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
        limiter:      rate.NewLimiter(rate.Every(100*time.Millisecond), 100), // 10 req/s burst 100
    }
}

// validateAddress ensures the address matches the expected hex format.
func validateAddress(addr string) bool {
    return addressRegex.MatchString(addr)
}

// isSupportedToken checks if a token symbol is allowed.
func isSupportedToken(tok string) bool {
    for _, t := range SupportedTokens {
        if strings.EqualFold(t, tok) {
            return true
        }
    }
    return false
}

// generateTxHash creates a deterministic hash based on tx fields and a random nonce.
func generateTxHash(tx *RelayedTx) string {
    h := sha256.New()
    data := fmt.Sprintf("%s|%s|%s|%f|%f|%d|%s|%d", tx.From, tx.To, tx.Token, tx.Amount, tx.Fee, tx.Nonce, tx.Signature, rand.Uint64())
    h.Write([]byte(data))
    return hex.EncodeToString(h.Sum(nil))
}

// broadcast sends a message to all connected websocket clients.
func (ws *WalletStore) broadcast(msg WebSocketMessage) {
    ws.wsMu.Lock()
    defer ws.wsMu.Unlock()
    payload, err := json.Marshal(msg)
    if err != nil {
        log.Printf("WebSocket marshal error: %v", err)
        return
    }
    for conn := range ws.wsClients {
        if err := conn.WriteMessage(websocket.TextMessage, payload); err != nil {
            log.Printf("WebSocket write error, removing client: %v", err)
            conn.Close()
            delete(ws.wsClients, conn)
        }
    }
}

// addToMempool appends a transaction and updates metrics.
func (ws *WalletStore) addToMempool(tx *RelayedTx) {
    ws.mu.Lock()
    defer ws.mu.Unlock()
    ws.mempool = append(ws.mempool, tx)
    atomic.AddUint64(&ws.metrics.TotalRelayed, 1)
    atomic.StoreUint64(&ws.metrics.MempoolSize, uint64(len(ws.mempool)))
    ws.broadcast(WebSocketMessage{Type: "mempool_update", Payload: tx, Timestamp: time.Now()})
}

// processMempool simulates block creation every 5 seconds.
func (ws *WalletStore) processMempool() {
    ticker := time.NewTicker(5 * time.Second)
    for range ticker.C {
        ws.mu.Lock()
        if len(ws.mempool) == 0 {
            ws.mu.Unlock()
            continue
        }
        blockTxs := ws.mempool
        ws.mempool = make([]*RelayedTx, 0)
        ws.currentBlock++
        blockHash := generateTxHash(&RelayedTx{From: "block", To: "block", Token: "OPUS", Amount: 0, Nonce: ws.currentBlock})
        block := &BlockInfo{BlockNumber: ws.currentBlock, BlockHash: blockHash, TxCount: len(blockTxs), Timestamp: time.Now(), Txs: blockTxs}
        ws.blocks = append(ws.blocks, block)
        // Update each tx status
        for _, tx := range blockTxs {
            tx.Status = StatusConfirmed
            tx.BlockNum = ws.currentBlock
            ws.allTxs[tx.TxHash] = tx
            ws.txHistory[tx.From] = append(ws.txHistory[tx.From], tx)
            ws.txHistory[tx.To] = append(ws.txHistory[tx.To], tx)
        }
        atomic.StoreUint64(&ws.metrics.MempoolSize, 0)
        ws.mu.Unlock()
        ws.broadcast(WebSocketMessage{Type: "new_block", Payload: block, Timestamp: time.Now()})
    }
}

// ------------------------------------------------------------
// Wallet Operations
// ------------------------------------------------------------

