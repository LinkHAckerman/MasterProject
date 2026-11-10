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
        limiter:      rate.NewLimiter(rate.Every(time.Second), 100),
    }
}

// Helper function to validate Ethereum address
func isValidAddress(address string) bool {
    return addressRegex.MatchString(address)
}

// Helper function to validate token
func isValidToken(token string) bool {
    for _, t := range SupportedTokens {
        if t == token {
            return true
        }
    }
    return false
}

// Helper function to generate a random transaction hash
func generateTxHash() string {
    hash := sha256.Sum256([]byte(strconv.FormatInt(time.Now().UnixNano(), 10)))
    return hex.EncodeToString(hash[:])
}

// ------------------------------------------------------------
// WalletStore Methods
// ------------------------------------------------------------

// CreateWallet creates a new wallet with the given address
func (ws *WalletStore) CreateWallet(address string) (*Wallet, error) {
    ws.mu.Lock()
    defer ws.mu.Unlock()

    if !isValidAddress(address) {
        return nil, fmt.Errorf("invalid address")
    }

    if _, exists := ws.wallets[address]; exists {
        return nil, fmt.Errorf("wallet already exists")
    }

    wallet := &Wallet{
        Address:   address,
        Balance:   make(map[string]float64),
        Nonce:     0,
        CreatedAt: time.Now(),
        UpdatedAt: time.Now(),
    }

    for _, token := range SupportedTokens {
        wallet.Balance[token] = 0
    }

    ws.wallets[address] = wallet
    atomic.AddUint64(&ws.metrics.ActiveWallets, 1)

    return wallet, nil
}

// GetWallet retrieves a wallet by address
func (ws *WalletStore) GetWallet(address string) (*Wallet, error) {
    ws.mu.RLock()
    defer ws.mu.RUnlock()

    wallet, exists := ws.wallets[address]
    if !exists {
        return nil, fmt.Errorf("wallet not found")
    }

    return wallet, nil
}

// Transfer performs a token transfer between wallets
func (ws *WalletStore) Transfer(from, to, token string, amount float64) (*RelayedTx, error) {
    ws.mu.Lock()
    defer ws.mu.Unlock()

    if !isValidAddress(from) || !isValidAddress(to) {
        return nil, fmt.Errorf("invalid address")
    }

    if !isValidToken(token) {
        return nil, fmt.Errorf("invalid token")
    }

    fromWallet, exists := ws.wallets[from]
    if !exists {
        return nil, fmt.Errorf("sender wallet not found")
    }

    toWallet, exists := ws.wallets[to]
    if !exists {
        return nil, fmt.Errorf("receiver wallet not found")
    }

    if fromWallet.Balance[token] < amount {
        return nil, fmt.Errorf("insufficient balance")
    }

    fromWallet.Balance[token] -= amount
    toWallet.Balance[token] += amount
    fromWallet.UpdatedAt = time.Now()
    toWallet.UpdatedAt = time.Now()

    tx := &RelayedTx{
        TxHash:    generateTxHash(),
        From:      from,
        To:        to,
        Token:     token,
        Amount:    amount,
        Fee:       0,
        Nonce:     fromWallet.Nonce,
        Status:    StatusConfirmed,
        Timestamp: time.Now(),
    }

    fromWallet.Nonce++
    ws.txHistory[from] = append(ws.txHistory[from], tx)
    ws.txHistory[to] = append(ws.txHistory[to], tx)
    ws.allTxs[tx.TxHash] = tx

    atomic.AddUint64(&ws.metrics.TotalTransfers, 1)

    return tx, nil
}

// RelayTx relays a meta-transaction to the mempool
func (ws *WalletStore) RelayTx(tx *RelayedTx) error {
    ws.mu.Lock()
    defer ws.mu.Unlock()

    if !isValidAddress(tx.From) || !isValidAddress(tx.To) {
        return fmt.Errorf("invalid address")
    }

    if !isValidToken(tx.Token) {
        return fmt.Errorf("invalid token")
    }

    fromWallet, exists := ws.wallets[tx.From]
    if !exists {
        return fmt.Errorf("sender wallet not found")
    }

    if fromWallet.Nonce != tx.Nonce {
        return fmt.Errorf("invalid nonce")
    }

    if fromWallet.Balance[tx.Token] < tx.Amount+tx.Fee {
        return fmt.Errorf("insufficient balance")
    }

    tx.Status = StatusPending
    tx.Timestamp = time.Now()
    ws.mempool = append(ws.mempool, tx)
    atomic.AddUint64(&ws.metrics.MempoolSize, 1)

    return nil
}

