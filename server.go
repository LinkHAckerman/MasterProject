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
// Wallet Operations
// ------------------------------------------------------------

// Get returns a copy of the wallet to avoid race conditions.
func (s *WalletStore) Get(address string) (*Wallet, bool) {
    s.mu.RLock()
    defer s.mu.RUnlock()
    w, ok := s.wallets[address]
    if !ok {
        return nil, false
    }
    // Deep copy of balances
    balCopy := make(map[string]float64, len(w.Balance))
    for k, v := range w.Balance {
        balCopy[k] = v
    }
    copy := &Wallet{
        Address:   w.Address,
        Balance:   balCopy,
        Nonce:     w.Nonce,
        CreatedAt: w.CreatedAt,
        UpdatedAt: w.UpdatedAt,
    }
    return copy, true
}

// CreateWallet generates a new wallet with a random address (for demo purposes).
func (s *WalletStore) CreateWallet() *Wallet {
    // In a real system this would be a proper key‑pair generation.
    addr := fmt.Sprintf("0x%040x", rand.Uint64()<<32|rand.Uint64())
    w := &Wallet{
        Address:   addr,
        Balance:   map[string]float64{"OPUS": 0, "ETH": 0, "USDC": 0},
        Nonce:     0,
        CreatedAt: time.Now(),
        UpdatedAt: time.Now(),
    }
    s.mu.Lock()
    s.wallets[addr] = w
    atomic.AddUint64(&s.metrics.ActiveWallets, 1)
    s.mu.Unlock()
    return w
}

// SubmitTx validates and queues a transaction into the mempool.
func (s *WalletStore) SubmitTx(tx *RelayedTx) (*RelayedTx, error) {
    // Basic validation
    if !isValidAddress(tx.From) || !isValidAddress(tx.To) {
        return nil, fmt.Errorf("invalid address")
    }
    if !isSupportedToken(tx.Token) {
        return nil, fmt.Errorf("unsupported token")
    }
    if tx.Amount <= 0 {
        return nil, fmt.Errorf("amount must be positive")
    }
    // Ensure sender exists
    s.mu.RLock()
    sender, ok := s.wallets[tx.From]
    s.mu.RUnlock()
    if !ok {
        return nil, fmt.Errorf("sender wallet not found")
    }
    // Simple nonce check
    if tx.Nonce != sender.Nonce {
        return nil, fmt.Errorf("invalid nonce, expected %d", sender.Nonce)
    }
    // Compute hash and set fields
    tx.TxHash = computeTxHash(tx.From, tx.To, tx.Token, tx.Amount, tx.Nonce, time.Now())
    tx.Timestamp = time.Now()
    tx.Status = StatusPending
    // Queue
    s.mu.Lock()
    s.mempool = append(s.mempool, tx)
    s.allTxs[tx.TxHash] = tx
    atomic.AddUint64(&s.metrics.TotalTransfers, 1)
    atomic.AddUint64(&s.metrics.MempoolSize, 1)
    s.mu.Unlock()
    return tx, nil
}

// GetTx retrieves a transaction by hash.
func (s *WalletStore) GetTx(hash string) (*RelayedTx, bool) {
    s.mu.RLock()
    defer s.mu.RUnlock()
    tx, ok := s.allTxs[hash]
    if !ok {
        return nil, false
    }
    // Return a copy to avoid external mutation
    copy := *tx
    return &copy, true
}

// ------------------------------------------------------------
// Background Workers
// ------------------------------------------------------------

// blockProducer simulates block creation every 5 seconds.
func (s *WalletStore) blockProducer() {
    ticker := time.NewTicker(5 * time.Second)
    defer ticker.Stop()
    for range ticker.C {
        s.mu.Lock()
        s.currentBlock++
        s.mu.Unlock()
        // Broadcast new block number to WS clients
        s.broadcastWS("new_block", map[string]uint64{"block_number": s.currentBlock})
    }
}

// mempoolProcessor processes pending transactions, moves them to confirmed state.
func (s *WalletStore) mempoolProcessor() {
    for {
        time.Sleep(2 * time.Second)
        s.mu.Lock()
        if len(s.mempool) == 0 {
            s.mu.Unlock()
            continue
        }
        // Process a batch (for demo we process all)
        processed := s.mempool
        s.mempool = nil
        atomic.StoreUint64(&s.metrics.MempoolSize, 0)
        s.mu.Unlock()

        for _, tx := range processed {
            s.processTransaction(tx)
        }
    }
}

func (s *WalletStore) processTransaction(tx *RelayedTx) {
    s.mu.Lock()
    defer s.mu.Unlock()

    sender, ok1 := s.wallets[tx.From]
    receiver, ok2 := s.wallets[tx.To]
    if !ok1 || !ok2 {
        tx.Status = StatusFailed
        tx.ErrorMsg = "wallet not found"
        atomic.AddUint64(&s.metrics.FailedTransfers, 1)
        s.broadcastWS("tx_update", tx)
        return
    }
    // Simple fee model: 0.1% of amount, minimum 0.0001
    fee := tx.Amount * 0.001
    if fee < 0.0001 {
        fee = 0.0001
    }
    total := tx.Amount + fee
    bal := sender.Balance[tx.Token]
    if bal < total {
        tx.Status = StatusFailed
        tx.ErrorMsg = "insufficient balance"
        atomic.AddUint64(&s.metrics.FailedTransfers, 1)
        s.broadcastWS("tx_update", tx)
        return
    }
    // Deduct from sender
    sender.Balance[tx.Token] -= total
    sender.Nonce++
    sender.UpdatedAt = time.Now()
    // Credit receiver (no fee for receiver)
    if receiver.Balance == nil {
        receiver.Balance = make(map[string]float64)
    }
    receiver.Balance[tx.Token] += tx.Amount
    receiver.UpdatedAt = time.Now()

    // Update transaction status
    tx.Status = StatusConfirmed
    tx.BlockNum = s.currentBlock
    tx.Fee = fee
    tx.Timestamp = time.Now()
    // Record history
    s.txHistory[tx.From] = append(s.txHistory[tx.From], tx)
    s.txHistory[tx.To] = append(s.txHistory[tx.To], tx)
    atomic.AddUint64(&s.metrics.TotalRelayed, 1)
    s.broadcastWS("tx_update", tx)
}

