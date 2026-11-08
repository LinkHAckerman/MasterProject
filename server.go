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
// Types & Constants (unchanged from original snapshot)
// ------------------------------------------------------------

type TransactionStatus string

const (
    StatusPending   TransactionStatus = "PENDING"
    StatusRelayed   TransactionStatus = "RELAYED"
    StatusConfirmed TransactionStatus = "CONFIRMED"
    StatusFailed    TransactionStatus = "FAILED"
)

var SupportedTokens = []string{"OPUS", "ETH", "BTC", "SOL", "USDC"}

var addressRegex = regexp.MustCompile(`^0x[a-fA-F0-9]{40}$`)

var upgrader = websocket.Upgrader{
    CheckOrigin: func(r *http.Request) bool { return true },
    ReadBufferSize:  1024,
    WriteBufferSize: 1024,
}

// RelayedTx models an on-chain or meta-transaction handled by the relay microservice.
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

// Metrics tracks real-time telemetry of the microservice.
type Metrics struct {
    TotalRequests   uint64 `json:"total_requests"`
    TotalTransfers  uint64 `json:"total_transfers"`
    TotalRelayed    uint64 `json:"total_relayed"`
    FailedTransfers uint64 `json:"failed_transfers"`
    ActiveWallets   uint64 `json:"active_wallets"`
    MempoolSize     uint64 `json:"mempool_size"`
    UptimeSeconds   uint64 `json:"uptime_seconds"`
}

// WebSocketMessage represents a real-time update pushed to clients.
type WebSocketMessage struct {
    Type      string      `json:"type"`
    Payload   interface{} `json:"payload"`
    Timestamp time.Time   `json:"timestamp"`
}

// APIResponse standardized response envelope.
type APIResponse struct {
    Success bool        `json:"success"`
    Data    interface{} `json:"data,omitempty"`
    Error   string      `json:"error,omitempty"`
}

// CreateWalletRequest request payload for creating a wallet.
type CreateWalletRequest struct {
    Address string `json:"address"`
}

// TransferRequest request payload for standard transfer.
type TransferRequest struct {
    From   string  `json:"from"`
    To     string  `json:"to"`
    Token  string  `json:"token"`
    Amount float64 `json:"amount"`
}

// RelayTxRequest payload for meta-transactions.
type RelayTxRequest struct {
    From      string  `json:"from"`
    To        string  `json:"to"`
    Token     string  `json:"token"`
    Amount    float64 `json:"amount"`
    Fee       float64 `json:"fee"`
    Nonce     uint64  `json:"nonce"`
    Signature string  `json:"signature"`
}

// BlockInfo metadata about a mined block.
type BlockInfo struct {
    BlockNumber uint64       `json:"block_number"`
    BlockHash   string       `json:"block_hash"`
    TxCount     int          `json:"tx_count"`
    Timestamp   time.Time    `json:"timestamp"`
    Txs         []*RelayedTx `json:"transactions"`
}

// WalletStore handles concurrent wallet storage, transaction indexing, and mempool relaying.
type WalletStore struct {
    mu           sync.RWMutex
    wallets      map[string]*Wallet
    txHistory    map[string][]*RelayedTx
    allTxs       map[string]*RelayedTx
    mempool      []*RelayedTx
    blocks       []*BlockInfo
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
    ws := &WalletStore{
        wallets:      make(map[string]*Wallet),
        txHistory:    make(map[string][]*RelayedTx),
        allTxs:       make(map[string]*RelayedTx),
        mempool:      make([]*RelayedTx, 0),
        blocks:       make([]*BlockInfo, 0),
        metrics:      Metrics{},
        startTime:    time.Now(),
        currentBlock: 0,
        wsClients:    make(map[*websocket.Conn]bool),
        limiter:      rate.NewLimiter(rate.Every(time.Second), 100), // 100 req/s burst
    }
    // Background workers
    go ws.mempoolProcessor()
    go ws.blockMiner()
    go ws.uptimeTicker()
    return ws
}

func (ws *WalletStore) uptimeTicker() {
    ticker := time.NewTicker(time.Second)
    defer ticker.Stop()
    for range ticker.C {
        atomic.StoreUint64(&ws.metrics.UptimeSeconds, uint64(time.Since(ws.startTime).Seconds()))
    }
}

