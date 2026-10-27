package main

import (
    "context"
    "crypto/sha256"
    "encoding/hex"
    "encoding/json"
    "fmt"
    "log"
    "math/rand"
    "net/http"
    "os"
    "os/signal"
    "regexp"
    "strconv"
    "strings"
    "sync"
    "sync/atomic"
    "syscall"
    "time"

    "github.com/gorilla/mux"
    "github.com/gorilla/websocket"
    "golang.org/x/time/rate"
)

// ------------------------------------------------------------
// Types & Constants
// ------------------------------------------------------------

type TransactionStatus string

const (
    StatusPending   TransactionStatus = "PENDING"
    StatusRelayed   TransactionStatus = "RELAYED"
    StatusConfirmed TransactionStatus = "CONFIRMED"
    StatusFailed    TransactionStatus = "FAILED"
)

var SupportedTokens = []string{"OPUS", "ETH", "BTC", "SOL", "USDC"}

// RelayedTx models an on-chain or meta‑transaction handled by the relay microservice.
type RelayedTx struct {
    TxHash    string            `json:"tx_hash"`
    From      string            `json:"from"`
    To        string            `json:"to"`
    Token     string            `json:"token"`
    Amount    float64           `json:"amount"`
    Fee       float64           `json:"fee"`
    Nonce     uint64            `json:"nonce"`
    Signature string            `json:"signature,omitempty"`
    Status    TransactionStatus `json:"status"`
    Timestamp time.Time         `json:"timestamp"`
    BlockNum  uint64            `json:"block_number,omitempty"`
    ErrorMsg  string            `json:"error_msg,omitempty"`
}

// Wallet models a Web3 account holding multiple token assets with nonce tracking.
type Wallet struct {
    Address   string             `json:"address"`
    Balance   map[string]float64 `json:"balance"`
    Nonce     uint64             `json:"nonce"`
    CreatedAt time.Time          `json:"created_at"`
    UpdatedAt time.Time          `json:"updated_at"`
}

// Metrics tracks real‑time telemetry of the microservice.
type Metrics struct {
    TotalRequests   uint64 `json:"total_requests"`
    TotalTransfers  uint64 `json:"total_transfers"`
    TotalRelayed    uint64 `json:"total_relayed"`
    FailedTransfers uint64 `json:"failed_transfers"`
    ActiveWallets   uint64 `json:"active_wallets"`
    MempoolSize     uint64 `json:"mempool_size"`
    UptimeSeconds   uint64 `json:"uptime_seconds"`
}

// WebSocketMessage represents a real‑time update pushed to clients.
type WebSocketMessage struct {
    Type      string      `json:"type"`
    Payload   interface{} `json:"payload"`
    Timestamp time.Time   `json:"timestamp"`
}

// WalletStore handles concurrent wallet storage, transaction indexing, and mempool relaying.
type WalletStore struct {
    mu           sync.RWMutex
    wallets      map[string]*Wallet
    txHistory    map[string][]*RelayedTx
    allTxs       map[string]*RelayedTx
    mempool      []*RelayedTx
    metrics      Metrics
    startTime    time.Time
    currentBlock uint64
    wsClients    map[*websocket.Conn]bool
    wsMu         sync.Mutex
    limiter      *rate.Limiter
}

// ------------------------------------------------------------
// Store Construction & Helpers
// ------------------------------------------------------------

func NewWalletStore() *WalletStore {
    store := &WalletStore{
        wallets:      make(map[string]*Wallet),
        txHistory:    make(map[string][]*RelayedTx),
        allTxs:       make(map[string]*RelayedTx),
        mempool:      make([]*RelayedTx, 0),
        startTime:    time.Now(),
        currentBlock: 18450200,
        wsClients:    make(map[*websocket.Conn]bool),
        limiter:      rate.NewLimiter(rate.Limit(100), 200), // 100 req/s, burst 200
    }

    // Seed the relayer gas‑station wallet
    relayer := &Wallet{
        Address: "0x000000000000000000000000000000000000dEaD",
        Balance: map[string]float64{
            "OPUS": 1000000.0,
            "ETH":  5000.0,
            "USDC": 5000000.0,
        },
        Nonce:     0,
        CreatedAt: time.Now(),
        UpdatedAt: time.Now(),
    }
    store.wallets[relayer.Address] = relayer
    atomic.StoreUint64(&store.metrics.ActiveWallets, 1)

    go store.blockProducer()
    go store.mempoolProcessor()
    go store.metricsUpdater()

    return store
}