// metricsUpdater updates uptime and other derived metrics periodically.
func (s *WalletStore) metricsUpdater() {
    ticker := time.NewTicker(10 * time.Second)
    defer ticker.Stop()
    for range ticker.C {
        uptime := uint64(time.Since(s.startTime).Seconds())
        atomic.StoreUint64(&s.metrics.UptimeSeconds, uptime)
    }
}

// ------------------------------------------------------------
// WebSocket Helpers
// ------------------------------------------------------------

var upgrader = websocket.Upgrader{CheckOrigin: func(r *http.Request) bool { return true }}

func (s *WalletStore) addWSClient(conn *websocket.Conn) {
    s.wsMu.Lock()
    s.wsClients[conn] = true
    s.wsMu.Unlock()
}

func (s *WalletStore) removeWSClient(conn *websocket.Conn) {
    s.wsMu.Lock()
    delete(s.wsClients, conn)
    s.wsMu.Unlock()
    conn.Close()
}

func (s *WalletStore) broadcastWS(msgType string, payload interface{}) {
    message := WebSocketMessage{Type: msgType, Payload: payload, Timestamp: time.Now()}
    data, err := json.Marshal(message)
    if err != nil {
        log.Printf("failed to marshal ws message: %v", err)
        return
    }
    s.wsMu.Lock()
    defer s.wsMu.Unlock()
    for conn := range s.wsClients {
        if err := conn.WriteMessage(websocket.TextMessage, data); err != nil {
            log.Printf("ws write error, removing client: %v", err)
            delete(s.wsClients, conn)
            conn.Close()
        }
    }
}

// ------------------------------------------------------------
// HTTP Handlers
// ------------------------------------------------------------

func (s *WalletStore) createWalletHandler(w http.ResponseWriter, r *http.Request) {
    wallet := s.CreateWallet()
    respondJSON(w, http.StatusCreated, wallet)
}

func (s *WalletStore) getWalletHandler(w http.ResponseWriter, r *http.Request) {
    addr := mux.Vars(r)["address"]
    wallet, ok := s.Get(addr)
    if !ok {
        http.Error(w, "wallet not found", http.StatusNotFound)
        return
    }
    respondJSON(w, http.StatusOK, wallet)
}

func (s *WalletStore) submitTxHandler(w http.ResponseWriter, r *http.Request) {
    var payload struct {
        From  string  `json:"from"`
        To    string  `json:"to"`
        Token string  `json:"token"`
        Amount float64 `json:"amount"`
    }
    if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
        http.Error(w, "invalid json", http.StatusBadRequest)
        return
    }
    // Retrieve sender to get nonce
    sender, ok := s.Get(payload.From)
    if !ok {
        http.Error(w, "sender not found", http.StatusBadRequest)
        return
    }
    tx := &RelayedTx{
        From:  payload.From,
        To:    payload.To,
        Token: payload.Token,
        Amount: payload.Amount,
        Nonce: sender.Nonce,
    }
    submitted, err := s.SubmitTx(tx)
    if err != nil {
        http.Error(w, err.Error(), http.StatusBadRequest)
        return
    }
    respondJSON(w, http.StatusAccepted, submitted)
}

func (s *WalletStore) getTxHandler(w http.ResponseWriter, r *http.Request) {
    hash := mux.Vars(r)["hash"]
    tx, ok := s.GetTx(hash)
    if !ok {
        http.Error(w, "transaction not found", http.StatusNotFound)
        return
    }
    respondJSON(w, http.StatusOK, tx)
}

func (s *WalletStore) wsHandler(w http.ResponseWriter, r *http.Request) {
    conn, err := upgrader.Upgrade(w, r, nil)
    if err != nil {
        log.Printf("ws upgrade error: %v", err)
        return
    }
    s.addWSClient(conn)
    // Simple read loop to keep connection alive; we ignore incoming messages.
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

func respondJSON(w http.ResponseWriter, status int, data interface{}) {
    w.Header().Set("Content-Type", "application/json")
    w.WriteHeader(status)
    json.NewEncoder(w).Encode(data)
}

// ------------------------------------------------------------
// Main
// ------------------------------------------------------------

func main() {
    store := NewWalletStore()
    r := mux.NewRouter()

    // REST API
    r.HandleFunc("/wallet", store.createWalletHandler).Methods("POST")
    r.HandleFunc("/wallet/{address}", store.getWalletHandler).Methods("GET")
    r.HandleFunc("/tx", store.submitTxHandler).Methods("POST")
    r.HandleFunc("/tx/{hash}", store.getTxHandler).Methods("GET")
    // WebSocket endpoint
    r.HandleFunc("/ws", store.wsHandler)

    srv := &http.Server{Addr: ":8080", Handler: r}

    // Graceful shutdown handling
    stop := make(chan os.Signal, 1)
    signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)
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
        log.Fatalf("Server shutdown failed:%+v", err)
    }
    log.Println("Server gracefully stopped")
}
