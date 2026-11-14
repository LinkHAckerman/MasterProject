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

func (ws *WalletStore) generateTxHash(tx *RelayedTx) string {
    h := sha256.New()
    h.Write([]byte(fmt.Sprintf("%s%s%s%f%f%d%s", tx.From, tx.To, tx.Token, tx.Amount, tx.Fee, tx.Nonce, tx.Signature)))
    return hex.EncodeToString(h.Sum(nil))
}

func (ws *WalletStore) validateAddress(address string) bool {
    return addressRegex.MatchString(address)
}

func (ws *WalletStore) validateToken(token string) bool {
    for _, t := range SupportedTokens {
        if t == token {
            return true
        }
    }
    return false
}

// ------------------------------------------------------------
// Wallet Operations
// ------------------------------------------------------------

func (ws *WalletStore) CreateWallet(address string) (*Wallet, error) {
    if !ws.validateAddress(address) {
        return nil, fmt.Errorf("invalid address format")
    }

    ws.mu.Lock()
    defer ws.mu.Unlock()

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

func (ws *WalletStore) GetWallet(address string) (*Wallet, error) {
    ws.mu.RLock()
    defer ws.mu.RUnlock()

    wallet, exists := ws.wallets[address]
    if !exists {
        return nil, fmt.Errorf("wallet not found")
    }

    return wallet, nil
}

func (ws *WalletStore) UpdateWalletBalance(address string, token string, amount float64) error {
    if !ws.validateToken(token) {
        return fmt.Errorf("unsupported token")
    }

    ws.mu.Lock()
    defer ws.mu.Unlock()

    wallet, exists := ws.wallets[address]
    if !exists {
        return fmt.Errorf("wallet not found")
    }

    wallet.Balance[token] += amount
    wallet.UpdatedAt = time.Now()

    return nil
}

// ------------------------------------------------------------
// Transaction Operations
// ------------------------------------------------------------

func (ws *WalletStore) CreateTransaction(from, to, token string, amount, fee float64) (*RelayedTx, error) {
    if !ws.validateAddress(from) || !ws.validateAddress(to) {
        return nil, fmt.Errorf("invalid address format")
    }

    if !ws.validateToken(token) {
        return nil, fmt.Errorf("unsupported token")
    }

    if amount <= 0 || fee < 0 {
        return nil, fmt.Errorf("invalid amount or fee")
    }

    ws.mu.Lock()
    defer ws.mu.Unlock()

    sender, exists := ws.wallets[from]
    if !exists {
        return nil, fmt.Errorf("sender wallet not found")
    }

    if sender.Balance[token] < amount+fee {
        return nil, fmt.Errorf("insufficient balance")
    }

    tx := &RelayedTx{
        From:      from,
        To:        to,
        Token:     token,
        Amount:    amount,
        Fee:       fee,
        Nonce:     sender.Nonce,
        Status:    StatusPending,
        Timestamp: time.Now(),
    }

    tx.TxHash = ws.generateTxHash(tx)
    ws.allTxs[tx.TxHash] = tx
    ws.mempool = append(ws.mempool, tx)
    sender.Nonce++
    sender.UpdatedAt = time.Now()

    atomic.AddUint64(&ws.metrics.TotalTransfers, 1)
    atomic.AddUint64(&ws.metrics.MempoolSize, 1)

    return tx, nil
}

func (ws *WalletStore) RelayTransaction(txHash string) error {
    ws.mu.Lock()
    defer ws.mu.Unlock()

    tx, exists := ws.allTxs[txHash]
    if !exists {
        return fmt.Errorf("transaction not found")
    }

    if tx.Status != StatusPending {
        return fmt.Errorf("transaction already processed")
    }

    sender, exists := ws.wallets[tx.From]
    if !exists {
        return fmt.Errorf("sender wallet not found")
    }

    if sender.Balance[tx.Token] < tx.Amount+tx.Fee {
        return fmt.Errorf("insufficient balance")
    }

    sender.Balance[tx.Token] -= tx.Amount + tx.Fee
    sender.UpdatedAt = time.Now()

    receiver, exists := ws.wallets[tx.To]
    if !exists {
        receiver = &Wallet{
            Address:   tx.To,
            Balance:   make(map[string]float64),
            Nonce:     0,
            CreatedAt: time.Now(),
            UpdatedAt: time.Now(),
        }
        for _, token := range SupportedTokens {
            receiver.Balance[token] = 0
        }
        ws.wallets[tx.To] = receiver
        atomic.AddUint64(&ws.metrics.ActiveWallets, 1)
    }

    receiver.Balance[tx.Token] += tx.Amount
    receiver.UpdatedAt = time.Now()

    tx.Status = StatusRelayed
    tx.Timestamp = time.Now()

    atomic.AddUint64(&ws.metrics.TotalRelayed, 1)
    atomic.AddUint64(&ws.metrics.MempoolSize, ^uint64(0))

    return nil
}

// ------------------------------------------------------------
// Block Operations
// ------------------------------------------------------------

func (ws *WalletStore) MineBlock() (*BlockInfo, error) {
    ws.mu.Lock()
    defer ws.mu.Unlock()

    if len(ws.mempool) == 0 {
        return nil, fmt.Errorf("no transactions in mempool")
    }

    block := &BlockInfo{
        BlockNumber: ws.currentBlock,
        BlockHash:   fmt.Sprintf("block_%d", ws.currentBlock),
        TxCount:     len(ws.mempool),
        Timestamp:   time.Now(),
        Txs:         make([]*RelayedTx, len(ws.mempool)),
    }

    copy(block.Txs, ws.mempool)
    ws.blocks = append(ws.blocks, block)
    ws.currentBlock++

    for _, tx := range ws.mempool {
        tx.Status = StatusConfirmed
        tx.BlockNum = block.BlockNumber
        tx.Timestamp = time.Now()
    }

    ws.mempool = ws.mempool[:0]
    atomic.StoreUint64(&ws.metrics.MempoolSize, 0)

    return block, nil
}

// ------------------------------------------------------------
// WebSocket Operations
// ------------------------------------------------------------

func (ws *WalletStore) AddWebSocketClient(conn *websocket.Conn) {
    ws.wsMu.Lock()
    defer ws.wsMu.Unlock()
    ws.wsClients[conn] = true
}

func (ws *WalletStore) RemoveWebSocketClient(conn *websocket.Conn) {
    ws.wsMu.Lock()
    defer ws.wsMu.Unlock()
    delete(ws.wsClients, conn)
}

func (ws *WalletStore) BroadcastWebSocketMessage(msg WebSocketMessage) {
    ws.wsMu.Lock()
    defer ws.wsMu.Unlock()

    for conn := range ws.wsClients {
        if err := conn.WriteJSON(msg); err != nil {
            conn.Close()
            delete(ws.wsClients, conn)
        }
    }
}

// ------------------------------------------------------------
// API Handlers
// ------------------------------------------------------------

func (ws *WalletStore) CreateWalletHandler(w http.ResponseWriter, r *http.Request) {
    if !ws.limiter.Allow() {
        http.Error(w, "rate limit exceeded", http.StatusTooManyRequests)
        return
    }

    var req CreateWalletRequest
    if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
        http.Error(w, err.Error(), http.StatusBadRequest)
        return
    }

    wallet, err := ws.CreateWallet(req.Address)
    if err != nil {
        http.Error(w, err.Error(), http.StatusBadRequest)
        return
    }

    atomic.AddUint64(&ws.metrics.TotalRequests, 1)

    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(APIResponse{
        Success: true,
        Data:    wallet,
    })
}

