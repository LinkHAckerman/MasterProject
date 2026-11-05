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
    return &WalletStore{
        wallets:      make(map[string]*Wallet),
        txHistory:    make(map[string][]*RelayedTx),
        allTxs:       make(map[string]*RelayedTx),
        mempool:      make([]*RelayedTx, 0),
        blocks:       make([]*BlockInfo, 0),
        metrics:      Metrics{},
        startTime:    time.Now(),
        currentBlock: 0,
        wsClients:    make(map[*websocket.Conn]bool),
        limiter:      rate.NewLimiter(rate.Every(time.Second/10), 100), // 10 req/s burst 100
    }
}

func (s *WalletStore) AddWallet(address string) error {
    if !addressRegex.MatchString(address) {
        return fmt.Errorf("invalid address format")
    }
    s.mu.Lock()
    defer s.mu.Unlock()
    if _, exists := s.wallets[address]; exists {
        return fmt.Errorf("wallet already exists")
    }
    s.wallets[address] = &Wallet{
        Address:   address,
        Balance:   make(map[string]float64),
        Nonce:     0,
        CreatedAt: time.Now(),
        UpdatedAt: time.Now(),
    }
    atomic.AddUint64(&s.metrics.ActiveWallets, 1)
    return nil
}

func (s *WalletStore) GetWallet(address string) (*Wallet, bool) {
    s.mu.RLock()
    defer s.mu.RUnlock()
    w, ok := s.wallets[address]
    return w, ok
}

func (s *WalletStore) Transfer(req TransferRequest) (*RelayedTx, error) {
    if !addressRegex.MatchString(req.From) || !addressRegex.MatchString(req.To) {
        return nil, fmt.Errorf("invalid address")
    }
    if req.Amount <= 0 {
        return nil, fmt.Errorf("amount must be positive")
    }
    if !contains(SupportedTokens, req.Token) {
        return nil, fmt.Errorf("unsupported token")
    }

    s.mu.Lock()
    defer s.mu.Unlock()

    fromWallet, ok := s.wallets[req.From]
    if !ok {
        return nil, fmt.Errorf("sender wallet not found")
    }
    toWallet, ok := s.wallets[req.To]
    if !ok {
        return nil, fmt.Errorf("receiver wallet not found")
    }
    if fromWallet.Balance[req.Token] < req.Amount {
        return nil, fmt.Errorf("insufficient balance")
    }

    // Perform balance updates
    fromWallet.Balance[req.Token] -= req.Amount
    toWallet.Balance[req.Token] += req.Amount
    fromWallet.Nonce++
    fromWallet.UpdatedAt = time.Now()
    toWallet.UpdatedAt = time.Now()

    now := time.Now()
    tx := &RelayedTx{
        TxHash:    generateTxHash(req.From, req.To, req.Token, req.Amount, now),
        From:      req.From,
        To:        req.To,
        Token:     req.Token,
        Amount:    req.Amount,
        Fee:       0,
        Nonce:     fromWallet.Nonce,
        Status:    StatusConfirmed,
        Timestamp: now,
        BlockNum:  s.currentBlock,
    }
    s.allTxs[tx.TxHash] = tx
    s.txHistory[req.From] = append(s.txHistory[req.From], tx)
    s.txHistory[req.To] = append(s.txHistory[req.To], tx)
    atomic.AddUint64(&s.metrics.TotalTransfers, 1)
    atomic.AddUint64(&s.metrics.TotalRequests, 1)

    s.broadcast(WebSocketMessage{Type: "tx_confirmed", Payload: tx, Timestamp: now})
    return tx, nil
}

