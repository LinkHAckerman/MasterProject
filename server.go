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
        currentBlock: 18450200,
        wsClients:    make(map[*websocket.Conn]bool),
        limiter:      rate.NewLimiter(rate.Limit(200), 400), // 200 req/s burst 400
    }

    // Seed the relayer gas‑station wallet (dead address used as fee collector)
    relayer := &Wallet{
        Address:   "0x000000000000000000000000000000000000dead",
        Balance:   map[string]float64{"OPUS": 0},
        Nonce:     0,
        CreatedAt: time.Now(),
        UpdatedAt: time.Now(),
    }
    store.wallets[relayer.Address] = relayer
    atomic.AddUint64(&store.metrics.ActiveWallets, 1)
    return store
}

func (s *WalletStore) isSupportedToken(tok string) bool {
    for _, t := range SupportedTokens {
        if t == strings.ToUpper(tok) {
            return true
        }
    }
    return false
}

func (s *WalletStore) AddWallet(address string) (*Wallet, error) {
    if !addressRegex.MatchString(address) {
        return nil, fmt.Errorf("invalid address format")
    }
    s.mu.Lock()
    defer s.mu.Unlock()
    if _, exists := s.wallets[address]; exists {
        return nil, fmt.Errorf("wallet already exists")
    }
    w := &Wallet{Address: address, Balance: make(map[string]float64), Nonce: 0, CreatedAt: time.Now(), UpdatedAt: time.Now()}
    s.wallets[address] = w
    atomic.AddUint64(&s.metrics.ActiveWallets, 1)
    return w, nil
}

func (s *WalletStore) GetWallet(address string) (*Wallet, error) {
    s.mu.RLock()
    defer s.mu.RUnlock()
    w, ok := s.wallets[address]
    if !ok {
        return nil, fmt.Errorf("wallet not found")
    }
    return w, nil
}

func (s *WalletStore) Transfer(req TransferRequest) (*RelayedTx, error) {
    // Basic validation
    if !addressRegex.MatchString(req.From) || !addressRegex.MatchString(req.To) {
        return nil, fmt.Errorf("invalid address")
    }
    if !s.isSupportedToken(req.Token) {
        return nil, fmt.Errorf("unsupported token")
    }
    if req.Amount <= 0 {
        return nil, fmt.Errorf("amount must be positive")
    }

    s.mu.Lock()
    defer s.mu.Unlock()

    fromW, ok := s.wallets[req.From]
    if !ok {
        return nil, fmt.Errorf("sender wallet not found")
    }
    toW, ok := s.wallets[req.To]
    if !ok {
        // auto‑create recipient with empty balances
        toW = &Wallet{Address: req.To, Balance: make(map[string]float64), Nonce: 0, CreatedAt: time.Now(), UpdatedAt: time.Now()}
        s.wallets[req.To] = toW
        atomic.AddUint64(&s.metrics.ActiveWallets, 1)
    }

    token := strings.ToUpper(req.Token)
    if fromW.Balance[token] < req.Amount {
        return nil, fmt.Errorf("insufficient balance")
    }

    // Update balances and nonces
    fromW.Balance[token] -= req.Amount
    toW.Balance[token] += req.Amount
    fromW.Nonce++
    now := time.Now()
    fromW.UpdatedAt = now
    toW.UpdatedAt = now

    // Create transaction record
    tx := &RelayedTx{
        TxHash:    generateTxHash(req.From, req.To, token, req.Amount, now),
        From:      req.From,
        To:        req.To,
        Token:     token,
        Amount:    req.Amount,
        Fee:       0,
        Nonce:     fromW.Nonce,
        Status:    StatusConfirmed,
        Timestamp: now,
    }
    s.allTxs[tx.TxHash] = tx
    s.txHistory[req.From] = append(s.txHistory[req.From], tx)
    s.txHistory[req.To] = append(s.txHistory[req.To], tx)
    atomic.AddUint64(&s.metrics.TotalTransfers, 1)
    return tx, nil
}