// ProcessMempool processes transactions in the mempool
func (ws *WalletStore) ProcessMempool() {
    ws.mu.Lock()
    defer ws.mu.Unlock()

    for len(ws.mempool) > 0 {
        tx := ws.mempool[0]
        ws.mempool = ws.mempool[1:]
        atomic.AddUint64(&ws.metrics.MempoolSize, ^uint64(0))

        fromWallet, exists := ws.wallets[tx.From]
        if !exists {
            tx.Status = StatusFailed
            tx.ErrorMsg = "sender wallet not found"
            atomic.AddUint64(&ws.metrics.FailedTransfers, 1)
            continue
        }

        toWallet, exists := ws.wallets[tx.To]
        if !exists {
            tx.Status = StatusFailed
            tx.ErrorMsg = "receiver wallet not found"
            atomic.AddUint64(&ws.metrics.FailedTransfers, 1)
            continue
        }

        if fromWallet.Balance[tx.Token] < tx.Amount+tx.Fee {
            tx.Status = StatusFailed
            tx.ErrorMsg = "insufficient balance"
            atomic.AddUint64(&ws.metrics.FailedTransfers, 1)
            continue
        }

        fromWallet.Balance[tx.Token] -= tx.Amount + tx.Fee
        toWallet.Balance[tx.Token] += tx.Amount
        fromWallet.UpdatedAt = time.Now()
        toWallet.UpdatedAt = time.Now()

        tx.Status = StatusRelayed
        tx.Timestamp = time.Now()
        fromWallet.Nonce++
        ws.txHistory[tx.From] = append(ws.txHistory[tx.From], tx)
        ws.txHistory[tx.To] = append(ws.txHistory[tx.To], tx)
        ws.allTxs[tx.TxHash] = tx

        atomic.AddUint64(&ws.metrics.TotalRelayed, 1)
    }
}

// MineBlock simulates mining a new block
func (ws *WalletStore) MineBlock() {
    ws.mu.Lock()
    defer ws.mu.Unlock()

    if len(ws.mempool) == 0 {
        return
    }

    block := &BlockInfo{
        BlockNumber: ws.currentBlock + 1,
        BlockHash:   generateTxHash(),
        TxCount:     len(ws.mempool),
        Timestamp:   time.Now(),
        Txs:         make([]*RelayedTx, len(ws.mempool)),
    }

    copy(block.Txs, ws.mempool)
    ws.blocks = append(ws.blocks, block)
    ws.currentBlock = block.BlockNumber

    for _, tx := range ws.mempool {
        tx.Status = StatusConfirmed
        tx.BlockNum = block.BlockNumber
    }

    ws.mempool = ws.mempool[:0]
    atomic.StoreUint64(&ws.metrics.MempoolSize, 0)
}

// GetMetrics retrieves the current metrics
func (ws *WalletStore) GetMetrics() Metrics {
    ws.mu.RLock()
    defer ws.mu.RUnlock()

    metrics := ws.metrics
    metrics.UptimeSeconds = uint64(time.Since(ws.startTime).Seconds())

    return metrics
}

// ------------------------------------------------------------
// WebSocket Handlers
// ------------------------------------------------------------

// handleWebSocket handles WebSocket connections
func (ws *WalletStore) handleWebSocket(w http.ResponseWriter, r *http.Request) {
    conn, err := upgrader.Upgrade(w, r, nil)
    if err != nil {
        log.Println("WebSocket upgrade error:", err)
        return
    }

    ws.wsMu.Lock()
    ws.wsClients[conn] = true
    ws.wsMu.Unlock()

    defer func() {
        ws.wsMu.Lock()
        delete(ws.wsClients, conn)
        ws.wsMu.Unlock()
        conn.Close()
    }()

    for {
        _, _, err := conn.ReadMessage()
        if err != nil {
            log.Println("WebSocket read error:", err)
            break
        }
    }
}

// broadcastWebSocket broadcasts a message to all WebSocket clients
func (ws *WalletStore) broadcastWebSocket(message WebSocketMessage) {
    ws.wsMu.Lock()
    defer ws.wsMu.Unlock()

    for client := range ws.wsClients {
        err := client.WriteJSON(message)
        if err != nil {
            log.Println("WebSocket write error:", err)
            client.Close()
            delete(ws.wsClients, client)
        }
    }
}

// ------------------------------------------------------------
// HTTP Handlers
// ------------------------------------------------------------

// handleCreateWallet handles the creation of a new wallet
func (ws *WalletStore) handleCreateWallet(w http.ResponseWriter, r *http.Request) {
    if !ws.limiter.Allow() {
        http.Error(w, "Too many requests", http.StatusTooManyRequests)
        return
    }

    var req CreateWalletRequest
    err := json.NewDecoder(r.Body).Decode(&req)
    if err != nil {
        http.Error(w, err.Error(), http.StatusBadRequest)
        return
    }

    wallet, err := ws.CreateWallet(req.Address)
    if err != nil {
        http.Error(w, err.Error(), http.StatusBadRequest)
        return
    }

    response := APIResponse{
        Success: true,
        Data:    wallet,
    }

    json.NewEncoder(w).Encode(response)
}

