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

func (ws *WalletStore) Transfer(from, to, token string, amount float64) (*RelayedTx, error) {
    if !ws.validateAddress(from) || !ws.validateAddress(to) {
        return nil, fmt.Errorf("invalid address format")
    }

    if !ws.validateToken(token) {
        return nil, fmt.Errorf("unsupported token")
    }

    if amount <= 0 {
        return nil, fmt.Errorf("invalid amount")
    }

    ws.mu.Lock()
    defer ws.mu.Unlock()

    fromWallet, exists := ws.wallets[from]
    if !exists {
        return nil, fmt.Errorf("sender wallet not found")
    }

    toWallet, exists := ws.wallets[to]
    if !exists {
        return nil, fmt.Errorf("recipient wallet not found")
    }

    if fromWallet.Balance[token] < amount {
        return nil, fmt.Errorf("insufficient balance")
    }

    fromWallet.Balance[token] -= amount
    toWallet.Balance[token] += amount

    fromWallet.Nonce++
    fromWallet.UpdatedAt = time.Now()
    toWallet.UpdatedAt = time.Now()

    tx := &RelayedTx{
        From:      from,
        To:        to,
        Token:     token,
        Amount:    amount,
        Fee:       0,
        Nonce:     fromWallet.Nonce,
        Status:    StatusConfirmed,
        Timestamp: time.Now(),
    }

    tx.TxHash = ws.generateTxHash(tx)

    ws.txHistory[from] = append(ws.txHistory[from], tx)
    ws.txHistory[to] = append(ws.txHistory[to], tx)
    ws.allTxs[tx.TxHash] = tx

    atomic.AddUint64(&ws.metrics.TotalTransfers, 1)

    return tx, nil
}

// ------------------------------------------------------------
// Transaction Relaying
// ------------------------------------------------------------

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

    tx.Status = StatusRelayed
    tx.Timestamp = time.Now()
    tx.TxHash = ws.generateTxHash(tx)

    ws.mempool = append(ws.mempool, tx)
    atomic.AddUint64(&ws.metrics.MempoolSize, 1)
    atomic.AddUint64(&ws.metrics.TotalRelayed, 1)

    return nil
}

// ------------------------------------------------------------
// Block Mining & Processing
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
        Txs:         make([]*RelayedTx, 0, len(ws.mempool)),
    }

    for _, tx := range ws.mempool {
        fromWallet, exists := ws.wallets[tx.From]
        if !exists {
            tx.Status = StatusFailed
            tx.ErrorMsg = "sender wallet not found"
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
        fromWallet.Nonce++
        fromWallet.UpdatedAt = time.Now()

        toWallet, exists := ws.wallets[tx.To]
        if !exists {
            tx.Status = StatusFailed
            tx.ErrorMsg = "recipient wallet not found"
            atomic.AddUint64(&ws.metrics.FailedTransfers, 1)
            continue
        }

        toWallet.Balance[tx.Token] += tx.Amount
        toWallet.UpdatedAt = time.Now()

        tx.Status = StatusConfirmed
        tx.BlockNum = block.BlockNumber

        block.Txs = append(block.Txs, tx)
        ws.txHistory[tx.From] = append(ws.txHistory[tx.From], tx)
        ws.txHistory[tx.To] = append(ws.txHistory[tx.To], tx)
        ws.allTxs[tx.TxHash] = tx
    }

    block.TxCount = len(block.Txs)
    block.BlockHash = ws.generateBlockHash(block)

    ws.blocks = append(ws.blocks, block)
    ws.currentBlock = block.BlockNumber
    ws.mempool = nil
    atomic.StoreUint64(&ws.metrics.MempoolSize, 0)

    return block, nil
}

func (ws *WalletStore) generateBlockHash(block *BlockInfo) string {
    h := sha256.New()
    h.Write([]byte(fmt.Sprintf("%d%s%d", block.BlockNumber, block.Timestamp, block.TxCount)))
    for _, tx := range block.Txs {
        h.Write([]byte(tx.TxHash))
    }
    return hex.EncodeToString(h.Sum(nil))
}