func (s *WalletStore) Relay(req RelayTxRequest) (*RelayedTx, error) {
    // Validate basics
    if !addressRegex.MatchString(req.From) || !addressRegex.MatchString(req.To) {
        return nil, fmt.Errorf("invalid address")
    }
    if !s.isSupportedToken(req.Token) {
        return nil, fmt.Errorf("unsupported token")
    }
    if req.Amount <= 0 {
        return nil, fmt.Errorf("amount must be positive")
    }
    if req.Fee < 0 {
        return nil, fmt.Errorf("fee cannot be negative")
    }
    // Signature verification placeholder – in real world you'd verify ECDSA etc.
    if strings.TrimSpace(req.Signature) == "" {
        return nil, fmt.Errorf("missing signature")
    }

    s.mu.Lock()
    defer s.mu.Unlock()

    // Ensure sender exists
    fromW, ok := s.wallets[req.From]
    if !ok {
        return nil, fmt.Errorf("sender wallet not found")
    }
    // Ensure enough balance for amount+fee
    token := strings.ToUpper(req.Token)
    total := req.Amount + req.Fee
    if fromW.Balance[token] < total {
        return nil, fmt.Errorf("insufficient balance for amount+fee")
    }

    // Create pending transaction and push to mempool
    now := time.Now()
    tx := &RelayedTx{
        TxHash:    generateTxHash(req.From, req.To, token, req.Amount, now),
        From:      req.From,
        To:        req.To,
        Token:     token,
        Amount:    req.Amount,
        Fee:       req.Fee,
        Nonce:     req.Nonce,
        Signature: req.Signature,
        Status:    StatusPending,
        Timestamp: now,
    }
    s.mempool = append(s.mempool, tx)
    s.allTxs[tx.TxHash] = tx
    atomic.AddUint64(&s.metrics.TotalRelayed, 1)
    atomic.StoreUint64(&s.metrics.MempoolSize, uint64(len(s.mempool)))
    return tx, nil
}

func generateTxHash(from, to, token string, amount float64, t time.Time) string {
    data := fmt.Sprintf("%s|%s|%s|%f|%d", from, to, token, amount, t.UnixNano())
    h := sha256.Sum256([]byte(data))
    return hex.EncodeToString(h[:])
}

// ------------------------------------------------------------
// Mempool & Block Processing
// ------------------------------------------------------------