// handleGetWallet handles retrieving a wallet by address
func (ws *WalletStore) handleGetWallet(w http.ResponseWriter, r *http.Request) {
    if !ws.limiter.Allow() {
        http.Error(w, "Too many requests", http.StatusTooManyRequests)
        return
    }

    vars := mux.Vars(r)
    address := vars["address"]

    wallet, err := ws.GetWallet(address)
    if err != nil {
        http.Error(w, err.Error(), http.StatusNotFound)
        return
    }

    response := APIResponse{
        Success: true,
        Data:    wallet,
    }

    json.NewEncoder(w).Encode(response)
}

// handleTransfer handles a token transfer between wallets
func (ws *WalletStore) handleTransfer(w http.ResponseWriter, r *http.Request) {
    if !ws.limiter.Allow() {
        http.Error(w, "Too many requests", http.StatusTooManyRequests)
        return
    }

    var req TransferRequest
    err := json.NewDecoder(r.Body).Decode(&req)
    if err != nil {
        http.Error(w, err.Error(), http.StatusBadRequest)
        return
    }

    tx, err := ws.Transfer(req.From, req.To, req.Token, req.Amount)
    if err != nil {
        http.Error(w, err.Error(), http.StatusBadRequest)
        return
    }

    response := APIResponse{
        Success: true,
        Data:    tx,
    }

    json.NewEncoder(w).Encode(response)
}

// handleRelayTx handles relaying a meta-transaction to the mempool
func (ws *WalletStore) handleRelayTx(w http.ResponseWriter, r *http.Request) {
    if !ws.limiter.Allow() {
        http.Error(w, "Too many requests", http.StatusTooManyRequests)
        return
    }

    var req RelayTxRequest
    err := json.NewDecoder(r.Body).Decode(&req)
    if err != nil {
        http.Error(w, err.Error(), http.StatusBadRequest)
        return
    }

    tx := &RelayedTx{
        TxHash:    generateTxHash(),
        From:      req.From,
        To:        req.To,
        Token:     req.Token,
        Amount:    req.Amount,
        Fee:       req.Fee,
        Nonce:     req.Nonce,
        Signature: req.Signature,
    }

    err = ws.RelayTx(tx)
    if err != nil {
        http.Error(w, err.Error(), http.StatusBadRequest)
        return
    }

    response := APIResponse{
        Success: true,
        Data:    tx,
    }

    json.NewEncoder(w).Encode(response)
}

// handleGetMetrics handles retrieving the current metrics
func (ws *WalletStore) handleGetMetrics(w http.ResponseWriter, r *http.Request) {
    if !ws.limiter.Allow() {
        http.Error(w, "Too many requests", http.StatusTooManyRequests)
        return
    }

    metrics := ws.GetMetrics()

    response := APIResponse{
        Success: true,
        Data:    metrics,
    }

    json.NewEncoder(w).Encode(response)
}

// ------------------------------------------------------------
// Main Function
// ------------------------------------------------------------

func main() {
    store := NewWalletStore()

    // Start a goroutine to periodically process the mempool and mine blocks
    go func() {
        for {
            time.Sleep(5 * time.Second)
            store.ProcessMempool()
            store.MineBlock()
        }
    }()

    // Set up HTTP routes
    r := mux.NewRouter()
    r.HandleFunc("/wallets", store.handleCreateWallet).Methods("POST")
    r.HandleFunc("/wallets/{address}", store.handleGetWallet).Methods("GET")
    r.HandleFunc("/transfers", store.handleTransfer).Methods("POST")
    r.HandleFunc("/relay", store.handleRelayTx).Methods("POST")
    r.HandleFunc("/metrics", store.handleGetMetrics).Methods("GET")
    r.HandleFunc("/ws", store.handleWebSocket)

    // Start HTTP server
    srv := &http.Server{
        Handler: r,
        Addr:    "127.0.0.1:8000",
        // Good practice: enforce timeouts for servers you create!
        WriteTimeout: 15 * time.Second,
        ReadTimeout:  15 * time.Second,
    }

    // Run our server in a goroutine so that it doesn't block.
    go func() {
        log.Println("Starting server on :8000")
        if err := srv.ListenAndServe(); err != nil {
            log.Println(err)
        }
    }()

    // Graceful shutdown
    c := make(chan os.Signal, 1)
    signal.Notify(c, os.Interrupt, syscall.SIGTERM)
    <-c

    // Create a deadline to wait for.
    ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
    defer cancel()
    srv.Shutdown(ctx)
    log.Println("Shutting down")
    os.Exit(0)
}