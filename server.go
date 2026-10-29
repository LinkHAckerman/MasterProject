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
// WalletStore Core Operations
// ------------------------------------------------------------

// CreateWallet generates a new wallet with a random address (for demo purposes).
func (s *WalletStore) CreateWallet() (*Wallet, error) {
    // In a real system this would be a proper key‑pair generation.
    addr := fmt.Sprintf("0x%040x", rand.Uint64())
    // Ensure uniqueness
    s.mu.Lock()
    defer s.mu.Unlock()
    if _, exists := s.wallets[addr]; exists {
        return nil, fmt.Errorf("address collision, try again")
    }
    w := &Wallet{
        Address:   addr,
        Balance:   map[string]float64{"OPUS": 0, "ETH": 0, "USDC": 0},
        Nonce:     0,
        CreatedAt: time.Now(),
        UpdatedAt: time.Now(),
    }
    s.wallets[addr] = w
    atomic.AddUint64(&s.metrics.ActiveWallets, 1)
    return w, nil
}

// GetWallet returns a copy of the wallet data for read‑only purposes.
func (s *WalletStore) GetWallet(addr string) (*Wallet, error) {
    s.mu.RLock()
    defer s.mu.RUnlock()
    w, ok := s.wallets[addr]
    if !ok {
        return nil, fmt.Errorf("wallet not found")
    }
    // Return a shallow copy to avoid callers mutating internal state.
    copyBal := make(map[string]float64, len(w.Balance))
    for k, v := range w.Balance {
        copyBal[k] = v
    }
    return &Wallet{
        Address:   w.Address,
        Balance:   copyBal,
        Nonce:     w.Nonce,
        CreatedAt: w.CreatedAt,
        UpdatedAt: w.UpdatedAt,
    }, nil
}

// SubmitTransaction validates, signs (mock), and places a transaction into the mempool.
func (s *WalletStore) SubmitTransaction(tx *RelayedTx) (*RelayedTx, error) {
    if !isValidAddress(tx.From) || !isValidAddress(tx.To) {
        return nil, fmt.Errorf("invalid address format")
    }
    if !isSupportedToken(tx.Token) {
        return nil, fmt.Errorf("unsupported token %s", tx.Token)
    }
    if tx.Amount <= 0 {
        return nil, fmt.Errorf("amount must be positive")
    }
    // Basic nonce handling & balance check
    s.mu.Lock()
    defer s.mu.Unlock()
    fromWallet, ok := s.wallets[tx.From]
    if !ok {
        return nil, fmt.Errorf("sender wallet not found")
    }
    if fromWallet.Nonce != tx.Nonce {
        return nil, fmt.Errorf("invalid nonce: expected %d", fromWallet.Nonce)
    }
    if bal, ok := fromWallet.Balance[tx.Token]; !ok || bal < tx.Amount+tx.Fee {
        return nil, fmt.Errorf("insufficient balance")
    }
    // Mock signature (in reality would be cryptographic)
    tx.Signature = fmt.Sprintf("sig-%d", rand.Int63())
    tx.Status = StatusPending
    tx.Timestamp = time.Now()
    tx.TxHash = computeTxHash(tx.From, tx.To, tx.Token, tx.Amount, tx.Nonce, tx.Timestamp)
    // Deduct fee immediately; amount will be moved on confirmation.
    fromWallet.Balance[tx.Token] -= tx.Fee
    fromWallet.Nonce++
    fromWallet.UpdatedAt = time.Now()
    // Add to mempool
    s.mempool = append(s.mempool, tx)
    s.allTxs[tx.TxHash] = tx
    atomic.AddUint64(&s.metrics.TotalTransfers, 1)
    atomic.AddUint64(&s.metrics.MempoolSize, 1)
    // Broadcast to WS listeners
    go s.broadcastWS("new_tx", tx)
    return tx, nil
}

// ------------------------------------------------------------
// Background Workers
// ------------------------------------------------------------