// ------------------------------------------------------------
// WebSocket & Real-time Updates
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

func (ws *WalletStore) BroadcastMessage(msgType string, payload interface{}) {
    ws.wsMu.Lock()
    defer ws.wsMu.Unlock()

    message := WebSocketMessage{
        Type:      msgType,
        Payload:   payload,
        Timestamp: time.Now(),
    }

    for client := range ws.wsClients {
        err := client.WriteJSON(message)
        if err != nil {
            log.Printf("Error broadcasting message: %v", err)
            client.Close()
            delete(ws.wsClients, client)
        }
    }
}

// ------------------------------------------------------------
// API Handlers
// ------------------------------------------------------------

func (ws *WalletStore) CreateWalletHandler(w http.ResponseWriter, r *http.Request) {
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

    atomic.AddUint64(&ws.metrics.TotalRequests, 1)

    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(APIResponse{
        Success: true,
        Data:    wallet,
    })
}

func (ws *WalletStore) GetWalletHandler(w http.ResponseWriter, r *http.Request) {
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

    atomic.AddUint64(&ws.metrics.TotalRequests, 1)

    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(APIResponse{
        Success: true,
        Data:    wallet,
    })
}

func (ws *WalletStore) TransferHandler(w http.ResponseWriter, r *http.Request) {
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

    atomic.AddUint64(&ws.metrics.TotalRequests, 1)

    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(APIResponse{
        Success: true,
        Data:    tx,
    })
}

func (ws *WalletStore) RelayTxHandler(w http.ResponseWriter, r *http.Request) {
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
        From:      req.From,
        To:        req.To,
        Token:     req.Token,
        Amount:    req.Amount,
        Fee:       req.Fee,
        Nonce:     req.Nonce,
        Signature: req.Signature,
    }

    err = ws.RelayTransaction(tx)
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

func (ws *WalletStore) MineBlockHandler(w http.ResponseWriter, r *http.Request) {
    if !ws.limiter.Allow() {
        http.Error(w, "Too many requests", http.StatusTooManyRequests)
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
        http.Error(w, "Too many requests", http.StatusTooManyRequests)
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
        log.Printf("Error upgrading connection: %v", err)
        return
    }

    ws.AddWebSocketClient(conn)
    defer ws.RemoveWebSocketClient(conn)

    for {
        _, _, err := conn.ReadMessage()
        if err != nil {
            log.Printf("Error reading message: %v", err)
            break
        }
    }
}

// ------------------------------------------------------------
// Main & Server Setup
// ------------------------------------------------------------

func main() {
    rand.Seed(time.Now().UnixNano())

    walletStore := NewWalletStore()

    r := mux.NewRouter()

    r.HandleFunc("/api/wallet", walletStore.CreateWalletHandler).Methods("POST")
    r.HandleFunc("/api/wallet/{address}", walletStore.GetWalletHandler).Methods("GET")
    r.HandleFunc("/api/transfer", walletStore.TransferHandler).Methods("POST")
    r.HandleFunc("/api/relay", walletStore.RelayTxHandler).Methods("POST")
    r.HandleFunc("/api/mine", walletStore.MineBlockHandler).Methods("POST")
    r.HandleFunc("/api/metrics", walletStore.GetMetricsHandler).Methods("GET")
    r.HandleFunc("/ws", walletStore.WebSocketHandler)

    srv := &http.Server{
        Handler:      r,
        Addr:         "127.0.0.1:8000",
        WriteTimeout: 15 * time.Second,
        ReadTimeout:  15 * time.Second,
    }

    go func() {
        log.Println("Starting server on :8000")
        if err := srv.ListenAndServe(); err != nil {
            log.Fatal(err)
        }
    }()

    c := make(chan os.Signal, 1)
    signal.Notify(c, os.Interrupt, syscall.SIGTERM)
    <-c

    ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
    defer cancel()
    srv.Shutdown(ctx)

    log.Println("Shutting down server")
    os.Exit(0)
}