// -------------------- Wallet Operations --------------------

func (ws *WalletStore) CreateWallet(address string) (*Wallet, error) {
    if !addressRegex.MatchString(address) {
        return nil, fmt.Errorf("invalid address format")
    }
    ws.mu.Lock()
    defer ws.mu.Unlock()
    if _, exists := ws.wallets[address]; exists {
        return nil, fmt.Errorf("wallet already exists")
    }
    bal := make(map[string]float64)
    for _, t := range SupportedTokens {
        bal[t] = 0.0
    }
    w := &Wallet{Address: address, Balance: bal, Nonce: 0, CreatedAt: time.Now(), UpdatedAt: time.Now()}
    ws.wallets[address] = w
    atomic.AddUint64(&ws.metrics.ActiveWallets, 1)
    return w, nil
}

func (ws *WalletStore) GetWallet(address string) (*Wallet, bool) {
    ws.mu.RLock()
    defer ws.mu.RUnlock()
    w, ok := ws.wallets[address]
    return w, ok
}

// -------------------- Transaction Logic --------------------

func (ws *WalletStore) Transfer(req TransferRequest) (*RelayedTx, error) {
    if !addressRegex.MatchString(req.From) || !addressRegex.MatchString(req.To) {
        return nil, fmt.Errorf("invalid address")
    }
    if req.Amount <= 0 {
        return nil, fmt.Errorf("amount must be positive")
    }
    if !contains(SupportedTokens, req.Token) {
        return nil, fmt.Errorf("unsupported token")
    }
    ws.mu.Lock()
    defer ws.mu.Unlock()
    fromW, ok1 := ws.wallets[req.From]
    toW, ok2 := ws.wallets[req.To]
    if !ok1 || !ok2 {
        return nil, fmt.Errorf("wallet not found")
    }
    if fromW.Balance[req.Token] < req.Amount {
        return nil, fmt.Errorf("insufficient balance")
    }
    // Update balances
    fromW.Balance[req.Token] -= req.Amount
    toW.Balance[req.Token] += req.Amount
    fromW.Nonce++
    now := time.Now()
    tx := &RelayedTx{
        TxHash:    ws.generateTxHash(req.From, req.To, req.Token, req.Amount, now),
        From:      req.From,
        To:        req.To,
        Token:     req.Token,
        Amount:    req.Amount,
        Fee:       0,
        Nonce:     fromW.Nonce,
        Status:    StatusConfirmed,
        Timestamp: now,
    }
    ws.allTxs[tx.TxHash] = tx
    ws.txHistory[req.From] = append(ws.txHistory[req.From], tx)
    ws.txHistory[req.To] = append(ws.txHistory[req.To], tx)
    atomic.AddUint64(&ws.metrics.TotalTransfers, 1)
    ws.broadcastWS("transfer", tx)
    return tx, nil
}

func (ws *WalletStore) RelayTransaction(req RelayTxRequest) (*RelayedTx, error) {
    if !addressRegex.MatchString(req.From) || !addressRegex.MatchString(req.To) {
        return nil, fmt.Errorf("invalid address")
    }
    if req.Amount <= 0 {
        return nil, fmt.Errorf("amount must be positive")
    }
    if !contains(SupportedTokens, req.Token) {
        return nil, fmt.Errorf("unsupported token")
    }
    ws.mu.Lock()
    defer ws.mu.Unlock()
    // Basic nonce check (optional)
    fromW, ok := ws.wallets[req.From]
    if !ok {
        return nil, fmt.Errorf("sender wallet not found")
    }
    if req.Nonce != fromW.Nonce+1 {
        return nil, fmt.Errorf("invalid nonce, expected %d", fromW.Nonce+1)
    }
    now := time.Now()
    tx := &RelayedTx{
        TxHash:    ws.generateTxHash(req.From, req.To, req.Token, req.Amount, now),
        From:      req.From,
        To:        req.To,
        Token:     req.Token,
        Amount:    req.Amount,
        Fee:       req.Fee,
        Nonce:     req.Nonce,
        Signature: req.Signature,
        Status:    StatusPending,
        Timestamp: now,
    }
    ws.mempool = append(ws.mempool, tx)
    ws.allTxs[tx.TxHash] = tx
    atomic.AddUint64(&ws.metrics.TotalRelayed, 1)
    atomic.StoreUint64(&ws.metrics.MempoolSize, uint64(len(ws.mempool)))
    ws.broadcastWS("mempool_add", tx)
    return tx, nil
}

