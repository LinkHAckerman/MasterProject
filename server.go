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

func (ws *WalletStore) CreateTransfer(from string, to string, token string, amount float64) (*RelayedTx, error) {
    if !ws.validateAddress(from) || !ws.validateAddress(to) {
        return nil, fmt.Errorf("invalid address format")
    }

    if !ws.validateToken(token) {
        return nil, fmt.Errorf("unsupported token")
    }

    if amount <= 0 {
        return nil, fmt.Errorf("amount must be positive")
    }

    ws.mu.Lock()
    defer ws.mu.Unlock()

    sender, exists := ws.wallets[from]
    if !exists {
        return nil, fmt.Errorf("sender wallet not found")
    }

    if sender.Balance[token] < amount {
        return nil, fmt.Errorf("insufficient balance")
    }

    receiver, exists := ws.wallets[to]
    if !exists {
        return nil, fmt.Errorf("receiver wallet not found")
    }

    tx := &RelayedTx{
        From:      from,
        To:        to,
        Token:     token,
        Amount:    amount,
        Fee:       0,
        Nonce:     sender.Nonce,
        Status:    StatusPending,
        Timestamp: time.Now(),
    }

    tx.TxHash = ws.generateTxHash(tx)

    sender.Balance[token] -= amount
    receiver.Balance[token] += amount
    sender.Nonce++
    sender.UpdatedAt = time.Now()
    receiver.UpdatedAt = time.Now()

    ws.txHistory[from] = append(ws.txHistory[from], tx)
    ws.txHistory[to] = append(ws.txHistory[to], tx)
    ws.allTxs[tx.TxHash] = tx
    ws.mempool = append(ws.mempool, tx)

    atomic.AddUint64(&ws.metrics.TotalTransfers, 1)
    atomic.AddUint64(&ws.metrics.MempoolSize, 1)

    return tx, nil
}

func (ws *WalletStore) RelayTransaction(tx *RelayedTx) error {
    if !ws.validateAddress(tx.From) || !ws.validateAddress(tx.To) {
        return fmt.Errorf("invalid address format")
    }

    if !ws.validateToken(tx.Token) {
        return fmt.Errorf("unsupported token")
    }

    if tx.Amount <= 0 || tx.Fee < 0 {
        return fmt.Errorf("invalid amount or fee")
    }

    ws.mu.Lock()
    defer ws.mu.Unlock()

    sender, exists := ws.wallets[tx.From]
    if !exists {
        return fmt.Errorf("sender wallet not found")
    }

    if sender.Balance[tx.Token] < tx.Amount+tx.Fee {
        return fmt.Errorf("insufficient balance")
    }

    if sender.Nonce != tx.Nonce {
        return fmt.Errorf("invalid nonce")
    }

    tx.Status = StatusRelayed
    tx.Timestamp = time.Now()
    tx.TxHash = ws.generateTxHash(tx)

    sender.Balance[tx.Token] -= tx.Amount + tx.Fee
    sender.Nonce++
    sender.UpdatedAt = time.Now()

    ws.allTxs[tx.TxHash] = tx
    ws.mempool = append(ws.mempool, tx)

    atomic.AddUint64(&ws.metrics.TotalRelayed, 1)
    atomic.AddUint64(&ws.metrics.MempoolSize, 1)

    return nil
}

func (ws *WalletStore) ConfirmTransaction(txHash string) error {
    ws.mu.Lock()
    defer ws.mu.Unlock()

    tx, exists := ws.allTxs[txHash]
    if !exists {
        return fmt.Errorf("transaction not found")
    }

    if tx.Status != StatusRelayed {
        return fmt.Errorf("transaction not in relayed state")
    }

    tx.Status = StatusConfirmed
    tx.Timestamp = time.Now()

    // Remove from mempool
    for i, memTx := range ws.mempool {
        if memTx.TxHash == txHash {
            ws.mempool = append(ws.mempool[:i], ws.mempool[i+1:]...)
            break
        }
    }

    atomic.AddUint64(&ws.metrics.MempoolSize, ^uint64(0))

    return nil
}

func (ws *WalletStore) FailTransaction(txHash string, errorMsg string) error {
    ws.mu.Lock()
    defer ws.mu.Unlock()

    tx, exists := ws.allTxs[txHash]
    if !exists {
        return fmt.Errorf("transaction not found")
    }

    if tx.Status != StatusRelayed {
        return fmt.Errorf("transaction not in relayed state")
    }

    tx.Status = StatusFailed
    tx.ErrorMsg = errorMsg
    tx.Timestamp = time.Now()

    // Refund sender
    sender, exists := ws.wallets[tx.From]
    if exists {
        sender.Balance[tx.Token] += tx.Amount + tx.Fee
        sender.UpdatedAt = time.Now()
    }

    // Remove from mempool
    for i, memTx := range ws.mempool {
        if memTx.TxHash == txHash {
            ws.mempool = append(ws.mempool[:i], ws.mempool[i+1:]...)
            break
        }
    }

    atomic.AddUint64(&ws.metrics.FailedTransfers, 1)
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
        BlockNumber: ws.currentBlock + 1,
        Timestamp:   time.Now(),
        Txs:         make([]*RelayedTx, len(ws.mempool)),
    }

    copy(block.Txs, ws.mempool)
    block.TxCount = len(block.Txs)

    // Generate block hash
    h := sha256.New()
    for _, tx := range block.Txs {
        h.Write([]byte(tx.TxHash))
    }
    block.BlockHash = hex.EncodeToString(h.Sum(nil))

    // Update transaction statuses
    for _, tx := range block.Txs {
        tx.Status = StatusConfirmed
        tx.BlockNum = block.BlockNumber
        tx.Timestamp = block.Timestamp
    }

    ws.blocks = append(ws.blocks, block)
    ws.currentBlock = block.BlockNumber
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

