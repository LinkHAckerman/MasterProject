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
        currentBlock: 1000000,
        wsClients:    make(map[*websocket.Conn]bool),
        limiter:      rate.NewLimiter(rate.Every(time.Second/100), 200),
    }
    store.seedDemoData()
    go store.processMempool()
    return store
}

func (s *WalletStore) seedDemoData() {
    demoAddrs := []string{
        "0x71C7656EC7ab88b098defB751B7401B5f6d8976F",
        "0xF39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
        "0x70997970C51812dc3A010C7d01b50e0d17dc79C8",
    }
    for i, addr := range demoAddrs {
        w := &Wallet{
            Address: strings.ToLower(addr),
            Balance: map[string]float64{
                "OPUS": float64(10000 * (i + 1)),
                "ETH":  float64(50 * (i + 1)),
                "BTC":  float64(2.5 * (i + 1)),
                "SOL":  float64(250 * (i + 1)),
                "USDC": float64(50000 * (i + 1)),
            },
            Nonce:     uint64(i * 5),
            CreatedAt: time.Now().Add(-24 * time.Hour * time.Duration(i+1)),
            UpdatedAt: time.Now(),
        }
        s.wallets[w.Address] = w
        s.txHistory[w.Address] = make([]*RelayedTx, 0)
    }
    s.metrics.ActiveWallets = uint64(len(s.wallets))
}

func isValidAddress(addr string) bool {
    return addressRegex.MatchString(addr)
}

func isSupportedToken(token string) bool {
    for _, t := range SupportedTokens {
        if strings.EqualFold(t, token) {
            return true
        }
    }
    return false
}

func computeHash(data string) string {
    h := sha256.Sum256([]byte(data))
    return "0x" + hex.EncodeToString(h[:])
}

// ------------------------------------------------------------
// Wallet & Transaction Methods
// ------------------------------------------------------------

func (s *WalletStore) GetOrCreateWallet(addr string) (*Wallet, error) {
    norm := strings.ToLower(addr)
    if !isValidAddress(norm) {
        return nil, fmt.Errorf("invalid Ethereum address format")
    }

    s.mu.Lock()
    defer s.mu.Unlock()

    if w, exists := s.wallets[norm]; exists {
        return w, nil
    }

    w := &Wallet{
        Address:   norm,
        Balance:   map[string]float64{"OPUS": 100.0, "ETH": 1.0, "BTC": 0.0, "SOL": 0.0, "USDC": 500.0},
        Nonce:     0,
        CreatedAt: time.Now(),
        UpdatedAt: time.Now(),
    }
    s.wallets[norm] = w
    s.txHistory[norm] = make([]*RelayedTx, 0)
    s.metrics.ActiveWallets = uint64(len(s.wallets))
    return w, nil
}

func (s *WalletStore) GetWallet(addr string) (*Wallet, bool) {
    norm := strings.ToLower(addr)
    s.mu.RLock()
    defer s.mu.RUnlock()
    w, ok := s.wallets[norm]
    return w, ok
}

func (s *WalletStore) addToMempool(tx *RelayedTx) {
    s.mu.Lock()
    s.mempool = append(s.mempool, tx)
    s.metrics.MempoolSize = uint64(len(s.mempool))
    s.mu.Unlock()
    s.broadcastWS(WebSocketMessage{Type: "mempool_update", Payload: tx, Timestamp: time.Now()})
}