// blockProducer simulates block creation every 5 seconds, confirming pending txs.
func (s *WalletStore) blockProducer() {
    ticker := time.NewTicker(5 * time.Second)
    defer ticker.Stop()
    for range ticker.C {
        s.mu.Lock()
        s.currentBlock++
        confirmed := make([]*RelayedTx, 0, len(s.mempool))
        remaining := make([]*RelayedTx, 0, len(s.mempool))
        for _, tx := range s.mempool {
            if tx.Status == StatusPending {
                // Apply transfer
                toWallet, ok := s.wallets[tx.To]
                if !ok {
                    // Auto‑create destination wallet for demo purposes
                    toWallet = &Wallet{Address: tx.To, Balance: map[string]float64{}, Nonce: 0, CreatedAt: time.Now(), UpdatedAt: time.Now()}
                    s.wallets[tx.To] = toWallet
                    atomic.AddUint64(&s.metrics.ActiveWallets, 1)
                }
                // Credit amount (fee already deducted from sender)
                toWallet.Balance[tx.Token] = toWallet.Balance[tx.Token] + tx.Amount
                toWallet.UpdatedAt = time.Now()
                // Update tx status
                tx.Status = StatusConfirmed
                tx.BlockNum = s.currentBlock
                tx.Timestamp = time.Now()
                confirmed = append(confirmed, tx)
                // Record history
                s.txHistory[tx.From] = append(s.txHistory[tx.From], tx)
                s.txHistory[tx.To] = append(s.txHistory[tx.To], tx)
                atomic.AddUint64(&s.metrics.TotalRelayed, 1)
            } else {
                remaining = append(remaining, tx)
            }
        }
        s.mempool = remaining
        atomic.StoreUint64(&s.metrics.MempoolSize, uint64(len(s.mempool)))
        s.mu.Unlock()
        // Notify listeners about the new block
        go s.broadcastWS("new_block", map[string]interface{}{"block_number": s.currentBlock, "tx_count": len(confirmed)})
    }
}

// mempoolProcessor could be used for fee market or eviction; here it simply logs.
func (s *WalletStore) mempoolProcessor() {
    ticker := time.NewTicker(30 * time.Second)
    defer ticker.Stop()
    for range ticker.C {
        s.mu.RLock()
        size := len(s.mempool)
        s.mu.RUnlock()
        log.Printf("[mempool] current size: %d", size)
    }
}

// metricsUpdater updates uptime and other derived metrics every second.
func (s *WalletStore) metricsUpdater() {
    ticker := time.NewTicker(1 * time.Second)
    defer ticker.Stop()
    for range ticker.C {
        uptime := uint64(time.Since(s.startTime).Seconds())
        atomic.StoreUint64(&s.metrics.UptimeSeconds, uptime)
    }
}

// ------------------------------------------------------------
// WebSocket Helpers
// ------------------------------------------------------------

func (s *WalletStore) broadcastWS(msgType string, payload interface{}) {
    s.wsMu.Lock()
    defer s.wsMu.Unlock()
    if len(s.wsClients) == 0 {
        return
    }
    message := WebSocketMessage{Type: msgType, Payload: payload, Timestamp: time.Now()}
    data, err := json.Marshal(message)
    if err != nil {
        log.Printf("[ws] marshal error: %v", err)
        return
    }
    for conn := range s.wsClients {
        if err := conn.WriteMessage(websocket.TextMessage, data); err != nil {
            log.Printf("[ws] write error, removing client: %v", err)
            conn.Close()
            delete(s.wsClients, conn)
        }
    }
}

// ------------------------------------------------------------
// HTTP Handlers
// ------------------------------------------------------------

