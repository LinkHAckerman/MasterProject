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
        limiter:      rate.NewLimiter(rate.Every(100*time.Millisecond), 20), // 10 req/s burst 20
    }
}

func (s *WalletStore) writeJSON(w http.ResponseWriter, status int, resp APIResponse) {
    w.Header().Set("Content-Type", "application/json")
    w.WriteHeader(status)
    json.NewEncoder(w).Encode(resp)
}

func (s *WalletStore) rateLimit(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        if !s.limiter.Allow() {
            s.writeJSON(w, http.StatusTooManyRequests, APIResponse{Success: false, Error: "rate limit exceeded"})
            return
        }
        next.ServeHTTP(w, r)
    })
}

func (s *WalletStore) validateToken(token string) bool {
    for _, t := range SupportedTokens {
        if t == token {
            return true
        }
    }
    return false
}

func (s *WalletStore) generateTxHash(tx *RelayedTx) string {
    data := fmt.Sprintf("%s:%s:%s:%f:%d", tx.From, tx.To, tx.Token, tx.Amount, time.Now().UnixNano())
    sum := sha256.Sum256([]byte(data))
    return hex.EncodeToString(sum[:])
}

func (s *WalletStore) generateBlockHash(blockNum uint64, prevHash string) string {
    data := fmt.Sprintf("%d:%s:%d", blockNum, prevHash, time.Now().UnixNano())
    sum := sha256.Sum256([]byte(data))
    return hex.EncodeToString(sum[:])
}

// ------------------------------------------------------------
// Wallet Operations
// ------------------------------------------------------------

func (s *WalletStore) CreateWallet(address string) error {
    if !addressRegex.MatchString(address) {
        return fmt.Errorf("invalid address format")
    }
    s.mu.Lock()
    defer s.mu.Unlock()
    if _, exists := s.wallets[address]; exists {
        return fmt.Errorf("wallet already exists")
    }
    bal := make(map[string]float64)
    for _, t := range SupportedTokens {
        bal[t] = 0.0
    }
    now := time.Now()
    s.wallets[address] = &Wallet{Address: address, Balance: bal, Nonce: 0, CreatedAt: now, UpdatedAt: now}
    atomic.AddUint64(&s.metrics.ActiveWallets, 1)
    return nil
}

func (s *WalletStore) getWallet(address string) (*Wallet, bool) {
    s.mu.RLock()
    defer s.mu.RUnlock()
    w, ok := s.wallets[address]
    return w, ok
}

// ------------------------------------------------------------
// Transaction Processing
// ------------------------------------------------------------

func (s *WalletStore) ProcessTransfer(req TransferRequest) (*RelayedTx, error) {
    if !addressRegex.MatchString(req.From) || !addressRegex.MatchString(req.To) {
        return nil, fmt.Errorf("invalid address")
    }
    if !s.validateToken(req.Token) {
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
        return nil, fmt.Errorf("receiver wallet not found")
    }
    if fromW.Balance[req.Token] < req.Amount {
        return nil, fmt.Errorf("insufficient balance")
    }

    // Update balances
    fromW.Balance[req.Token] -= req.Amount
    toW.Balance[req.Token] += req.Amount
    fromW.Nonce++
    now := time.Now()
    fromW.UpdatedAt = now
    toW.UpdatedAt = now

    tx := &RelayedTx{
        From:      req.From,
        To:        req.To,
        Token:     req.Token,
        Amount:    req.Amount,
        Fee:       0,
        Nonce:     fromW.Nonce,
        Status:    StatusConfirmed,
        Timestamp: now,
    }
    tx.TxHash = s.generateTxHash(tx)
    s.allTxs[tx.TxHash] = tx
    s.txHistory[req.From] = append(s.txHistory[req.From], tx)
    s.txHistory[req.To] = append(s.txHistory[req.To], tx)
    atomic.AddUint64(&s.metrics.TotalTransfers, 1)
    s.broadcast(WebSocketMessage{Type: "transfer", Payload: tx, Timestamp: now})
    return tx, nil
}