func (s *WalletStore) Transfer(req TransferRequest) (*RelayedTx, error) {
    from := strings.ToLower(req.From)
    to := strings.ToLower(req.To)
    token := strings.ToUpper(req.Token)

    if !isValidAddress(from) || !isValidAddress(to) {
        atomic.AddUint64(&s.metrics.FailedTransfers, 1)
        return nil, fmt.Errorf("invalid sender or recipient address")
    }
    if !isSupportedToken(token) {
        atomic.AddUint64(&s.metrics.FailedTransfers, 1)
        return nil, fmt.Errorf("unsupported token symbol: %s", token)
    }
    if req.Amount <= 0 {
        atomic.AddUint64(&s.metrics.FailedTransfers, 1)
        return nil, fmt.Errorf("transfer amount must be positive")
    }

    s.mu.Lock()
    defer s.mu.Unlock()

    sender, ok := s.wallets[from]
    if !ok {
        atomic.AddUint64(&s.metrics.FailedTransfers, 1)
        return nil, fmt.Errorf("sender wallet does not exist")
    }
    if sender.Balance[token] < req.Amount {
        atomic.AddUint64(&s.metrics.FailedTransfers, 1)
        return nil, fmt.Errorf("insufficient balance for %s", token)
    }

    recipient, ok := s.wallets[to]
    if !ok {
        recipient = &Wallet{Address: to, Balance: map[string]float64{"OPUS": 0, "ETH": 0, "BTC": 0, "SOL": 0, "USDC": 0}, Nonce: 0, CreatedAt: time.Now(), UpdatedAt: time.Now()}
        s.wallets[to] = recipient
        s.txHistory[to] = make([]*RelayedTx, 0)
        s.metrics.ActiveWallets = uint64(len(s.wallets))
    }

    // Perform balance updates
    sender.Balance[token] -= req.Amount
    recipient.Balance[token] += req.Amount
    sender.Nonce++
    sender.UpdatedAt = time.Now()
    recipient.UpdatedAt = time.Now()

    // Create transaction record
    tx := &RelayedTx{
        TxHash:    computeHash(fmt.Sprintf("%s%s%s%f%d", from, to, token, req.Amount, time.Now().UnixNano())),
        From:      from,
        To:        to,
        Token:     token,
        Amount:    req.Amount,
        Fee:       0,
        Nonce:     sender.Nonce,
        Status:    StatusPending,
        Timestamp: time.Now(),
    }

    // Store transaction
    s.allTxs[tx.TxHash] = tx
    s.txHistory[from] = append(s.txHistory[from], tx)
    s.txHistory[to] = append(s.txHistory[to], tx)
    atomic.AddUint64(&s.metrics.TotalTransfers, 1)
    s.addToMempool(tx)
    return tx, nil
}

func (s *WalletStore) Relay(req RelayTxRequest) (*RelayedTx, error) {
    from := strings.ToLower(req.From)
    to := strings.ToLower(req.To)
    token := strings.ToUpper(req.Token)

    if !isValidAddress(from) || !isValidAddress(to) {
        atomic.AddUint64(&s.metrics.FailedTransfers, 1)
        return nil, fmt.Errorf("invalid address")
    }
    if !isSupportedToken(token) {
        atomic.AddUint64(&s.metrics.FailedTransfers, 1)
        return nil, fmt.Errorf("unsupported token")
    }
    if req.Amount <= 0 {
        atomic.AddUint64(&s.metrics.FailedTransfers, 1)
        return nil, fmt.Errorf("amount must be positive")
    }
    if req.Fee < 0 {
        atomic.AddUint64(&s.metrics.FailedTransfers, 1)
        return nil, fmt.Errorf("fee cannot be negative")
    }

    s.mu.Lock()
    defer s.mu.Unlock()

    sender, ok := s.wallets[from]
    if !ok {
        atomic.AddUint64(&s.metrics.FailedTransfers, 1)
        return nil, fmt.Errorf("sender wallet does not exist")
    }
    total := req.Amount + req.Fee
    if sender.Balance[token] < total {
        atomic.AddUint64(&s.metrics.FailedTransfers, 1)
        return nil, fmt.Errorf("insufficient balance for amount+fee")
    }

    recipient, ok := s.wallets[to]
    if !ok {
        recipient = &Wallet{Address: to, Balance: map[string]float64{"OPUS": 0, "ETH": 0, "BTC": 0, "SOL": 0, "USDC": 0}, Nonce: 0, CreatedAt: time.Now(), UpdatedAt: time.Now()}
        s.wallets[to] = recipient
        s.txHistory[to] = make([]*RelayedTx, 0)
        s.metrics.ActiveWallets = uint64(len(s.wallets))
    }

    // Update balances
    sender.Balance[token] -= total
    recipient.Balance[token] += req.Amount
    // Assume fee is burned or sent to a system address; omitted for brevity
    sender.Nonce++
    sender.UpdatedAt = time.Now()
    recipient.UpdatedAt = time.Now()

    tx := &RelayedTx{
        TxHash:    computeHash(fmt.Sprintf("%s%s%s%f%f%d", from, to, token, req.Amount, req.Fee, time.Now().UnixNano())),
        From:      from,
        To:        to,
        Token:     token,
        Amount:    req.Amount,
        Fee:       req.Fee,
        Nonce:     req.Nonce,
        Signature: req.Signature,
        Status:    StatusPending,
        Timestamp: time.Now(),
    }
    s.allTxs[tx.TxHash] = tx
    s.txHistory[from] = append(s.txHistory[from], tx)
    s.txHistory[to] = append(s.txHistory[to], tx)
    atomic.AddUint64(&s.metrics.TotalRelayed, 1)
    s.addToMempool(tx)
    return tx, nil
}