func computeTxHash(from, to, token string, amount float64, nonce uint64, ts time.Time) string {
    data := fmt.Sprintf("%s:%s:%s:%.8f:%d:%d", from, to, token, amount, nonce, ts.UnixNano())
    hash := sha256.Sum256([]byte(data))
    return "0x" + hex.EncodeToString(hash[:])
}

func isValidAddress(addr string) bool {
    // Simple Ethereum‑style address validation (0x + 40 hex chars)
    re := regexp.MustCompile(`^0x[0-9a-fA-F]{40}$`)
    return re.MatchString(addr)
}

func isSupportedToken(tok string) bool {
    for _, t := range SupportedTokens {
        if strings.EqualFold(t, tok) {
            return true
        }
    }
    return false
}

// ------------------------------------------------------------
// WalletStore Methods
// ------------------------------------------------------------

func (s *WalletStore) CreateWallet(address string) (*Wallet, error) {
    if !isValidAddress(address) {
        return nil, fmt.Errorf("invalid address format")
    }
    s.mu.Lock()
    defer s.mu.Unlock()
    if _, exists := s.wallets[address]; exists {
        return nil, fmt.Errorf("wallet already exists")
    }
    w := &Wallet{
        Address:   address,
        Balance:   make(map[string]float64),
        Nonce:     0,
        CreatedAt: time.Now(),
        UpdatedAt: time.Now(),
    }
    s.wallets[address] = w
    atomic.AddUint64(&s.metrics.ActiveWallets, 1)
    return w, nil
}

func (s *WalletStore) GetWallet(address string) (*Wallet, bool) {
    s.mu.RLock()
    defer s.mu.RUnlock()
    w, ok := s.wallets[address]
    return w, ok
}

func (s *WalletStore) SubmitTx(tx *RelayedTx) (*RelayedTx, error) {
    // Basic validation
    if !isValidAddress(tx.From) || !isValidAddress(tx.To) {
        return nil, fmt.Errorf("invalid from/to address")
    }
    if !isSupportedToken(tx.Token) {
        return nil, fmt.Errorf("unsupported token %s", tx.Token)
    }
    if tx.Amount <= 0 {
        return nil, fmt.Errorf("amount must be positive")
    }
    if tx.Fee < 0 {
        return nil, fmt.Errorf("fee cannot be negative")
    }

    s.mu.Lock()
    defer s.mu.Unlock()

    fromWallet, ok := s.wallets[tx.From]
    if !ok {
        return nil, fmt.Errorf("sender wallet not found")
    }
    // Ensure sufficient balance (including fee)
    total := tx.Amount + tx.Fee
    bal := fromWallet.Balance[tx.Token]
    if bal < total {
        return nil, fmt.Errorf("insufficient balance: have %.8f %s, need %.8f", bal, tx.Token, total)
    }

    // Deduct balance and increment nonce
    fromWallet.Balance[tx.Token] = bal - total
    fromWallet.Nonce++
    tx.Nonce = fromWallet.Nonce
    tx.Timestamp = time.Now()
    tx.Status = StatusPending
    tx.TxHash = computeTxHash(tx.From, tx.To, tx.Token, tx.Amount, tx.Nonce, tx.Timestamp)

    // Store transaction
    s.allTxs[tx.TxHash] = tx
    s.txHistory[tx.From] = append(s.txHistory[tx.From], tx)
    s.txHistory[tx.To] = append(s.txHistory[tx.To], tx)
    s.mempool = append(s.mempool, tx)
    atomic.AddUint64(&s.metrics.TotalTransfers, 1)
    atomic.AddUint64(&s.metrics.MempoolSize, 1)

    // Broadcast pending tx to WS clients
    s.broadcastWS(WebSocketMessage{Type: "tx_pending", Payload: tx, Timestamp: time.Now()})

    return tx, nil
}

func (s *WalletStore) GetTx(hash string) (*RelayedTx, bool) {
    s.mu.RLock()
    defer s.mu.RUnlock()
    tx, ok := s.allTxs[hash]
    return tx, ok
}