func (ws *WalletStore) GetWalletHandler(w http.ResponseWriter, r *http.Request) {
    if !ws.limiter.Allow() {
        http.Error(w, "rate limit exceeded", http.StatusTooManyRequests)
        return
    }

    vars := mux.Vars(r)
    address := vars["address"]

    wallet, err := ws.GetWallet(address)
    if err != nil {
        http.Error(w, err.Error(), http.StatusNotFound)
        return
    }

    atomic.AddUint64(&ws.metrics.TotalRequests, 1)

    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(APIResponse{
        Success: true,
        Data:    wallet,
    })
}

func (ws *WalletStore) TransferHandler(w http.ResponseWriter, r *http.Request) {
    if !ws.limiter.Allow() {
        http.Error(w, "rate limit exceeded", http.StatusTooManyRequests)
        return
    }

    var req TransferRequest
    if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
        http.Error(w, err.Error(), http.StatusBadRequest)
        return
    }

    tx, err := ws.CreateTransaction(req.From, req.To, req.Token, req.Amount, 0)
    if err != nil {
        http.Error(w, err.Error(), http.StatusBadRequest)
        return
    }

    atomic.AddUint64(&ws.metrics.TotalRequests, 1)

    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(APIResponse{
        Success: true,
        Data:    tx,
    })
}