func (s *WalletStore) GetMetrics() Metrics {
    uptime := uint64(time.Since(s.startTime).Seconds())
    atomic.StoreUint64(&s.metrics.UptimeSeconds, uptime)
    atomic.StoreUint64(&s.metrics.MempoolSize, uint64(len(s.mempool)))
    return s.metrics
}

func (s *WalletStore) GetTxHistory(addr string) ([]*RelayedTx, bool) {
    norm := strings.ToLower(addr)
    s.mu.RLock()
    defer s.mu.RUnlock()
    hist, ok := s.txHistory[norm]
    return hist, ok
}

func (s *WalletStore) broadcastWS(msg WebSocketMessage) {
    s.wsMu.Lock()
    defer s.wsMu.Unlock()
    for conn := range s.wsClients {
        if err := conn.WriteJSON(msg); err != nil {
            conn.Close()
            delete(s.wsClients, conn)
        }
    }
}

func (s *WalletStore) processMempool() {
    ticker := time.NewTicker(5 * time.Second)
    defer ticker.Stop()
    for {
        <-ticker.C
        s.mu.Lock()
        if len(s.mempool) == 0 {
            s.mu.Unlock()
            continue
        }
        // Simulate block creation
        blockTxs := s.mempool
        s.mempool = make([]*RelayedTx, 0)
        s.currentBlock++
        block := &BlockInfo{
            BlockNumber: s.currentBlock,
            Timestamp:   time.Now(),
            TxCount:     len(blockTxs),
            Txs:         blockTxs,
        }
        // Compute block hash from concatenated tx hashes
        var sb strings.Builder
        for _, tx := range blockTxs {
            tx.Status = StatusConfirmed
            tx.BlockNum = block.BlockNumber
            sb.WriteString(tx.TxHash)
        }
        block.BlockHash = computeHash(sb.String())
        s.blocks = append(s.blocks, block)
        s.mu.Unlock()
        // Broadcast block info
        s.broadcastWS(WebSocketMessage{Type: "new_block", Payload: block, Timestamp: time.Now()})
    }
}

// ------------------------------------------------------------
// HTTP Handlers
// ------------------------------------------------------------

func writeJSON(w http.ResponseWriter, status int, resp APIResponse) {
    w.Header().Set("Content-Type", "application/json")
    w.WriteHeader(status)
    json.NewEncoder(w).Encode(resp)
}

func (s *WalletStore) handleCreateWallet(w http.ResponseWriter, r *http.Request) {
    var req CreateWalletRequest
    if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
        writeJSON(w, http.StatusBadRequest, APIResponse{Success: false, Error: "invalid JSON"})
        return
    }
    wallet, err := s.GetOrCreateWallet(req.Address)
    if err != nil {
        writeJSON(w, http.StatusBadRequest, APIResponse{Success: false, Error: err.Error()})
        return
    }
    writeJSON(w, http.StatusCreated, APIResponse{Success: true, Data: wallet})
}