func (ws *WalletStore) CreateWallet(address string) (*Wallet, error) {
    if !validateAddress(address) {
        return nil, fmt.Errorf("invalid address format")
    }
    ws.mu.Lock()
    defer ws.mu.Unlock()
    if _, exists := ws.wallets[address]; exists {
        return nil, fmt.Errorf("wallet already exists")
    }
    wallet := &Wallet{Address: address, Balance: make(map[string]float64), Nonce: 0, CreatedAt: time.Now(), UpdatedAt: time.Now()}
    // Initialize balances to zero for all supported tokens
    for _, t := range SupportedTokens {
        wallet.Balance[t] = 0.0
    }
    ws.wallets[address] = wallet
    atomic.AddUint64(&ws.metrics.ActiveWallets, 1)
    return wallet, nil
}

func (ws *WalletStore) GetWallet(address string) (*Wallet, bool) {
    ws.mu.RLock()
    defer ws.mu.RUnlock()
    w, ok := ws.wallets[address]
    return w, ok
}

func (ws *WalletStore) internalTransfer(tx *RelayedTx) error {
    // Basic checks
    if !isSupportedToken(tx.Token) {
        return fmt.Errorf("unsupported token %s", tx.Token)
    }
    fromW, ok := ws.wallets[tx.From]
    if !ok {
        return fmt.Errorf("sender wallet not found")
    }
    toW, ok := ws.wallets[tx.To]
    if !ok {
        return fmt.Errorf("receiver wallet not found")
    }
    if fromW.Balance[tx.Token] < tx.Amount {
        return fmt.Errorf("insufficient balance")
    }
    // Perform transfer atomically
    fromW.Balance[tx.Token] -= tx.Amount
    toW.Balance[tx.Token] += tx.Amount
    fromW.Nonce++
    now := time.Now()
    fromW.UpdatedAt = now
    toW.UpdatedAt = now
    tx.Status = StatusConfirmed
    tx.Timestamp = now
    tx.TxHash = generateTxHash(tx)
    ws.allTxs[tx.TxHash] = tx
    ws.txHistory[tx.From] = append(ws.txHistory[tx.From], tx)
    ws.txHistory[tx.To] = append(ws.txHistory[tx.To], tx)
    atomic.AddUint64(&ws.metrics.TotalTransfers, 1)
    return nil
}

func (ws *WalletStore) Transfer(from, to, token string, amount float64) (*RelayedTx, error) {
    tx := &RelayedTx{From: from, To: to, Token: token, Amount: amount, Fee: 0, Nonce: 0, Status: StatusPending, Timestamp: time.Now()}
    ws.mu.Lock()
    // assign nonce from sender wallet if exists
    if sender, ok := ws.wallets[from]; ok {
        tx.Nonce = sender.Nonce
    }
    ws.mu.Unlock()
    if err := ws.internalTransfer(tx); err != nil {
        return nil, err
    }
    ws.broadcast(WebSocketMessage{Type: "transfer", Payload: tx, Timestamp: time.Now()})
    return tx, nil
}

func (ws *WalletStore) RelayTransaction(req RelayTxRequest) (*RelayedTx, error) {
    // Basic validation
    if !validateAddress(req.From) || !validateAddress(req.To) {
        return nil, fmt.Errorf("invalid address")
    }
    if !isSupportedToken(req.Token) {
        return nil, fmt.Errorf("unsupported token")
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
    // In a real system we would verify the signature here.
    // For this mock, we just add to mempool.
    ws.addToMempool(tx)
    return tx, nil
}

// ------------------------------------------------------------
// HTTP Handlers
// ------------------------------------------------------------

func (ws *WalletStore) handleCreateWallet(w http.ResponseWriter, r *http.Request) {
    atomic.AddUint64(&ws.metrics.TotalRequests, 1)
    var req CreateWalletRequest
    if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
        respondJSON(w, http.StatusBadRequest, APIResponse{Success: false, Error: "invalid JSON"})
        return
    }
    wallet, err := ws.CreateWallet(req.Address)
    if err != nil {
        respondJSON(w, http.StatusBadRequest, APIResponse{Success: false, Error: err.Error()})
        return
    }
    respondJSON(w, http.StatusCreated, APIResponse{Success: true, Data: wallet})
}