func (s *WalletStore) processMempool() {
    ticker := time.NewTicker(5 * time.Second)
    defer ticker.Stop()
    for range ticker.C {
        s.mu.Lock()
        if len(s.mempool) == 0 {
            s.mu.Unlock()
            continue
        }
        // Create new block
        blockNum := s.currentBlock + 1
        blockTxs := s.mempool
        s.mempool = make([]*RelayedTx, 0)
        // Update transaction statuses and apply balances
        for _, tx := range blockTxs {
            // Simple balance update (fee goes to relayer wallet)
            fromW := s.wallets[tx.From]
            toW := s.wallets[tx.To]
            // Ensure recipient exists
            if toW == nil {
                toW = &Wallet{Address: tx.To, Balance: make(map[string]float64), Nonce: 0, CreatedAt: time.Now(), UpdatedAt: time.Now()}
                s.wallets[tx.To] = toW
                atomic.AddUint64(&s.metrics.ActiveWallets, 1)
            }
            // Deduct amount+fee from sender
            fromW.Balance[tx.Token] -= (tx.Amount + tx.Fee)
            // Credit amount to receiver
            toW.Balance[tx.Token] += tx.Amount
            // Credit fee to relayer (dead address)
            relayer := s.wallets["0x000000000000000000000000000000000000dead"]
            if relayer != nil {
                relayer.Balance[tx.Token] += tx.Fee
            }
            // Update nonces and timestamps
            fromW.Nonce = tx.Nonce + 1
            now := time.Now()
            fromW.UpdatedAt = now
            toW.UpdatedAt = now
            tx.Status = StatusConfirmed
            tx.BlockNum = blockNum
            tx.Timestamp = now
        }
        // Compute block hash (simple concatenation of tx hashes)
        var sb strings.Builder
        for _, tx := range blockTxs {
            sb.WriteString(tx.TxHash)
        }
        blockHash := hex.EncodeToString(sha256.New().Sum([]byte(sb.String())))
        block := &BlockInfo{BlockNumber: blockNum, BlockHash: blockHash, TxCount: len(blockTxs), Timestamp: time.Now(), Txs: blockTxs}
        s.blocks = append(s.blocks, block)
        s.currentBlock = blockNum
        atomic.StoreUint64(&s.metrics.MempoolSize, 0)
        s.mu.Unlock()
        // Broadcast block to WS clients
        s.broadcastWS("new_block", block)
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

func (s *WalletStore) wsHandler(w http.ResponseWriter, r *http.Request) {
    conn, err := upgrader.Upgrade(w, r, nil)
    if err != nil {
        log.Printf("ws upgrade error: %v", err)
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
// HTTP Handlers
// ------------------------------------------------------------

func (s *WalletStore) healthHandler(w http.ResponseWriter, r *http.Request) {
    w.WriteHeader(http.StatusOK)
    w.Write([]byte("OK"))
}

func (s *WalletStore) createWalletHandler(w http.ResponseWriter, r *http.Request) {
    var req CreateWalletRequest
    if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
        respondJSON(w, http.StatusBadRequest, APIResponse{Success: false, Error: "invalid json"})
        return
    }
    wallet, err := s.AddWallet(req.Address)
    if err != nil {
        respondJSON(w, http.StatusBadRequest, APIResponse{Success: false, Error: err.Error()})
        return
    }
    respondJSON(w, http.StatusCreated, APIResponse{Success: true, Data: wallet})
}

func (s *WalletStore) getWalletHandler(w http.ResponseWriter, r *http.Request) {
    addr := mux.Vars(r)["address"]
    wallet, err := s.GetWallet(addr)
    if err != nil {
        respondJSON(w, http.StatusNotFound, APIResponse{Success: false, Error: err.Error()})
        return
    }
    respondJSON(w, http.StatusOK, APIResponse{Success: true, Data: wallet})
}

func (s *WalletStore) transferHandler(w http.ResponseWriter, r *http.Request) {
    var req TransferRequest
    if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
        respondJSON(w, http.StatusBadRequest, APIResponse{Success: false, Error: "invalid json"})
        return
    }
    tx, err := s.Transfer(req)
    if err != nil {
        atomic.AddUint64(&s.metrics.FailedTransfers, 1)
        respondJSON(w, http.StatusBadRequest, APIResponse{Success: false, Error: err.Error()})
        return
    }
    respondJSON(w, http.StatusOK, APIResponse{Success: true, Data: tx})
}

func (s *WalletStore) relayHandler(w http.ResponseWriter, r *http.Request) {
    var req RelayTxRequest
    if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
        respondJSON(w, http.StatusBadRequest, APIResponse{Success: false, Error: "invalid json"})
        return
    }
    tx, err := s.Relay(req)
    if err != nil {
        atomic.AddUint64(&s.metrics.FailedTransfers, 1)
        respondJSON(w, http.StatusBadRequest, APIResponse{Success: false, Error: err.Error()})
        return
    }
    respondJSON(w, http.StatusAccepted, APIResponse{Success: true, Data: tx})
}

func (s *WalletStore) metricsHandler(w http.ResponseWriter, r *http.Request) {
    // Update uptime
    uptime := uint64(time.Since(s.startTime).Seconds())
    atomic.StoreUint64(&s.metrics.UptimeSeconds, uptime)
    respondJSON(w, http.StatusOK, APIResponse{Success: true, Data: s.metrics})
}

func respondJSON(w http.ResponseWriter, status int, resp APIResponse) {
    w.Header().Set("Content-Type", "application/json")
    w.WriteHeader(status)
    json.NewEncoder(w).Encode(resp)
}

// ------------------------------------------------------------
// Main Entrypoint
// ------------------------------------------------------------

func main() {
    store := NewWalletStore()
    // Start background block processor
    go store.processMempool()

    r := mux.NewRouter()
    r.Use(store.rateLimitMiddleware)
    r.HandleFunc("/health", store.healthHandler).Methods("GET")
    r.HandleFunc("/ws", store.wsHandler)
    r.HandleFunc("/wallet", store.createWalletHandler).Methods("POST")
    r.HandleFunc("/wallet/{address}", store.getWalletHandler).Methods("GET")
    r.HandleFunc("/transfer", store.transferHandler).Methods("POST")
    r.HandleFunc("/relay", store.relayHandler).Methods("POST")
    r.HandleFunc("/metrics", store.metricsHandler).Methods("GET")

    srv := &http.Server{Addr: ":8080", Handler: r}

    // Graceful shutdown handling
    idleConnsClosed := make(chan struct{})
    go func() {
        sigint := make(chan os.Signal, 1)
        signal.Notify(sigint, os.Interrupt, syscall.SIGTERM)
        <-sigint
        // Received an interrupt signal, shut down.
        ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
        defer cancel()
        if err := srv.Shutdown(ctx); err != nil {
            log.Printf("HTTP server Shutdown: %v", err)
        }
        close(idleConnsClosed)
    }()

    log.Printf("Magnum Opus relay service listening on %s", srv.Addr)
    if err := srv.ListenAndServe(); err != http.ErrServerClosed {
        log.Fatalf("ListenAndServe(): %v", err)
    }
    <-idleConnsClosed
    log.Println("Server gracefully stopped")
}

// ------------------------------------------------------------
// Rate Limiting Middleware
// ------------------------------------------------------------

func (s *WalletStore) rateLimitMiddleware(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        if !s.limiter.Allow() {
            http.Error(w, "rate limit exceeded", http.StatusTooManyRequests)
            return
        }
        atomic.AddUint64(&s.metrics.TotalRequests, 1)
        next.ServeHTTP(w, r)
    })
}