func (s *WalletStore) RelayTransaction(req RelayTxRequest) (*RelayedTx, error) {
    if !addressRegex.MatchString(req.From) || !addressRegex.MatchString(req.To) {
        return nil, fmt.Errorf("invalid address")
    }
    if req.Amount <= 0 {
        return nil, fmt.Errorf("amount must be positive")
    }
    if !contains(SupportedTokens, req.Token) {
        return nil, fmt.Errorf("unsupported token")
    }
    if req.Signature == "" {
        return nil, fmt.Errorf("missing signature")
    }

    s.mu.Lock()
    defer s.mu.Unlock()

    wallet, ok := s.wallets[req.From]
    if !ok {
        return nil, fmt.Errorf("sender wallet not found")
    }
    // Simple nonce check – must be exactly current+1
    expectedNonce := wallet.Nonce + 1
    if req.Nonce != expectedNonce {
        return nil, fmt.Errorf("invalid nonce, expected %d", expectedNonce)
    }

    now := time.Now()
    tx := &RelayedTx{
        TxHash:    generateTxHash(req.From, req.To, req.Token, req.Amount, now),
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
    s.allTxs[tx.TxHash] = tx
    s.mempool = append(s.mempool, tx)
    atomic.AddUint64(&s.metrics.MempoolSize, 1)
    atomic.AddUint64(&s.metrics.TotalRelayed, 1)
    atomic.AddUint64(&s.metrics.TotalRequests, 1)

    s.broadcast(WebSocketMessage{Type: "tx_pending", Payload: tx, Timestamp: now})
    return tx, nil
}

func (s *WalletStore) GetTransaction(hash string) (*RelayedTx, bool) {
    s.mu.RLock()
    defer s.mu.RUnlock()
    tx, ok := s.allTxs[hash]
    return tx, ok
}

func (s *WalletStore) GetBlock(number uint64) (*BlockInfo, bool) {
    s.mu.RLock()
    defer s.mu.RUnlock()
    if number == 0 || number > s.currentBlock {
        return nil, false
    }
    // blocks slice is zero-indexed
    idx := int(number - 1)
    if idx < 0 || idx >= len(s.blocks) {
        return nil, false
    }
    return s.blocks[idx], true
}

func (s *WalletStore) mineBlocks(interval time.Duration, stopCh <-chan struct{}) {
    ticker := time.NewTicker(interval)
    defer ticker.Stop()
    for {
        select {
        case <-ticker.C:
            s.createBlock()
        case <-stopCh:
            return
        }
    }
}

func (s *WalletStore) createBlock() {
    s.mu.Lock()
    defer s.mu.Unlock()
    if len(s.mempool) == 0 {
        // still increment block number for time progression
        s.currentBlock++
        return
    }
    blockTxs := s.mempool
    s.mempool = make([]*RelayedTx, 0)
    atomic.StoreUint64(&s.metrics.MempoolSize, 0)
    s.currentBlock++
    blockHash := generateBlockHash(s.currentBlock, time.Now())
    block := &BlockInfo{
        BlockNumber: s.currentBlock,
        BlockHash:   blockHash,
        TxCount:     len(blockTxs),
        Timestamp:   time.Now(),
        Txs:         blockTxs,
    }
    // Update transaction statuses
    for _, tx := range blockTxs {
        tx.Status = StatusConfirmed
        tx.BlockNum = s.currentBlock
        // Record in history for both parties
        s.txHistory[tx.From] = append(s.txHistory[tx.From], tx)
        s.txHistory[tx.To] = append(s.txHistory[tx.To], tx)
    }
    s.blocks = append(s.blocks, block)
    s.broadcast(WebSocketMessage{Type: "new_block", Payload: block, Timestamp: time.Now()})
}

func generateBlockHash(number uint64, t time.Time) string {
    h := sha256.New()
    fmt.Fprintf(h, "%d|%d", number, t.UnixNano())
    return hex.EncodeToString(h.Sum(nil))
}

func (s *WalletStore) broadcast(msg WebSocketMessage) {
    s.wsMu.Lock()
    defer s.wsMu.Unlock()
    data, err := json.Marshal(msg)
    if err != nil {
        log.Printf("failed to marshal ws message: %v", err)
        return
    }
    for conn := range s.wsClients {
        if err := conn.WriteMessage(websocket.TextMessage, data); err != nil {
            log.Printf("ws write error, removing client: %v", err)
            conn.Close()
            delete(s.wsClients, conn)
        }
    }
}

func (s *WalletStore) registerWS(conn *websocket.Conn) {
    s.wsMu.Lock()
    s.wsClients[conn] = true
    s.wsMu.Unlock()
}

func (s *WalletStore) unregisterWS(conn *websocket.Conn) {
    s.wsMu.Lock()
    if _, ok := s.wsClients[conn]; ok {
        delete(s.wsClients, conn)
        conn.Close()
    }
    s.wsMu.Unlock()
}

// ------------------------------------------------------------
// HTTP Handlers
// ------------------------------------------------------------

func writeJSON(w http.ResponseWriter, status int, resp APIResponse) {
    w.Header().Set("Content-Type", "application/json")
    w.WriteHeader(status)
    json.NewEncoder(w).Encode(resp)
}

func (s *WalletStore) createWalletHandler(w http.ResponseWriter, r *http.Request) {
    if err := s.limiter.Wait(r.Context()); err != nil {
        writeJSON(w, http.StatusTooManyRequests, APIResponse{Success: false, Error: "rate limit exceeded"})
        return
    }
    var req CreateWalletRequest
    if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
        writeJSON(w, http.StatusBadRequest, APIResponse{Success: false, Error: "invalid json"})
        return
    }
    if err := s.AddWallet(strings.TrimSpace(req.Address)); err != nil {
        writeJSON(w, http.StatusBadRequest, APIResponse{Success: false, Error: err.Error()})
        return
    }
    writeJSON(w, http.StatusCreated, APIResponse{Success: true, Data: map[string]string{"address": req.Address}})
}