func (ws *WalletStore) generateTxHash(from, to, token string, amount float64, t time.Time) string {
    h := sha256.New()
    data := fmt.Sprintf("%s|%s|%s|%f|%d", from, to, token, amount, t.UnixNano())
    h.Write([]byte(data))
    return hex.EncodeToString(h.Sum(nil))
}

// -------------------- Mempool & Block Processing --------------------

func (ws *WalletStore) mempoolProcessor() {
    ticker := time.NewTicker(2 * time.Second)
    defer ticker.Stop()
    for range ticker.C {
        ws.mu.Lock()
        if len(ws.mempool) == 0 {
            ws.mu.Unlock()
            continue
        }
        // Simple processing: mark all as RELAYED (simulating verification)
        for _, tx := range ws.mempool {
            tx.Status = StatusRelayed
        }
        ws.mu.Unlock()
    }
}

func (ws *WalletStore) blockMiner() {
    ticker := time.NewTicker(10 * time.Second)
    defer ticker.Stop()
    for range ticker.C {
        ws.mu.Lock()
        if len(ws.mempool) == 0 {
            ws.mu.Unlock()
            continue
        }
        // Create block from current mempool
        blockTxs := ws.mempool
        ws.mempool = make([]*RelayedTx, 0)
        ws.currentBlock++
        block := &BlockInfo{
            BlockNumber: ws.currentBlock,
            BlockHash:   ws.generateBlockHash(ws.currentBlock, blockTxs),
            TxCount:     len(blockTxs),
            Timestamp:   time.Now(),
            Txs:         blockTxs,
        }
        // Update tx statuses to CONFIRMED and assign block number
        for _, tx := range blockTxs {
            tx.Status = StatusConfirmed
            tx.BlockNum = block.BlockNumber
        }
        ws.blocks = append(ws.blocks, block)
        atomic.StoreUint64(&ws.metrics.MempoolSize, 0)
        ws.mu.Unlock()
        ws.broadcastWS("new_block", block)
    }
}

func (ws *WalletStore) generateBlockHash(number uint64, txs []*RelayedTx) string {
    h := sha256.New()
    h.Write([]byte(strconv.FormatUint(number, 10)))
    for _, tx := range txs {
        h.Write([]byte(tx.TxHash))
    }
    return hex.EncodeToString(h.Sum(nil))
}

// -------------------- WebSocket Management --------------------

func (ws *WalletStore) registerWS(conn *websocket.Conn) {
    ws.wsMu.Lock()
    ws.wsClients[conn] = true
    ws.wsMu.Unlock()
}

func (ws *WalletStore) unregisterWS(conn *websocket.Conn) {
    ws.wsMu.Lock()
    delete(ws.wsClients, conn)
    ws.wsMu.Unlock()
    conn.Close()
}

func (ws *WalletStore) broadcastWS(msgType string, payload interface{}) {
    ws.wsMu.Lock()
    defer ws.wsMu.Unlock()
    if len(ws.wsClients) == 0 {
        return
    }
    message := WebSocketMessage{Type: msgType, Payload: payload, Timestamp: time.Now()}
    data, err := json.Marshal(message)
    if err != nil {
        log.Printf("failed to marshal ws message: %v", err)
        return
    }
    for conn := range ws.wsClients {
        if err := conn.WriteMessage(websocket.TextMessage, data); err != nil {
            log.Printf("ws write error, removing client: %v", err)
            delete(ws.wsClients, conn)
            conn.Close()
        }
    }
}

// -------------------- HTTP Handlers --------------------

func (ws *WalletStore) rateLimited(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        if !ws.limiter.Allow() {
            http.Error(w, "rate limit exceeded", http.StatusTooManyRequests)
            return
        }
        atomic.AddUint64(&ws.metrics.TotalRequests, 1)
        next.ServeHTTP(w, r)
    })
}

