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
// WalletStore Core Operations
// ------------------------------------------------------------

func (s *WalletStore) CreateWallet() *Wallet {
    // Generate a pseudo‑random address (not cryptographically secure, fine for demo)
    var addr string
    for {
        b := make([]byte, 20)
        rand.Read(b)
        addr = "0x" + hex.EncodeToString(b)
        if !isValidAddress(addr) {
            continue
        }
        s.mu.RLock()
        _, exists := s.wallets[addr]
        s.mu.RUnlock()
        if !exists {
            break
        }
    }
    w := &Wallet{
        Address:   addr,
        Balance:   make(map[string]float64),
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

func (s *WalletStore) GetWallet(addr string) (*Wallet, bool) {
    s.mu.RLock()
    defer s.mu.RUnlock()
    w, ok := s.wallets[addr]
    return w, ok
}

func (s *WalletStore) SubmitTx(tx *RelayedTx) (*RelayedTx, error) {
    // Basic validation
    if !isValidAddress(tx.From) || !isValidAddress(tx.To) {
        return nil, fmt.Errorf("invalid address format")
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
    toWallet, ok := s.wallets[tx.To]
    if !ok {
        // Auto‑create receiver wallet with empty balances
        toWallet = &Wallet{Address: tx.To, Balance: make(map[string]float64), Nonce: 0, CreatedAt: time.Now(), UpdatedAt: time.Now()}
        s.wallets[tx.To] = toWallet
        atomic.AddUint64(&s.metrics.ActiveWallets, 1)
    }

    // Check nonce ordering
    if tx.Nonce != fromWallet.Nonce {
        return nil, fmt.Errorf("invalid nonce: expected %d, got %d", fromWallet.Nonce, tx.Nonce)
    }

    // Check sufficient balance (amount + fee)
    total := tx.Amount + tx.Fee
    bal := fromWallet.Balance[tx.Token]
    if bal < total {
        return nil, fmt.Errorf("insufficient balance: have %.8f %s, need %.8f", bal, tx.Token, total)
    }

    // Deduct immediately (simplified model)
    fromWallet.Balance[tx.Token] = bal - total
    fromWallet.Nonce++
    fromWallet.UpdatedAt = time.Now()

    // Credit receiver on confirmation (not now)
    // Store transaction
    tx.TxHash = computeTxHash(tx.From, tx.To, tx.Token, tx.Amount, tx.Nonce, time.Now())
    tx.Status = StatusPending
    tx.Timestamp = time.Now()
    s.allTxs[tx.TxHash] = tx
    s.txHistory[tx.From] = append(s.txHistory[tx.From], tx)
    s.txHistory[tx.To] = append(s.txHistory[tx.To], tx)
    s.mempool = append(s.mempool, tx)
    atomic.AddUint64(&s.metrics.TotalTransfers, 1)
    atomic.StoreUint64(&s.metrics.MempoolSize, uint64(len(s.mempool)))
    return tx, nil
}

func (s *WalletStore) GetTx(hash string) (*RelayedTx, bool) {
    s.mu.RLock()
    defer s.mu.RUnlock()
    tx, ok := s.allTxs[hash]
    return tx, ok
}

// ------------------------------------------------------------
// Background Workers
// ------------------------------------------------------------

func (s *WalletStore) blockProducer() {
    ticker := time.NewTicker(5 * time.Second)
    defer ticker.Stop()
    for range ticker.C {
        s.mu.Lock()
        s.currentBlock++
        // Process mempool: confirm all pending txs
        confirmed := make([]*RelayedTx, 0, len(s.mempool))
        for _, tx := range s.mempool {
            // Credit receiver now that block is produced
            receiver := s.wallets[tx.To]
            if receiver != nil {
                receiver.Balance[tx.Token] += tx.Amount
                receiver.UpdatedAt = time.Now()
            }
            tx.Status = StatusConfirmed
            tx.BlockNum = s.currentBlock
            tx.Timestamp = time.Now()
            confirmed = append(confirmed, tx)
            atomic.AddUint64(&s.metrics.TotalRelayed, 1)
        }
        // Clear mempool
        s.mempool = s.mempool[:0]
        atomic.StoreUint64(&s.metrics.MempoolSize, 0)
        s.mu.Unlock()

        // Broadcast block and tx confirmations via WebSocket
        s.broadcastMessage("new_block", map[string]interface{}{"block_number": s.currentBlock})
        for _, tx := range confirmed {
            s.broadcastMessage("tx_confirmed", tx)
        }
    }
}

func (s *WalletStore) metricsUpdater() {
    ticker := time.NewTicker(1 * time.Second)
    defer ticker.Stop()
    for range ticker.C {
        uptime := uint64(time.Since(s.startTime).Seconds())
        atomic.StoreUint64(&s.metrics.UptimeSeconds, uptime)
    }
}

func (s *WalletStore) broadcastMessage(msgType string, payload interface{}) {
    msg := WebSocketMessage{Type: msgType, Payload: payload, Timestamp: time.Now()}
    data, err := json.Marshal(msg)
    if err != nil {
        log.Printf("failed to marshal ws message: %v", err)
        return
    }
    s.wsMu.Lock()
    defer s.wsMu.Unlock()
    for conn := range s.wsClients {
        if err := conn.WriteMessage(websocket.TextMessage, data); err != nil {
            log.Printf("ws write error, removing client: %v", err)
            conn.Close()
            delete(s.wsClients, conn)
        }
    }
}

// ------------------------------------------------------------
// HTTP Handlers
// ------------------------------------------------------------

func (s *WalletStore) rateLimit(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        if err := s.limiter.Wait(r.Context()); err != nil {
            http.Error(w, "rate limit exceeded", http.StatusTooManyRequests)
            return
        }
        atomic.AddUint64(&s.metrics.TotalRequests, 1)
        next.ServeHTTP(w, r)
    })
}

func (s *WalletStore) createWalletHandler(w http.ResponseWriter, r *http.Request) {
    wlt := s.CreateWallet()
    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(wlt)
}

func (s *WalletStore) getWalletHandler(w http.ResponseWriter, r *http.Request) {
    vars := mux.Vars(r)
    addr := vars["address"]
    if !isValidAddress(addr) {
        http.Error(w, "invalid address", http.StatusBadRequest)
        return
    }
    wlt, ok := s.GetWallet(addr)
    if !ok {
        http.Error(w, "wallet not found", http.StatusNotFound)
        return
    }
    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(wlt)
}

func (s *WalletStore) submitTxHandler(w http.ResponseWriter, r *http.Request) {
    var payload struct {
        From  string  `json:"from"`
        To    string  `json:"to"`
        Token string  `json:"token"`
        Amount float64 `json:"amount"`
        Fee    float64 `json:"fee"`
    }
    if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
        http.Error(w, "invalid json payload", http.StatusBadRequest)
        return
    }
    // Retrieve sender nonce
    s.mu.RLock()
    sender, ok := s.wallets[payload.From]
    s.mu.RUnlock()
    if !ok {
        http.Error(w, "sender wallet not found", http.StatusNotFound)
        return
    }
    tx := &RelayedTx{
        From:  payload.From,
        To:    payload.To,
        Token: payload.Token,
        Amount: payload.Amount,
        Fee:    payload.Fee,
        Nonce:  sender.Nonce,
    }
    submitted, err := s.SubmitTx(tx)
    if err != nil {
        http.Error(w, err.Error(), http.StatusBadRequest)
        return
    }
    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(submitted)
}