func (ws *WalletStore) handleCreateWallet(w http.ResponseWriter, r *http.Request) {
    atomic.AddUint64(&ws.metrics.TotalRequests, 1)

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

    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(APIResponse{
        Success: true,
        Data:    wallet,
    })
}

func (ws *WalletStore) handleGetWallet(w http.ResponseWriter, r *http.Request) {
    atomic.AddUint64(&ws.metrics.TotalRequests, 1)

    vars := mux.Vars(r)
    address := vars["address"]

    wallet, err := ws.GetWallet(address)
    if err != nil {
        http.Error(w, err.Error(), http.StatusNotFound)
        return
    }

    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(APIResponse{
        Success: true,
        Data:    wallet,
    })
}

func (ws *WalletStore) handleTransfer(w http.ResponseWriter, r *http.Request) {
    atomic.AddUint64(&ws.metrics.TotalRequests, 1)

    var req TransferRequest
    if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
        http.Error(w, err.Error(), http.StatusBadRequest)
        return
    }

    tx, err := ws.CreateTransfer(req.From, req.To, req.Token, req.Amount)
    if err != nil {
        http.Error(w, err.Error(), http.StatusBadRequest)
        return
    }

    // Broadcast transaction to WebSocket clients
    ws.BroadcastWebSocketMessage(WebSocketMessage{
        Type:      "transaction",
        Payload:   tx,
        Timestamp: time.Now(),
    })

    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(APIResponse{
        Success: true,
        Data:    tx,
    })
}

func (ws *WalletStore) handleRelayTx(w http.ResponseWriter, r *http.Request) {
    atomic.AddUint64(&ws.metrics.TotalRequests, 1)

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

    if err := ws.RelayTransaction(tx); err != nil {
        http.Error(w, err.Error(), http.StatusBadRequest)
        return
    }

    // Broadcast transaction to WebSocket clients
    ws.BroadcastWebSocketMessage(WebSocketMessage{
        Type:      "transaction",
        Payload:   tx,
        Timestamp: time.Now(),
    })

    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(APIResponse{
        Success: true,
        Data:    tx,
    })
}

func (ws *WalletStore) handleGetMetrics(w http.ResponseWriter, r *http.Request) {
    atomic.AddUint64(&ws.metrics.TotalRequests, 1)

    ws.metrics.UptimeSeconds = uint64(time.Since(ws.startTime).Seconds())

    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(APIResponse{
        Success: true,
        Data:    ws.metrics,
    })
}

func (ws *WalletStore) handleWebSocket(w http.ResponseWriter, r *http.Request) {
    conn, err := upgrader.Upgrade(w, r, nil)
    if err != nil {
        log.Println("WebSocket upgrade error:", err)
        return
    }

    ws.AddWebSocketClient(conn)
    defer func() {
        ws.RemoveWebSocketClient(conn)
        conn.Close()
    }()

    for {
        _, _, err := conn.ReadMessage()
        if err != nil {
            if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
                log.Printf("WebSocket error: %v", err)
            }
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

    // API Routes
    r.HandleFunc("/api/wallet", store.handleCreateWallet).Methods("POST")
    r.HandleFunc("/api/wallet/{address}", store.handleGetWallet).Methods("GET")
    r.HandleFunc("/api/transfer", store.handleTransfer).Methods("POST")
    r.HandleFunc("/api/relay", store.handleRelayTx).Methods("POST")
    r.HandleFunc("/api/metrics", store.handleGetMetrics).Methods("GET")

    // WebSocket Route
    r.HandleFunc("/ws", store.handleWebSocket)

    // Start HTTP server
    srv := &http.Server{
        Handler: r,
        Addr:    "127.0.0.1:8080",
        // Good practice: enforce timeouts for servers you create!
        WriteTimeout: 15 * time.Second,
        ReadTimeout:  15 * time.Second,
    }

    // Run our server in a goroutine so that it doesn't block.
    go func() {
        log.Println("Starting server on :8080")
        if err := srv.ListenAndServe(); err != nil {
            log.Println(err)
        }
    }()

    // Start a goroutine to periodically mine blocks
    go func() {
        ticker := time.NewTicker(10 * time.Second)
        defer ticker.Stop()

        for range ticker.C {
            block, err := store.MineBlock()
            if err != nil {
                log.Printf("Error mining block: %v", err)
                continue
            }

            // Broadcast block to WebSocket clients
            store.BroadcastWebSocketMessage(WebSocketMessage{
                Type:      "block",
                Payload:   block,
                Timestamp: time.Now(),
            })
        }
    }()

    // Graceful shutdown
    c := make(chan os.Signal, 1)
    signal.Notify(c, os.Interrupt, syscall.SIGTERM)
    <-c

    // Create a deadline to wait for.
    ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
    defer cancel()

    // Doesn't block if no connections, but will otherwise wait
    // until the timeout deadline.
    srv.Shutdown(ctx)

    log.Println("Shutting down")
    os.Exit(0)
}