func (ws *WalletStore) createWalletHandler(w http.ResponseWriter, r *http.Request) {
    var req CreateWalletRequest
    if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
        respondJSON(w, http.StatusBadRequest, APIResponse{Success: false, Error: "invalid json"})
        return
    }
    wallet, err := ws.CreateWallet(strings.TrimSpace(req.Address))
    if err != nil {
        respondJSON(w, http.StatusBadRequest, APIResponse{Success: false, Error: err.Error()})
        return
    }
    respondJSON(w, http.StatusCreated, APIResponse{Success: true, Data: wallet})
}

func (ws *WalletStore) getWalletHandler(w http.ResponseWriter, r *http.Request) {
    addr := mux.Vars(r)["address"]
    wallet, ok := ws.GetWallet(addr)
    if !ok {
        respondJSON(w, http.StatusNotFound, APIResponse{Success: false, Error: "wallet not found"})
        return
    }
    respondJSON(w, http.StatusOK, APIResponse{Success: true, Data: wallet})
}

func (ws *WalletStore) transferHandler(w http.ResponseWriter, r *http.Request) {
    var req TransferRequest
    if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
        respondJSON(w, http.StatusBadRequest, APIResponse{Success: false, Error: "invalid json"})
        return
    }
    tx, err := ws.Transfer(req)
    if err != nil {
        atomic.AddUint64(&ws.metrics.FailedTransfers, 1)
        respondJSON(w, http.StatusBadRequest, APIResponse{Success: false, Error: err.Error()})
        return
    }
    respondJSON(w, http.StatusOK, APIResponse{Success: true, Data: tx})
}

func (ws *WalletStore) relayHandler(w http.ResponseWriter, r *http.Request) {
    var req RelayTxRequest
    if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
        respondJSON(w, http.StatusBadRequest, APIResponse{Success: false, Error: "invalid json"})
        return
    }
    tx, err := ws.RelayTransaction(req)
    if err != nil {
        atomic.AddUint64(&ws.metrics.FailedTransfers, 1)
        respondJSON(w, http.StatusBadRequest, APIResponse{Success: false, Error: err.Error()})
        return
    }
    respondJSON(w, http.StatusAccepted, APIResponse{Success: true, Data: tx})
}

func (ws *WalletStore) metricsHandler(w http.ResponseWriter, r *http.Request) {
    respondJSON(w, http.StatusOK, APIResponse{Success: true, Data: ws.metrics})
}

func (ws *WalletStore) wsHandler(w http.ResponseWriter, r *http.Request) {
    conn, err := upgrader.Upgrade(w, r, nil)
    if err != nil {
        log.Printf("websocket upgrade error: %v", err)
        return
    }
    ws.registerWS(conn)
    // Simple read loop to keep connection alive; we ignore incoming messages.
    for {
        if _, _, err := conn.NextReader(); err != nil {
            ws.unregisterWS(conn)
            break
        }
    }
}

// -------------------- Utility Functions --------------------

func respondJSON(w http.ResponseWriter, status int, payload APIResponse) {
    w.Header().Set("Content-Type", "application/json")
    w.WriteHeader(status)
    json.NewEncoder(w).Encode(payload)
}

func contains(slice []string, item string) bool {
    for _, s := range slice {
        if s == item {
            return true
        }
    }
    return false
}

// ------------------------------------------------------------
// Main entry point
// ------------------------------------------------------------

func main() {
    store := NewWalletStore()
    r := mux.NewRouter()
    api := r.PathPrefix("/api").Subrouter()
    api.Use(store.rateLimited)
    api.HandleFunc("/wallet", store.createWalletHandler).Methods("POST")
    api.HandleFunc("/wallet/{address}", store.getWalletHandler).Methods("GET")
    api.HandleFunc("/transfer", store.transferHandler).Methods("POST")
    api.HandleFunc("/relay", store.relayHandler).Methods("POST")
    api.HandleFunc("/metrics", store.metricsHandler).Methods("GET")
    r.HandleFunc("/ws", store.wsHandler)

    srv := &http.Server{Addr: ":8080", Handler: r}

    // Graceful shutdown handling
    quit := make(chan os.Signal, 1)
    signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
    go func() {
        <-quit
        log.Println("Shutting down server...")
        ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
        defer cancel()
        if err := srv.Shutdown(ctx); err != nil {
            log.Fatalf("Server forced to shutdown: %v", err)
        }
    }()

    log.Println("Server listening on :8080")
    if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
        log.Fatalf("listen: %s\n", err)
    }
}