func (s *WalletStore) ProcessRelay(req RelayTxRequest) (*RelayedTx, error) {
    if !addressRegex.MatchString(req.From) || !addressRegex.MatchString(req.To) {
        return nil, fmt.Errorf("invalid address")
    }
    if !s.validateToken(req.Token) {
        return nil, fmt.Errorf("unsupported token")
    }
    if req.Amount <= 0 {
        return nil, fmt.Errorf("amount must be positive")
    }
    // Basic signature placeholder validation (in real world would verify)
    if strings.TrimSpace(req.Signature) == "" {
        return nil, fmt.Errorf("missing signature")
    }

    s.mu.Lock()
    defer s.mu.Unlock()

    // Ensure sender exists
    sender, ok := s.wallets[req.From]
    if !ok {
        return nil, fmt.Errorf("sender wallet not found")
    }
    // Nonce check
    if req.Nonce != sender.Nonce+1 {
        return nil, fmt.Errorf("invalid nonce, expected %d", sender.Nonce+1)
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
    s.broadcast(WebSocketMessage{Type: "relay_pending", Payload: tx, Timestamp: time.Now()})
    return tx, nil
}

// ------------------------------------------------------------
// Mempool & Block Mining
// ------------------------------------------------------------

func (s *WalletStore) mineBlock() {
    s.mu.Lock()
    if len(s.mempool) == 0 {
        s.mu.Unlock()
        return
    }
    // Take snapshot of current mempool
    txs := s.mempool
    s.mempool = make([]*RelayedTx, 0)
    atomic.StoreUint64(&s.metrics.MempoolSize, 0)
    s.currentBlock++
    blockNum := s.currentBlock
    prevHash := ""
    if blockNum > 1 && len(s.blocks) > 0 {
        prevHash = s.blocks[len(s.blocks)-1].BlockHash
    }
    blockHash := s.generateBlockHash(blockNum, prevHash)
    now := time.Now()
    block := &BlockInfo{BlockNumber: blockNum, BlockHash: blockHash, TxCount: len(txs), Timestamp: now, Txs: txs}
    // Update transaction statuses
    for _, tx := range txs {
        tx.Status = StatusRelayed
        tx.BlockNum = blockNum
        // Apply balances for relayed txs (simple model: deduct fee from sender, credit amount to receiver)
        sender, sOk := s.wallets[tx.From]
        receiver, rOk := s.wallets[tx.To]
        if sOk && rOk {
            totalDeduct := tx.Amount + tx.Fee
            if sender.Balance[tx.Token] >= totalDeduct {
                sender.Balance[tx.Token] -= totalDeduct
                receiver.Balance[tx.Token] += tx.Amount
                sender.Nonce = tx.Nonce
                sender.UpdatedAt = now
                receiver.UpdatedAt = now
            } else {
                tx.Status = StatusFailed
                tx.ErrorMsg = "insufficient balance for fee"
                atomic.AddUint64(&s.metrics.FailedTransfers, 1)
            }
        } else {
            tx.Status = StatusFailed
            tx.ErrorMsg = "wallet not found"
            atomic.AddUint64(&s.metrics.FailedTransfers, 1)
        }
        s.allTxs[tx.TxHash] = tx
        s.txHistory[tx.From] = append(s.txHistory[tx.From], tx)
        s.txHistory[tx.To] = append(s.txHistory[tx.To], tx)
    }
    s.blocks = append(s.blocks, block)
    atomic.AddUint64(&s.metrics.TotalRelayed, uint64(len(txs)))
    s.mu.Unlock()
    s.broadcast(WebSocketMessage{Type: "new_block", Payload: block, Timestamp: now})
}

func (s *WalletStore) startMiner(ctx context.Context, interval time.Duration) {
    ticker := time.NewTicker(interval)
    defer ticker.Stop()
    for {
        select {
        case <-ctx.Done():
            return
        case <-ticker.C:
            s.mineBlock()
        }
    }
}

// ------------------------------------------------------------
// WebSocket Broadcasting
// ------------------------------------------------------------

func (s *WalletStore) broadcast(msg WebSocketMessage) {
    s.wsMu.Lock()
    defer s.wsMu.Unlock()
    for conn := range s.wsClients {
        if err := conn.WriteJSON(msg); err != nil {
            conn.Close()
            delete(s.wsClients, conn)
        }
    }
}

func (s *WalletStore) handleWs(w http.ResponseWriter, r *http.Request) {
    conn, err := upgrader.Upgrade(w, r, nil)
    if err != nil {
        log.Printf("WebSocket upgrade error: %v", err)
        return
    }
    s.wsMu.Lock()
    s.wsClients[conn] = true
    s.wsMu.Unlock()
    // Simple read loop to keep connection alive; we ignore inbound messages.
    for {
        if _, _, err := conn.NextReader(); err != nil {
            break
        }
    }
    s.wsMu.Lock()
    delete(s.wsClients, conn)
    s.wsMu.Unlock()
    conn.Close()
}

// ------------------------------------------------------------
// HTTP Handlers
// ------------------------------------------------------------

func (s *WalletStore) handleCreateWallet(w http.ResponseWriter, r *http.Request) {
    var req CreateWalletRequest
    if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
        s.writeJSON(w, http.StatusBadRequest, APIResponse{Success: false, Error: "invalid json"})
        return
    }
    if err := s.CreateWallet(req.Address); err != nil {
        s.writeJSON(w, http.StatusBadRequest, APIResponse{Success: false, Error: err.Error()})
        return
    }
    s.writeJSON(w, http.StatusCreated, APIResponse{Success: true, Data: map[string]string{"address": req.Address}})
}