func (s *WalletStore) GetTxHistory(address string) ([]*RelayedTx, bool) {
    s.mu.RLock()
    defer s.mu.RUnlock()
    hist, ok := s.txHistory[address]
    return hist, ok
}

func (s *WalletStore) broadcastWS(msg WebSocketMessage) {
    s.wsMu.Lock()
    defer s.wsMu.Unlock()
    for conn := range s.wsClients {
        if err := conn.WriteJSON(msg); err != nil {
            // Remove faulty connections
            conn.Close()
            delete(s.wsClients, conn)
        }
    }
}

func (s *WalletStore) addWSClient(conn *websocket.Conn) {
    s.wsMu.Lock()
    s.wsClients[conn] = true
    s.wsMu.Unlock()
}

func (s *WalletStore) removeWSClient(conn *websocket.Conn) {
    s.wsMu.Lock()
    if _, ok := s.wsClients[conn]; ok {
        conn.Close()
        delete(s.wsClients, conn)
    }
    s.wsMu.Unlock()
}

// ------------------------------------------------------------
// Background Goroutines
// ------------------------------------------------------------

func (s *WalletStore) blockProducer() {
    ticker := time.NewTicker(5 * time.Second)
    defer ticker.Stop()
    for range ticker.C {
        s.mu.Lock()
        s.currentBlock++
        s.mu.Unlock()
        // Broadcast new block number
        s.broadcastWS(WebSocketMessage{Type: "new_block", Payload: map[string]uint64{"block_number": s.currentBlock}, Timestamp: time.Now()})
    }
}

func (s *WalletStore) mempoolProcessor() {
    // Simple processor that confirms pending txs after a random short delay
    for {
        time.Sleep(1 * time.Second)
        s.mu.Lock()
        if len(s.mempool) == 0 {
            s.mu.Unlock()
            continue
        }
        // Pop first transaction
        tx := s.mempool[0]
        s.mempool = s.mempool[1:]
        atomic.AddUint64(&s.metrics.MempoolSize, ^uint64(0)) // decrement
        // Simulate processing delay
        processingDelay := time.Duration(rand.Intn(500)+200) * time.Millisecond
        s.mu.Unlock()
        time.Sleep(processingDelay)
        s.mu.Lock()
        // Mark as confirmed and assign block number
        tx.Status = StatusConfirmed
        tx.BlockNum = s.currentBlock
        atomic.AddUint64(&s.metrics.TotalRelayed, 1)
        s.mu.Unlock()
        // Broadcast confirmation
        s.broadcastWS(WebSocketMessage{Type: "tx_confirmed", Payload: tx, Timestamp: time.Now()})
        s.mu.Lock()
        s.mu.Unlock()
    }
}

func (s *WalletStore) metricsUpdater() {
    ticker := time.NewTicker(10 * time.Second)
    defer ticker.Stop()
    for range ticker.C {
        uptime := uint64(time.Since(s.startTime).Seconds())
        atomic.StoreUint64(&s.metrics.UptimeSeconds, uptime)
    }
}

// ------------------------------------------------------------
// HTTP Handlers
// ------------------------------------------------------------

func (s *WalletStore) handleCreateWallet(w http.ResponseWriter, r *http.Request) {
    // Generate a random address (0x + 40 hex chars)
    var addr string
    for {
        b := make([]byte, 20)
        rand.Read(b)
        addr = "0x" + hex.EncodeToString(b)
        if _, exists := s.GetWallet(addr); !exists {
            break
        }
    }
    wallet, err := s.CreateWallet(addr)
    if err != nil {
        http.Error(w, err.Error(), http.StatusBadRequest)
        return
    }
    writeJSON(w, http.StatusCreated, wallet)
}

func (s *WalletStore) handleGetWallet(w http.ResponseWriter, r *http.Request) {
    vars := mux.Vars(r)
    addr := vars["address"]
    wallet, ok := s.GetWallet(addr)
    if !ok {
        http.Error(w, "wallet not found", http.StatusNotFound)
        return
    }
    writeJSON(w, http.StatusOK, wallet)
}