func (s *WalletStore) getWalletHandler(w http.ResponseWriter, r *http.Request) {
    if err := s.limiter.Wait(r.Context()); err != nil {
        writeJSON(w, http.StatusTooManyRequests, APIResponse{Success: false, Error: "rate limit exceeded"})
        return
    }
    addr := mux.Vars(r)["address"]
    wallet, ok := s.GetWallet(addr)
    if !ok {
        writeJSON(w, http.StatusNotFound, APIResponse{Success: false, Error: "wallet not found"})
        return
    }
    writeJSON(w, http.StatusOK, APIResponse{Success: true, Data: wallet})
}

func (s *WalletStore) transferHandler(w http.ResponseWriter, r *http.Request) {
    if err := s.limiter.Wait(r.Context()); err != nil {
        writeJSON(w, http.StatusTooManyRequests, APIResponse{Success: false, Error: "rate limit exceeded"})
        return
    }
    var req TransferRequest
    if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
        writeJSON(w, http.StatusBadRequest, APIResponse{Success: false, Error: "invalid json"})
        return
    }
    tx, err := s.Transfer(req)
    if err != nil {
        writeJSON(w, http.StatusBadRequest, APIResponse{Success: false, Error: err.Error()})
        return
    }
    writeJSON(w, http.StatusOK, APIResponse{Success: true, Data: tx})
}

func (s *WalletStore) relayTxHandler(w http.ResponseWriter, r *http.Request) {
    if err := s.limiter.Wait(r.Context()); err != nil {
        writeJSON(w, http.StatusTooManyRequests, APIResponse{Success: false, Error: "rate limit exceeded"})
        return
    }
    var req RelayTxRequest
    if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
        writeJSON(w, http.StatusBadRequest, APIResponse{Success: false, Error: "invalid json"})
        return
    }
    tx, err := s.RelayTransaction(req)
    if err != nil {
        writeJSON(w, http.StatusBadRequest, APIResponse{Success: false, Error: err.Error()})
        return
    }
    writeJSON(w, http.StatusAccepted, APIResponse{Success: true, Data: tx})
}