func (s *WalletStore) handleCreateWallet(w http.ResponseWriter, r *http.Request) {
    atomic.AddUint64(&s.metrics.TotalRequests, 1)
    if err := s.limiter.Wait(r.Context()); err != nil {
        http.Error(w, "rate limit exceeded", http.StatusTooManyRequests)
        return
    }
    wallet, err := s.CreateWallet()
    if err != nil {
        http.Error(w, err.Error(), http.StatusInternalServerError)
        return
    }
    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(wallet)
}

func (s *WalletStore) handleGetWallet(w http.ResponseWriter, r *http.Request) {
    atomic.AddUint64(&s.metrics.TotalRequests, 1)
    if err := s.limiter.Wait(r.Context()); err != nil {
        http.Error(w, "rate limit exceeded", http.StatusTooManyRequests)
        return
    }
    vars := mux.Vars(r)
    addr := vars["address"]
    wallet, err := s.GetWallet(addr)
    if err != nil {
        http.Error(w, err.Error(), http.StatusNotFound)
        return
    }
    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(wallet)
}

type submitTxRequest struct {
    From      string  `json:"from"`
    To        string  `json:"to"`
    Token     string  `json:"token"`
    Amount    float64 `json:"amount"`
    Fee       float64 `json:"fee"`
    Nonce     uint64  `json:"nonce"`
    Signature string  `json:"signature,omitempty"`
}

func (s *WalletStore) handleSubmitTx(w http.ResponseWriter, r *http.Request) {
    atomic.AddUint64(&s.metrics.TotalRequests, 1)
    if err := s.limiter.Wait(r.Context()); err != nil {
        http.Error(w, "rate limit exceeded", http.StatusTooManyRequests)
        return
    }
    var req submitTxRequest
    if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
        http.Error(w, "invalid JSON payload", http.StatusBadRequest)
        return
    }
    tx := &RelayedTx{
        From:      req.From,
        To:        req.To,
        Token:     req.Token,
        Amount:    req.Amount,
        Fee:       req.Fee,
        Nonce:     req.Nonce,
        Signature: req.Signature,
    }
    submitted, err := s.SubmitTransaction(tx)
    if err != nil {
        http.Error(w, err.Error(), http.StatusBadRequest)
        return
    }
    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(submitted)
}

func (s *WalletStore) handleMetrics(w http.ResponseWriter, r *http.Request) {
    atomic.AddUint64(&s.metrics.TotalRequests, 1)
    if err := s.limiter.Wait(r.Context()); err != nil {
        http.Error(w, "rate limit exceeded", http.StatusTooManyRequests)
        return
    }
    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(s.metrics)
}

var upgrader = websocket.Upgrader{CheckOrigin: func(r *http.Request) bool { return true }}

func (s *WalletStore) handleWS(w http.ResponseWriter, r *http.Request) {
    conn, err := upgrader.Upgrade(w, r, nil)
    if err != nil {
        log.Printf("[ws] upgrade error: %v", err)
        return
    }
    s.wsMu.Lock()
    s.wsClients[conn] = true
    s.wsMu.Unlock()
    // Simple read loop to keep connection alive; we ignore incoming messages.
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

// ------------------------------------------------------------
// Main – Server bootstrap & graceful shutdown
// ------------------------------------------------------------

func main() {
    store := NewWalletStore()
    r := mux.NewRouter()
    api := r.PathPrefix("/api/v1").Subrouter()
    api.HandleFunc("/wallet", store.handleCreateWallet).Methods("POST")
    api.HandleFunc("/wallet/{address}", store.handleGetWallet).Methods("GET")
    api.HandleFunc("/tx", store.handleSubmitTx).Methods("POST")
    api.HandleFunc("/metrics", store.handleMetrics).Methods("GET")
    r.HandleFunc("/ws", store.handleWS)

    srv := &http.Server{
        Addr:    ":8080",
        Handler: r,
    }

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
    ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
    defer cancel()
    if err := srv.Shutdown(ctx); err != nil {
        log.Fatalf("Server forced to shutdown: %v", err)
    }
    log.Println("Server exited gracefully")
}