func (s *WalletStore) handleSubmitTx(w http.ResponseWriter, r *http.Request) {
    var payload struct {
        From  string  `json:"from"`
        To    string  `json:"to"`
        Token string  `json:"token"`
        Amount float64 `json:"amount"`
        Fee   float64 `json:"fee"`
    }
    if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
        http.Error(w, "invalid json payload", http.StatusBadRequest)
        return
    }
    tx := &RelayedTx{
        From:  payload.From,
        To:    payload.To,
        Token: payload.Token,
        Amount: payload.Amount,
        Fee:   payload.Fee,
    }
    submitted, err := s.SubmitTx(tx)
    if err != nil {
        http.Error(w, err.Error(), http.StatusBadRequest)
        return
    }
    writeJSON(w, http.StatusAccepted, submitted)
}

func (s *WalletStore) handleGetTx(w http.ResponseWriter, r *http.Request) {
    vars := mux.Vars(r)
    hash := vars["hash"]
    tx, ok := s.GetTx(hash)
    if !ok {
        http.Error(w, "transaction not found", http.StatusNotFound)
        return
    }
    writeJSON(w, http.StatusOK, tx)
}

func (s *WalletStore) handleMetrics(w http.ResponseWriter, r *http.Request) {
    // Snapshot metrics atomically
    m := Metrics{
        TotalRequests:   atomic.LoadUint64(&s.metrics.TotalRequests),
        TotalTransfers:  atomic.LoadUint64(&s.metrics.TotalTransfers),
        TotalRelayed:    atomic.LoadUint64(&s.metrics.TotalRelayed),
        FailedTransfers: atomic.LoadUint64(&s.metrics.FailedTransfers),
        ActiveWallets:   atomic.LoadUint64(&s.metrics.ActiveWallets),
        MempoolSize:     atomic.LoadUint64(&s.metrics.MempoolSize),
        UptimeSeconds:   atomic.LoadUint64(&s.metrics.UptimeSeconds),
    }
    writeJSON(w, http.StatusOK, m)
}

var upgrader = websocket.Upgrader{CheckOrigin: func(r *http.Request) bool { return true }}

func (s *WalletStore) handleWebSocket(w http.ResponseWriter, r *http.Request) {
    conn, err := upgrader.Upgrade(w, r, nil)
    if err != nil {
        log.Printf("websocket upgrade error: %v", err)
        return
    }
    s.addWSClient(conn)
    // Simple read loop to keep connection alive; ignore messages.
    for {
        if _, _, err := conn.NextReader(); err != nil {
            s.removeWSClient(conn)
            break
        }
    }
}

// ------------------------------------------------------------
// Utility Functions
// ------------------------------------------------------------

func writeJSON(w http.ResponseWriter, status int, v interface{}) {
    w.Header().Set("Content-Type", "application/json")
    w.WriteHeader(status)
    json.NewEncoder(w).Encode(v)
}

// ------------------------------------------------------------
// Main Entry Point
// ------------------------------------------------------------

func main() {
    rand.Seed(time.Now().UnixNano())
    store := NewWalletStore()

    r := mux.NewRouter()
    api := r.PathPrefix("/api").Subrouter()
    api.HandleFunc("/wallets", store.handleCreateWallet).Methods("POST")
    api.HandleFunc("/wallets/{address}", store.handleGetWallet).Methods("GET")
    api.HandleFunc("/tx", store.handleSubmitTx).Methods("POST")
    api.HandleFunc("/tx/{hash}", store.handleGetTx).Methods("GET")
    api.HandleFunc("/metrics", store.handleMetrics).Methods("GET")
    api.HandleFunc("/ws", store.handleWebSocket).Methods("GET")

    srv := &http.Server{Addr: ":8080", Handler: r}

    // Graceful shutdown handling
    stop := make(chan os.Signal, 1)
    signal.Notify(stop, os.Interrupt, syscall.SIGTERM)
    go func() {
        log.Printf("Server listening on %s", srv.Addr)
        if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
            log.Fatalf("listen error: %v", err)
        }
    }()

    <-stop
    log.Println("Shutting down server...")
    ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
    defer cancel()
    if err := srv.Shutdown(ctx); err != nil {
        log.Fatalf("Server forced to shutdown: %v", err)
    }
    log.Println("Server exited gracefully")
}
