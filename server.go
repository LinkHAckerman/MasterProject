package main

import (
    "context"
    "crypto/sha256"
    "encoding/hex"
    "encoding/json"
    "fmt"
    "log"
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
    store := &WalletStore{
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
    return store
}

func (s *WalletStore) generateTxHash(tx *RelayedTx) string {
    h := sha256.New()
    h.Write([]byte(fmt.Sprintf("%s%s%s%f%f%d%s", tx.From, tx.To, tx.Token, tx.Amount, tx.Fee, tx.Nonce, tx.Timestamp.String())))
    return hex.EncodeToString(h.Sum(nil))
}

func (s *WalletStore) validateAddress(address string) bool {
    return addressRegex.MatchString(address)
}

func (s *WalletStore) validateToken(token string) bool {
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

func (s *WalletStore) CreateWallet(address string) (*Wallet, error) {
    if !s.validateAddress(address) {
        return nil, fmt.Errorf("invalid address format")
    }

    s.mu.Lock()
    defer s.mu.Unlock()

    if _, exists := s.wallets[address]; exists {
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

    s.wallets[address] = wallet
    atomic.AddUint64(&s.metrics.ActiveWallets, 1)

    return wallet, nil
}

func (s *WalletStore) GetWallet(address string) (*Wallet, error) {
    s.mu.RLock()
    defer s.mu.RUnlock()

    wallet, exists := s.wallets[address]
    if !exists {
        return nil, fmt.Errorf("wallet not found")
    }

    return wallet, nil
}

func (s *WalletStore) GetWalletBalance(address string, token string) (float64, error) {
    if !s.validateToken(token) {
        return 0, fmt.Errorf("unsupported token")
    }

    wallet, err := s.GetWallet(address)
    if err != nil {
        return 0, err
    }

    return wallet.Balance[token], nil
}

// ------------------------------------------------------------
// Transaction Operations
// ------------------------------------------------------------

func (s *WalletStore) Transfer(from, to, token string, amount float64) (*RelayedTx, error) {
    if !s.validateAddress(from) || !s.validateAddress(to) {
        return nil, fmt.Errorf("invalid address format")
    }

    if !s.validateToken(token) {
        return nil, fmt.Errorf("unsupported token")
    }

    if amount <= 0 {
        return nil, fmt.Errorf("invalid amount")
    }

    s.mu.Lock()
    defer s.mu.Unlock()

    fromWallet, exists := s.wallets[from]
    if !exists {
        return nil, fmt.Errorf("sender wallet not found")
    }

    toWallet, exists := s.wallets[to]
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
    tx.TxHash = s.generateTxHash(tx)

    s.txHistory[from] = append(s.txHistory[from], tx)
    s.txHistory[to] = append(s.txHistory[to], tx)
    s.allTxs[tx.TxHash] = tx

    atomic.AddUint64(&s.metrics.TotalTransfers, 1)

    return tx, nil
}

func (s *WalletStore) RelayTransaction(req RelayTxRequest) (*RelayedTx, error) {
    if !s.validateAddress(req.From) || !s.validateAddress(req.To) {
        return nil, fmt.Errorf("invalid address format")
    }

    if !s.validateToken(req.Token) {
        return nil, fmt.Errorf("unsupported token")
    }

    if req.Amount <= 0 || req.Fee < 0 {
        return nil, fmt.Errorf("invalid amount or fee")
    }

    s.mu.Lock()
    defer s.mu.Unlock()

    fromWallet, exists := s.wallets[req.From]
    if !exists {
        return nil, fmt.Errorf("sender wallet not found")
    }

    if fromWallet.Nonce != req.Nonce {
        return nil, fmt.Errorf("invalid nonce")
    }

    if fromWallet.Balance[req.Token] < req.Amount+req.Fee {
        return nil, fmt.Errorf("insufficient balance")
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
    tx.TxHash = s.generateTxHash(tx)

    s.mempool = append(s.mempool, tx)
    atomic.AddUint64(&s.metrics.MempoolSize, 1)

    return tx, nil
}

func (s *WalletStore) ProcessMempool() {
    s.mu.Lock()
    defer s.mu.Unlock()

    if len(s.mempool) == 0 {
        return
    }

    block := &BlockInfo{
        BlockNumber: s.currentBlock + 1,
        Timestamp:   time.Now(),
        Txs:         make([]*RelayedTx, 0),
    }

    for _, tx := range s.mempool {
        fromWallet, exists := s.wallets[tx.From]
        if !exists {
            tx.Status = StatusFailed
            tx.ErrorMsg = "sender wallet not found"
            atomic.AddUint64(&s.metrics.FailedTransfers, 1)
            continue
        }

        toWallet, exists := s.wallets[tx.To]
        if !exists {
            tx.Status = StatusFailed
            tx.ErrorMsg = "recipient wallet not found"
            atomic.AddUint64(&s.metrics.FailedTransfers, 1)
            continue
        }

        if fromWallet.Balance[tx.Token] < tx.Amount+tx.Fee {
            tx.Status = StatusFailed
            tx.ErrorMsg = "insufficient balance"
            atomic.AddUint64(&s.metrics.FailedTransfers, 1)
            continue
        }

        fromWallet.Balance[tx.Token] -= tx.Amount + tx.Fee
        toWallet.Balance[tx.Token] += tx.Amount
        fromWallet.Nonce++
        fromWallet.UpdatedAt = time.Now()
        toWallet.UpdatedAt = time.Now()

        tx.Status = StatusConfirmed
        tx.BlockNum = block.BlockNumber

        block.Txs = append(block.Txs, tx)
        s.txHistory[tx.From] = append(s.txHistory[tx.From], tx)
        s.txHistory[tx.To] = append(s.txHistory[tx.To], tx)
        s.allTxs[tx.TxHash] = tx

        atomic.AddUint64(&s.metrics.TotalRelayed, 1)
    }

    block.TxCount = len(block.Txs)
    block.BlockHash = s.generateBlockHash(block)

    s.blocks = append(s.blocks, block)
    s.currentBlock = block.BlockNumber
    s.mempool = make([]*RelayedTx, 0)
    atomic.StoreUint64(&s.metrics.MempoolSize, 0)
}

func (s *WalletStore) generateBlockHash(block *BlockInfo) string {
    h := sha256.New()
    h.Write([]byte(fmt.Sprintf("%d%s%d", block.BlockNumber, block.Timestamp.String(), block.TxCount)))
    return hex.EncodeToString(h.Sum(nil))
}

// ------------------------------------------------------------
// WebSocket Operations
// ------------------------------------------------------------

func (s *WalletStore) AddWebSocketClient(conn *websocket.Conn) {
    s.wsMu.Lock()
    defer s.wsMu.Unlock()
    s.wsClients[conn] = true
}

func (s *WalletStore) RemoveWebSocketClient(conn *websocket.Conn) {
    s.wsMu.Lock()
    defer s.wsMu.Unlock()
    delete(s.wsClients, conn)
}

func (s *WalletStore) BroadcastMessage(msgType string, payload interface{}) {
    s.wsMu.Lock()
    defer s.wsMu.Unlock()

    message := WebSocketMessage{
        Type:      msgType,
        Payload:   payload,
        Timestamp: time.Now(),
    }

    for client := range s.wsClients {
        err := client.WriteJSON(message)
        if err != nil {
            log.Printf("Error broadcasting message: %v", err)
            client.Close()
            delete(s.wsClients, client)
        }
    }
}

// ------------------------------------------------------------
// HTTP Handlers
// ------------------------------------------------------------

func (s *WalletStore) CreateWalletHandler(w http.ResponseWriter, r *http.Request) {
    if !s.limiter.Allow() {
        http.Error(w, "Too many requests", http.StatusTooManyRequests)
        return
    }

    var req CreateWalletRequest
    err := json.NewDecoder(r.Body).Decode(&req)
    if err != nil {
        http.Error(w, err.Error(), http.StatusBadRequest)
        return
    }

    wallet, err := s.CreateWallet(req.Address)
    if err != nil {
        http.Error(w, err.Error(), http.StatusBadRequest)
        return
    }

    atomic.AddUint64(&s.metrics.TotalRequests, 1)

    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(APIResponse{
        Success: true,
        Data:    wallet,
    })
}

func (s *WalletStore) GetWalletHandler(w http.ResponseWriter, r *http.Request) {
    if !s.limiter.Allow() {
        http.Error(w, "Too many requests", http.StatusTooManyRequests)
        return
    }

    vars := mux.Vars(r)
    address := vars["address"]

    wallet, err := s.GetWallet(address)
    if err != nil {
        http.Error(w, err.Error(), http.StatusNotFound)
        return
    }

    atomic.AddUint64(&s.metrics.TotalRequests, 1)

    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(APIResponse{
        Success: true,
        Data:    wallet,
    })
}

func (s *WalletStore) GetWalletBalanceHandler(w http.ResponseWriter, r *http.Request) {
    if !s.limiter.Allow() {
        http.Error(w, "Too many requests", http.StatusTooManyRequests)
        return
    }

    vars := mux.Vars(r)
    address := vars["address"]
    token := vars["token"]

    balance, err := s.GetWalletBalance(address, token)
    if err != nil {
        http.Error(w, err.Error(), http.StatusBadRequest)
        return
    }

    atomic.AddUint64(&s.metrics.TotalRequests, 1)

    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(APIResponse{
        Success: true,
        Data:    balance,
    })
}

func (s *WalletStore) TransferHandler(w http.ResponseWriter, r *http.Request) {
    if !s.limiter.Allow() {
        http.Error(w, "Too many requests", http.StatusTooManyRequests)
        return
    }

    var req TransferRequest
    err := json.NewDecoder(r.Body).Decode(&req)
    if err != nil {
        http.Error(w, err.Error(), http.StatusBadRequest)
        return
    }

    tx, err := s.Transfer(req.From, req.To, req.Token, req.Amount)
    if err != nil {
        http.Error(w, err.Error(), http.StatusBadRequest)
        return
    }

    atomic.AddUint64(&s.metrics.TotalRequests, 1)

    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(APIResponse{
        Success: true,
        Data:    tx,
    })
}

func (s *WalletStore) RelayTransactionHandler(w http.ResponseWriter, r *http.Request) {
    if !s.limiter.Allow() {
        http.Error(w, "Too many requests", http.StatusTooManyRequests)
        return
    }

    var req RelayTxRequest
    err := json.NewDecoder(r.Body).Decode(&req)
    if err != nil {
        http.Error(w, err.Error(), http.StatusBadRequest)
        return
    }

    tx, err := s.RelayTransaction(req)
    if err != nil {
        http.Error(w, err.Error(), http.StatusBadRequest)
        return
    }

    atomic.AddUint64(&s.metrics.TotalRequests, 1)

    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(APIResponse{
        Success: true,
        Data:    tx,
    })
}

func (s *WalletStore) GetMetricsHandler(w http.ResponseWriter, r *http.Request) {
    if !s.limiter.Allow() {
        http.Error(w, "Too many requests", http.StatusTooManyRequests)
        return
    }

    s.metrics.UptimeSeconds = uint64(time.Since(s.startTime).Seconds())

    atomic.AddUint64(&s.metrics.TotalRequests, 1)

    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(APIResponse{
        Success: true,
        Data:    s.metrics,
    })
}

func (s *WalletStore) WebSocketHandler(w http.ResponseWriter, r *http.Request) {
    conn, err := upgrader.Upgrade(w, r, nil)
    if err != nil {
        log.Printf("Error upgrading to WebSocket: %v", err)
        return
    }

    s.AddWebSocketClient(conn)
    defer s.RemoveWebSocketClient(conn)

    for {
        _, _, err := conn.ReadMessage()
        if err != nil {
            log.Printf("Error reading WebSocket message: %v", err)
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

    r.HandleFunc("/api/wallet", store.CreateWalletHandler).Methods("POST")
    r.HandleFunc("/api/wallet/{address}", store.GetWalletHandler).Methods("GET")
    r.HandleFunc("/api/wallet/{address}/balance/{token}", store.GetWalletBalanceHandler).Methods("GET")
    r.HandleFunc("/api/transfer", store.TransferHandler).Methods("POST")
    r.HandleFunc("/api/relay", store.RelayTransactionHandler).Methods("POST")
    r.HandleFunc("/api/metrics", store.GetMetricsHandler).Methods("GET")
    r.HandleFunc("/ws", store.WebSocketHandler)

    srv := &http.Server{
        Handler: r,
        Addr:    "127.0.0.1:8080",
    }

    go func() {
        ticker := time.NewTicker(10 * time.Second)
        defer ticker.Stop()

        for range ticker.C {
            store.ProcessMempool()
            store.BroadcastMessage("block", store.blocks[len(store.blocks)-1])
        }
    }()

    go func() {
        if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
            log.Fatalf("ListenAndServe: %v", err)
        }
    }()

    sigChan := make(chan os.Signal, 1)
    signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)
    <-sigChan

    ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
    defer cancel()

    if err := srv.Shutdown(ctx); err != nil {
        log.Fatalf("Server Shutdown Failed:%+v", err)
    }

    log.Println("Server Exited Properly")
}