func (s *WalletStore) handleGetWallet(w http.ResponseWriter, r *http.Request) {
    addr := mux.Vars(r)["address"]
    wallet, ok := s.GetWallet(addr)
    if !ok {
        writeJSON(w, http.StatusNotFound, APIResponse{Success: false, Error: "wallet not found"})
        return
    }
    writeJSON(w, http.StatusOK, APIResponse{Success: true, Data: wallet})
}

func (s *WalletStore) handleTransfer(w http.ResponseWriter, r *http.Request) {
    var req TransferRequest
    if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
        writeJSON(w, http.StatusBadRequest, APIResponse{Success: false, Error: "invalid JSON"})
        return
    }
    tx, err := s.Transfer(req)
    if err != nil {
        writeJSON(w, http.StatusBadRequest, APIResponse{Success: false, Error: err.Error()})
        return
    }
    writeJSON(w, http.StatusOK, APIResponse{Success: true, Data: tx})
}

func (s *WalletStore) handleRelay(w http.ResponseWriter, r *http.Request) {
    var req RelayTxRequest
    if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
        writeJSON(w, http.StatusBadRequest, APIResponse{Success: false, Error: "invalid JSON"})
        return
    }
    tx, err := s.Relay(req)
    if err != nil {
        writeJSON(w, http.StatusBadRequest, APIResponse{Success: false, Error: err.Error()})
        return
    }
    writeJSON(w, http.StatusOK, APIResponse{Success: true, Data: tx})
}

func (s *WalletStore) handleMetrics(w http.ResponseWriter, r *http.Request) {
    metrics := s.GetMetrics()
    writeJSON(w, http.StatusOK, APIResponse{Success: true, Data: metrics})
}

func (s *WalletStore) handleTxHistory(w http.ResponseWriter, r *http.Request) {
    addr := mux.Vars(r)["address"]
    hist, ok := s.GetTxHistory(addr)
    if !ok {
        writeJSON(w, http.StatusNotFound, APIResponse{Success: false, Error: "wallet not found"})
        return
    }
    writeJSON(w, http.StatusOK, APIResponse{Success: true, Data: hist})
}

func (s *WalletStore) handleWebSocket(w http.ResponseWriter, r *http.Request) {
    conn, err := upgrader.Upgrade(w, r, nil)
    if err != nil {
        log.Printf("WebSocket upgrade error: %v", err)
        return
    }
    s.wsMu.Lock()
    s.wsClients[conn] = true
    s.wsMu.Unlock()
    // Simple read loop to keep connection alive
    for {
        _, _, err := conn.ReadMessage()
        if err != nil {
            break
        }
    }
    s.wsMu.Lock()
    delete(s.wsClients, conn)
    s.wsMu.Unlock()
    conn.Close()
}

// ------------------------------------------------------------
// Main
// ------------------------------------------------------------

func main() {
    store := NewWalletStore()
    r := mux.NewRouter()

    // REST endpoints
    r.HandleFunc("/wallet", store.handleCreateWallet).Methods("POST")
    r.HandleFunc("/wallet/{address}", store.handleGetWallet).Methods("GET")
    r.HandleFunc("/transfer", store.handleTransfer).Methods("POST")
    r.HandleFunc("/relay", store.handleRelay).Methods("POST")
    r.HandleFunc("/metrics", store.handleMetrics).Methods("GET")
    r.HandleFunc("/txhistory/{address}", store.handleTxHistory).Methods("GET")
    r.HandleFunc("/ws", store.handleWebSocket)

    srv := &http.Server{
        Addr:    ":8080",
        Handler: r,
    }

    // Graceful shutdown handling
    go func() {
        if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
            log.Fatalf("listen: %s\n", err)
        }
    }()
    log.Println("Server started on :8080")

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