func (s *WalletStore) getTxHandler(w http.ResponseWriter, r *http.Request) {
    vars := mux.Vars(r)
    hash := vars["hash"]
    tx, ok := s.GetTx(hash)
    if !ok {
        http.Error(w, "transaction not found", http.StatusNotFound)
        return
    }
    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(tx)
}

var upgrader = websocket.Upgrader{CheckOrigin: func(r *http.Request) bool { return true }}

func (s *WalletStore) wsHandler(w http.ResponseWriter, r *http.Request) {
    conn, err := upgrader.Upgrade(w, r, nil)
    if err != nil {
        log.Printf("websocket upgrade failed: %v", err)
        return
    }
    s.wsMu.Lock()
    s.wsClients[conn] = true
    s.wsMu.Unlock()
    // Simple read loop to keep connection alive
    for {
        if _, _, err := conn.NextReader(); err != nil {
            s.wsMu.Lock()
            delete(s.wsClients, conn)
            s.wsMu.Unlock()
            conn.Close()
            break
        }
    }
}

func (s *WalletStore) healthHandler(w http.ResponseWriter, r *http.Request) {
    w.WriteHeader(http.StatusOK)
    w.Write([]byte("OK"))
}

func (s *WalletStore) metricsHandler(w http.ResponseWriter, r *http.Request) {
    s.mu.RLock()
    defer s.mu.RUnlock()
    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(s.metrics)
}

// ------------------------------------------------------------
// Main – Server bootstrap & graceful shutdown
// ------------------------------------------------------------

func main() {
    store := NewWalletStore()
    r := mux.NewRouter()

    api := r.PathPrefix("/api").Subrouter()
    api.Use(store.rateLimit)
    api.HandleFunc("/wallet", store.createWalletHandler).Methods("POST")
    api.HandleFunc("/wallet/{address}", store.getWalletHandler).Methods("GET")
    api.HandleFunc("/tx", store.submitTxHandler).Methods("POST")
    api.HandleFunc("/tx/{hash}", store.getTxHandler).Methods("GET")
    api.HandleFunc("/metrics", store.metricsHandler).Methods("GET")
    api.HandleFunc("/health", store.healthHandler).Methods("GET")
    r.HandleFunc("/ws", store.wsHandler)

    srv := &http.Server{Addr: ":8080", Handler: r}

    // Run server in goroutine
    go func() {
        log.Printf("Magnum Opus relay service listening on %s", srv.Addr)
        if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
            log.Fatalf("listen: %s\n", err)
        }
    }()

    // Graceful shutdown handling
    quit := make(chan os.Signal, 1)
    signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
    <-quit
    log.Println("Shutting down server...")
    ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
    defer cancel()
    if err := srv.Shutdown(ctx); err != nil {
        log.Fatalf("Server forced to shutdown: %v", err)
    }
    log.Println("Server exiting")
}