func (ws *WalletStore) RelayTxHandler(w http.ResponseWriter, r *http.Request) {
    if !ws.limiter.Allow() {
        http.Error(w, "rate limit exceeded", http.StatusTooManyRequests)
        return
    }

    var req RelayTxRequest
    if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
        http.Error(w, err.Error(), http.StatusBadRequest)
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
        Status:    StatusPending,
        Timestamp: time.Now(),
    }

    tx.TxHash = ws.generateTxHash(tx)
    ws.mu.Lock()
    ws.allTxs[tx.TxHash] = tx
    ws.mempool = append(ws.mempool, tx)
    ws.mu.Unlock()

    if err := ws.RelayTransaction(tx.TxHash); err != nil {
        http.Error(w, err.Error(), http.StatusBadRequest)
        return
    }

    atomic.AddUint64(&ws.metrics.TotalRequests, 1)

    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(APIResponse{
        Success: true,
        Data:    tx,
    })
}

func (ws *WalletStore) MineBlockHandler(w http.ResponseWriter, r *http.Request) {
    if !ws.limiter.Allow() {
        http.Error(w, "rate limit exceeded", http.StatusTooManyRequests)
        return
    }

    block, err := ws.MineBlock()
    if err != nil {
        http.Error(w, err.Error(), http.StatusBadRequest)
        return
    }

    atomic.AddUint64(&ws.metrics.TotalRequests, 1)

    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(APIResponse{
        Success: true,
        Data:    block,
    })
}

func (ws *WalletStore) GetMetricsHandler(w http.ResponseWriter, r *http.Request) {
    if !ws.limiter.Allow() {
        http.Error(w, "rate limit exceeded", http.StatusTooManyRequests)
        return
    }

    ws.metrics.UptimeSeconds = uint64(time.Since(ws.startTime).Seconds())

    atomic.AddUint64(&ws.metrics.TotalRequests, 1)

    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(APIResponse{
        Success: true,
        Data:    ws.metrics,
    })
}

func (ws *WalletStore) WebSocketHandler(w http.ResponseWriter, r *http.Request) {
    conn, err := upgrader.Upgrade(w, r, nil)
    if err != nil {
        log.Println("WebSocket upgrade error:", err)
        return
    }

    ws.AddWebSocketClient(conn)
    defer ws.RemoveWebSocketClient(conn)

    for {
        _, _, err := conn.ReadMessage()
        if err != nil {
            log.Println("WebSocket read error:", err)
            break
        }
    }
}

// ------------------------------------------------------------
// Main Function
// ------------------------------------------------------------

func main() {
    store := NewWalletStore()

    r := mux.NewRouter()
    r.HandleFunc("/wallets", store.CreateWalletHandler).Methods("POST")
    r.HandleFunc("/wallets/{address}", store.GetWalletHandler).Methods("GET")
    r.HandleFunc("/transfers", store.TransferHandler).Methods("POST")
    r.HandleFunc("/relay", store.RelayTxHandler).Methods("POST")
    r.HandleFunc("/mine", store.MineBlockHandler).Methods("POST")
    r.HandleFunc("/metrics", store.GetMetricsHandler).Methods("GET")
    r.HandleFunc("/ws", store.WebSocketHandler)

    srv := &http.Server{
        Handler:      r,
        Addr:         "127.0.0.1:8000",
        WriteTimeout: 15 * time.Second,
        ReadTimeout:  15 * time.Second,
    }

    go func() {
        log.Println("Server started on :8000")
        if err := srv.ListenAndServe(); err != nil {
            log.Println(err)
        }
    }()

    c := make(chan os.Signal, 1)
    signal.Notify(c, os.Interrupt, syscall.SIGTERM)
    <-c

    ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
    defer cancel()
    srv.Shutdown(ctx)

    log.Println("Shutting down server...")
    os.Exit(0)
}