func (ws *WalletStore) handleTransfer(w http.ResponseWriter, r *http.Request) {
    atomic.AddUint64(&ws.metrics.TotalRequests, 1)
    var req TransferRequest
    if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
        respondJSON(w, http.StatusBadRequest, APIResponse{Success: false, Error: "invalid JSON"})
        return
    }
    tx, err := ws.Transfer(req.From, req.To, req.Token, req.Amount)
    if err != nil {
        atomic.AddUint64(&ws.metrics.FailedTransfers, 1)
        respondJSON(w, http.StatusBadRequest, APIResponse{Success: false, Error: err.Error()})
        return
    }
    respondJSON(w, http.StatusOK, APIResponse{Success: true, Data: tx})
}

func (ws *WalletStore) handleRelay(w http.ResponseWriter, r *http.Request) {
    atomic.AddUint64(&ws.metrics.TotalRequests, 1)
    var req RelayTxRequest
    if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
        respondJSON(w, http.StatusBadRequest, APIResponse{Success: false, Error: "invalid JSON"})
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

func (ws *WalletStore) handleGetWallet(w http.ResponseWriter, r *http.Request) {
    atomic.AddUint64(&ws.metrics.TotalRequests, 1)
    addr := mux.Vars(r)["address"]
    wallet, ok := ws.GetWallet(addr)
    if !ok {
        respondJSON(w, http.StatusNotFound, APIResponse{Success: false, Error: "wallet not found"})
        return
    }
    respondJSON(w, http.StatusOK, APIResponse{Success: true, Data: wallet})
}

func (ws *WalletStore) handleMetrics(w http.ResponseWriter, r *http.Request) {
    atomic.AddUint64(&ws.metrics.TotalRequests, 1)
    // Update uptime
    uptime := uint64(time.Since(ws.startTime).Seconds())
    atomic.StoreUint64(&ws.metrics.UptimeSeconds, uptime)
    respondJSON(w, http.StatusOK, APIResponse{Success: true, Data: ws.metrics})
}

func (ws *WalletStore) handleWebSocket(w http.ResponseWriter, r *http.Request) {
    conn, err := upgrader.Upgrade(w, r, nil)
    if err != nil {
        log.Printf("WebSocket upgrade error: %v", err)
        return
    }
    ws.wsMu.Lock()
    ws.wsClients[conn] = true
    ws.wsMu.Unlock()
    // Simple read loop to keep connection alive; we ignore incoming messages.
    go func() {
        defer func() {
            ws.wsMu.Lock()
            delete(ws.wsClients, conn)
            ws.wsMu.Unlock()
            conn.Close()
        }()
        for {
            if _, _, err := conn.NextReader(); err != nil {
                return
            }
        }
    }()
}

func respondJSON(w http.ResponseWriter, status int, payload APIResponse) {
    w.Header().Set("Content-Type", "application/json")
    w.WriteHeader(status)
    json.NewEncoder(w).Encode(payload)
}

// ------------------------------------------------------------
// Server Setup & Graceful Shutdown
// ------------------------------------------------------------

func main() {
    store := NewWalletStore()
    // Start background mempool processor
    go store.processMempool()

    r := mux.NewRouter()
    api := r.PathPrefix("/api/v1").Subrouter()
    api.HandleFunc("/wallet", store.handleCreateWallet).Methods("POST")
    api.HandleFunc("/wallet/{address}", store.handleGetWallet).Methods("GET")
    api.HandleFunc("/transfer", store.handleTransfer).Methods("POST")
    api.HandleFunc("/relay", store.handleRelay).Methods("POST")
    api.HandleFunc("/metrics", store.handleMetrics).Methods("GET")
    r.HandleFunc("/ws", store.handleWebSocket)

    srv := &http.Server{Addr: ":8080", Handler: r}

    // Signal handling for graceful shutdown
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
        log.Fatalf("ListenAndServe error: %v", err)
    }
    log.Println("Server exited gracefully")
}