func (s *WalletStore) getTxHandler(w http.ResponseWriter, r *http.Request) {
    if err := s.limiter.Wait(r.Context()); err != nil {
        writeJSON(w, http.StatusTooManyRequests, APIResponse{Success: false, Error: "rate limit exceeded"})
        return
    }
    hash := mux.Vars(r)["hash"]
    tx, ok := s.GetTransaction(hash)
    if !ok {
        writeJSON(w, http.StatusNotFound, APIResponse{Success: false, Error: "transaction not found"})
        return
    }
    writeJSON(w, http.StatusOK, APIResponse{Success: true, Data: tx})
}

func (s *WalletStore) getBlockHandler(w http.ResponseWriter, r *http.Request) {
    if err := s.limiter.Wait(r.Context()); err != nil {
        writeJSON(w, http.StatusTooManyRequests, APIResponse{Success: false, Error: "rate limit exceeded"})
        return
    }
    numStr := mux.Vars(r)["number"]
    num, err := strconv.ParseUint(numStr, 10, 64)
    if err != nil {
        writeJSON(w, http.StatusBadRequest, APIResponse{Success: false, Error: "invalid block number"})
        return
    }
    block, ok := s.GetBlock(num)
    if !ok {
        writeJSON(w, http.StatusNotFound, APIResponse{Success: false, Error: "block not found"})
        return
    }
    writeJSON(w, http.StatusOK, APIResponse{Success: true, Data: block})
}

func (s *WalletStore) wsHandler(w http.ResponseWriter, r *http.Request) {
    conn, err := upgrader.Upgrade(w, r, nil)
    if err != nil {
        log.Printf("ws upgrade error: %v", err)
        return
    }
    s.registerWS(conn)
    defer s.unregisterWS(conn)
    // Simple read loop to keep connection alive; we ignore incoming messages.
    for {
        if _, _, err := conn.NextReader(); err != nil {
            break
        }
    }
}

// ------------------------------------------------------------
// Utility Functions
// ------------------------------------------------------------

func contains(slice []string, item string) bool {
    for _, v := range slice {
        if v == item {
            return true
        }
    }
    return false
}

func generateTxHash(from, to, token string, amount float64, t time.Time) string {
    h := sha256.New()
    fmt.Fprintf(h, "%s|%s|%s|%f|%d", from, to, token, amount, t.UnixNano())
    return hex.EncodeToString(h.Sum(nil))
}

// ------------------------------------------------------------
// Main
// ------------------------------------------------------------

func main() {
    store := NewWalletStore()
    router := mux.NewRouter()

    // REST endpoints
    router.HandleFunc("/wallet", store.createWalletHandler).Methods("POST")
    router.HandleFunc("/wallet/{address}", store.getWalletHandler).Methods("GET")
    router.HandleFunc("/transfer", store.transferHandler).Methods("POST")
    router.HandleFunc("/relay", store.relayTxHandler).Methods("POST")
    router.HandleFunc("/tx/{hash}", store.getTxHandler).Methods("GET")
    router.HandleFunc("/block/{number}", store.getBlockHandler).Methods("GET")
    router.HandleFunc("/ws", store.wsHandler)

    srv := &http.Server{
        Addr:    ":8080",
        Handler: router,
    }

    // Block mining routine
    stopMining := make(chan struct{})
    go store.mineBlocks(10*time.Second, stopMining)

    // Graceful shutdown handling
    quit := make(chan os.Signal, 1)
    signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
    go func() {
        <-quit
        log.Println("Shutting down server...")
        close(stopMining)
        ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
        defer cancel()
        if err := srv.Shutdown(ctx); err != nil {
            log.Fatalf("Server forced to shutdown: %v", err)
        }
    }()

    log.Println("Server listening on :8080")
    if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
        log.Fatalf("ListenAndServe error: %v", err)
    }
    log.Println("Server exited gracefully")
}