func (s *WalletStore) handleTransfer(w http.ResponseWriter, r *http.Request) {
    var req TransferRequest
    if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
        s.writeJSON(w, http.StatusBadRequest, APIResponse{Success: false, Error: "invalid json"})
        return
    }
    tx, err := s.ProcessTransfer(req)
    if err != nil {
        s.writeJSON(w, http.StatusBadRequest, APIResponse{Success: false, Error: err.Error()})
        return
    }
    s.writeJSON(w, http.StatusOK, APIResponse{Success: true, Data: tx})
}

func (s *WalletStore) handleRelay(w http.ResponseWriter, r *http.Request) {
    var req RelayTxRequest
    if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
        s.writeJSON(w, http.StatusBadRequest, APIResponse{Success: false, Error: "invalid json"})
        return
    }
    tx, err := s.ProcessRelay(req)
    if err != nil {
        s.writeJSON(w, http.StatusBadRequest, APIResponse{Success: false, Error: err.Error()})
        return
    }
    s.writeJSON(w, http.StatusAccepted, APIResponse{Success: true, Data: tx})
}

func (s *WalletStore) handleMetrics(w http.ResponseWriter, r *http.Request) {
    // Update uptime
    uptime := uint64(time.Since(s.startTime).Seconds())
    atomic.StoreUint64(&s.metrics.UptimeSeconds, uptime)
    s.writeJSON(w, http.StatusOK, APIResponse{Success: true, Data: s.metrics})
}

// ------------------------------------------------------------
// Main Entrypoint
// ------------------------------------------------------------

func main() {
    store := NewWalletStore()
    ctx, cancel := context.WithCancel(context.Background())
    defer cancel()

    // Start background miner (e.g., every 5 seconds)
    go store.startMiner(ctx, 5*time.Second)

    r := mux.NewRouter()
    // Apply rate limiting middleware globally
    r.Use(store.rateLimit)

    r.HandleFunc("/wallet", store.handleCreateWallet).Methods("POST")
    r.HandleFunc("/transfer", store.handleTransfer).Methods("POST")
    r.HandleFunc("/relay", store.handleRelay).Methods("POST")
    r.HandleFunc("/ws", store.handleWs)
    r.HandleFunc("/metrics", store.handleMetrics).Methods("GET")

    srv := &http.Server{Addr: ":8080", Handler: r}

    // Graceful shutdown handling
    go func() {
        sigCh := make(chan os.Signal, 1)
        signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)
        <-sigCh
        log.Println("Shutting down server...")
        ctxShut, cancelShut := context.WithTimeout(context.Background(), 10*time.Second)
        defer cancelShut()
        if err := srv.Shutdown(ctxShut); err != nil {
            log.Fatalf("Server forced to shutdown: %v", err)
        }
        cancel()
    }()

    log.Println("Server listening on :8080")
    if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
        log.Fatalf("ListenAndServe error: %v", err)
    }
    log.Println("Server stopped")
}
