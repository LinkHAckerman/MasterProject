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

// RelayedTx models an on-chain or metatransaction handled by the relay microservice.
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

// Metrics tracks realtime telemetry of the microservice.
type Metrics struct {
    TotalRequests   uint64 `json:"total_requests"`
    TotalTransfers  uint64 `json:"total_transfers"`
    TotalRelayed    uint64 `json:"total_relayed"`
    FailedTransfers uint64 `json:"failed_transfers"`
    ActiveWallets   uint64 `json:"active_wallets"`
    MempoolSize     uint64 `json:"mempool_size"`
    UptimeSeconds   uint64 `json:"uptime_seconds"`
}

// WebSocketMessage represents a realtime update pushed to clients.
type WebSocketMessage struct {
    Type      string      `json:"type"`
    Payload   interface{} `json:"payload"`
    Timestamp time.Time   `json:"timestamp"`
}

// WalletStore handles concurrent wallet storage, transaction indexing, and mempool relaying.
type WalletStore struct {
    mu           sync.RWMutex
    wallets      map[string]*Wallet
    txHistory    map[string][]*RelayedTx
    allTxs       map[string]*RelayedTx
    mempool      []*RelayedTx
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
        startTime:    time.Now(),
        currentBlock: 18450200,
        wsClients:    make(map[*websocket.Conn]bool),
        limiter:      rate.NewLimiter(rate.Limit(100), 200), // 100 req/s, burst 200
    }

    // Seed the relayer gasstation wallet
    relayer := &Wallet{
        Address: "0x000000000000000000000000000000000000dEaD",
        Balance: map[string]float64{
            "OPUS": 1000000.0,
            "ETH":  5000.0,
            "USDC": 5000000.0,
        },
        Nonce:     0,
        CreatedAt: time.Now(),
        UpdatedAt: time.Now(),
    }
    store.wallets[relayer.Address] = relayer
    atomic.StoreUint64(&store.metrics.ActiveWallets, 1)

    go store.blockProducer()
    go store.mempoolProcessor()
    go store.metricsUpdater()

    return store
}

func computeTxHash(from, to, token string, amount float64, nonce uint64, ts time.Time) string {
    data := fmt.Sprintf("%s:%s:%s:%.8f:%d:%d", from, to, token, amount, nonce, ts.UnixNano())
    hash := sha256.Sum256([]byte(data))
    return "0x" + hex.EncodeToString(hash[:])
}

func isValidAddress(addr string) bool {
    // Simple Ethereumstyle address validation (0x + 40 hex chars)
    re := regexp.MustCompile(`^0x[0-9a-fA-F]{40}$`)
    return re.MatchString(addr)
}

func isSupportedToken(tok string) bool {
    for _, t := range SupportedTokens {
        if strings.EqualFold(t, tok) {
            return true
        }
    }
    return false
}

// ------------------------------------------------------------
// WalletStore Methods
// ------------------------------------------------------------

// AddWallet creates a new wallet with the given address and initial balances.
func (ws *WalletStore) AddWallet(addr string, initialBalances map[string]float64) error {
    ws.mu.Lock()
    defer ws.mu.Unlock()

    if !isValidAddress(addr) {
        return fmt.Errorf("invalid wallet address: %s", addr)
    }

    if _, exists := ws.wallets[addr]; exists {
        return fmt.Errorf("wallet already exists: %s", addr)
    }

    balances := make(map[string]float64)
    for token, amount := range initialBalances {
        if !isSupportedToken(token) {
            return fmt.Errorf("unsupported token: %s", token)
        }
        balances[token] = amount
    }

    ws.wallets[addr] = &Wallet{
        Address:   addr,
        Balance:   balances,
        Nonce:     0,
        CreatedAt: time.Now(),
        UpdatedAt: time.Now(),
    }

    atomic.AddUint64(&ws.metrics.ActiveWallets, 1)
    return nil
}

// GetWallet retrieves a wallet by its address.
func (ws *WalletStore) GetWallet(addr string) (*Wallet, error) {
    ws.mu.RLock()
    defer ws.mu.RUnlock()

    wallet, exists := ws.wallets[addr]
    if !exists {
        return nil, fmt.Errorf("wallet not found: %s", addr)
    }

    return wallet, nil
}

// GetWalletBalance retrieves the balance of a specific token for a wallet.
func (ws *WalletStore) GetWalletBalance(addr, token string) (float64, error) {
    ws.mu.RLock()
    defer ws.mu.RUnlock()

    wallet, exists := ws.wallets[addr]
    if !exists {
        return 0, fmt.Errorf("wallet not found: %s", addr)
    }

    if !isSupportedToken(token) {
        return 0, fmt.Errorf("unsupported token: %s", token)
    }

    balance, exists := wallet.Balance[token]
    if !exists {
        return 0, nil
    }

    return balance, nil
}

// TransferTokens transfers tokens from one wallet to another.
func (ws *WalletStore) TransferTokens(from, to, token string, amount float64) (*RelayedTx, error) {
    ws.mu.Lock()
    defer ws.mu.Unlock()

    if !isValidAddress(from) || !isValidAddress(to) {
        return nil, fmt.Errorf("invalid wallet address")
    }

    if !isSupportedToken(token) {
        return nil, fmt.Errorf("unsupported token: %s", token)
    }

    fromWallet, exists := ws.wallets[from]
    if !exists {
        return nil, fmt.Errorf("sender wallet not found: %s", from)
    }

    toWallet, exists := ws.wallets[to]
    if !exists {
        return nil, fmt.Errorf("recipient wallet not found: %s", to)
    }

    fromBalance, exists := fromWallet.Balance[token]
    if !exists || fromBalance < amount {
        return nil, fmt.Errorf("insufficient balance for token: %s", token)
    }

    // Calculate fee (0.1% of amount)
    fee := amount * 0.001
    if fee < 0.00000001 {
        fee = 0.00000001
    }

    // Check if relayer has enough balance to cover the fee
    relayer, exists := ws.wallets["0x000000000000000000000000000000000000dEaD"]
    if !exists {
        return nil, fmt.Errorf("relayer wallet not found")
    }

    relayerBalance, exists := relayer.Balance[token]
    if !exists || relayerBalance < fee {
        return nil, fmt.Errorf("relayer insufficient balance for fee")
    }

    // Deduct amount and fee from sender
    fromWallet.Balance[token] -= amount + fee
    fromWallet.Nonce++
    fromWallet.UpdatedAt = time.Now()

    // Add amount to recipient
    toWallet.Balance[token] += amount
    toWallet.UpdatedAt = time.Now()

    // Add fee to relayer
    relayer.Balance[token] += fee
    relayer.UpdatedAt = time.Now()

    // Create transaction
    tx := &RelayedTx{
        TxHash:    computeTxHash(from, to, token, amount, fromWallet.Nonce, time.Now()),
        From:      from,
        To:        to,
        Token:     token,
        Amount:    amount,
        Fee:       fee,
        Nonce:     fromWallet.Nonce,
        Status:    StatusPending,
        Timestamp: time.Now(),
    }

    // Add transaction to mempool
    ws.mempool = append(ws.mempool, tx)
    atomic.AddUint64(&ws.metrics.MempoolSize, 1)

    // Broadcast transaction to WebSocket clients
    ws.broadcastWebSocketMessage(&WebSocketMessage{
        Type:      "transaction",
        Payload:   tx,
        Timestamp: time.Now(),
    })

    return tx, nil
}

// GetTransaction retrieves a transaction by its hash.
func (ws *WalletStore) GetTransaction(txHash string) (*RelayedTx, error) {
    ws.mu.RLock()
    defer ws.mu.RUnlock()

    tx, exists := ws.allTxs[txHash]
    if !exists {
        return nil, fmt.Errorf("transaction not found: %s", txHash)
    }

    return tx, nil
}

// GetTransactionHistory retrieves the transaction history for a wallet.
func (ws *WalletStore) GetTransactionHistory(addr string) ([]*RelayedTx, error) {
    ws.mu.RLock()
    defer ws.mu.RUnlock()

    if !isValidAddress(addr) {
        return nil, fmt.Errorf("invalid wallet address: %s", addr)
    }

    txs, exists := ws.txHistory[addr]
    if !exists {
        return []*RelayedTx{}, nil
    }

    return txs, nil
}

// GetMetrics retrieves the current metrics.
func (ws *WalletStore) GetMetrics() Metrics {
    ws.mu.RLock()
    defer ws.mu.RUnlock()

    metrics := ws.metrics
    metrics.UptimeSeconds = uint64(time.Since(ws.startTime).Seconds())
    metrics.MempoolSize = uint64(len(ws.mempool))

    return metrics
}

// ------------------------------------------------------------
// WebSocket Methods
// ------------------------------------------------------------

// broadcastWebSocketMessage broadcasts a message to all connected WebSocket clients.
func (ws *WalletStore) broadcastWebSocketMessage(msg *WebSocketMessage) {
    ws.wsMu.Lock()
    defer ws.wsMu.Unlock()

    for client := range ws.wsClients {
        err := client.WriteJSON(msg)
        if err != nil {
            log.Printf("Error broadcasting WebSocket message: %v", err)
            client.Close()
            delete(ws.wsClients, client)
        }
    }
}

// ------------------------------------------------------------
// Background Workers
// ------------------------------------------------------------

// blockProducer simulates block production and confirms transactions.
func (ws *WalletStore) blockProducer() {
    ticker := time.NewTicker(15 * time.Second)
    defer ticker.Stop()

    for range ticker.C {
        ws.mu.Lock()
        ws.currentBlock++
        ws.mu.Unlock()

        // Broadcast block update to WebSocket clients
        ws.broadcastWebSocketMessage(&WebSocketMessage{
            Type:      "block",
            Payload:   map[string]interface{}{
                "block_number": ws.currentBlock,
            },
            Timestamp: time.Now(),
        })
    }
}

// mempoolProcessor processes transactions in the mempool.
func (ws *WalletStore) mempoolProcessor() {
    ticker := time.NewTicker(5 * time.Second)
    defer ticker.Stop()

    for range ticker.C {
        ws.mu.Lock()
        if len(ws.mempool) > 0 {
            // Process the oldest transaction in the mempool
            tx := ws.mempool[0]
            ws.mempool = ws.mempool[1:]
            atomic.AddUint64(&ws.metrics.MempoolSize, ^uint64(0))

            // Simulate transaction processing
            time.Sleep(2 * time.Second)

            // Update transaction status
            tx.Status = StatusRelayed
            tx.BlockNum = ws.currentBlock

            // Add transaction to history
            ws.txHistory[tx.From] = append(ws.txHistory[tx.From], tx)
            ws.txHistory[tx.To] = append(ws.txHistory[tx.To], tx)
            ws.allTxs[tx.TxHash] = tx

            // Broadcast transaction update to WebSocket clients
            ws.broadcastWebSocketMessage(&WebSocketMessage{
                Type:      "transaction",
                Payload:   tx,
                Timestamp: time.Now(),
            })
        }
        ws.mu.Unlock()
    }
}

// metricsUpdater updates the metrics periodically.
func (ws *WalletStore) metricsUpdater() {
    ticker := time.NewTicker(1 * time.Minute)
    defer ticker.Stop()

    for range ticker.C {
        ws.mu.Lock()
        ws.metrics.UptimeSeconds = uint64(time.Since(ws.startTime).Seconds())
        ws.metrics.MempoolSize = uint64(len(ws.mempool))
        ws.mu.Unlock()
    }
}

// ------------------------------------------------------------
// HTTP Handlers
// ------------------------------------------------------------

// handleAddWallet handles the addition of a new wallet.
func (ws *WalletStore) handleAddWallet(w http.ResponseWriter, r *http.Request) {
    if !ws.limiter.Allow() {
        http.Error(w, "Too many requests", http.StatusTooManyRequests)
        return
    }

    var req struct {
        Address        string             `json:"address"`
        InitialBalances map[string]float64 `json:"initial_balances"`
    }

    if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
        http.Error(w, err.Error(), http.StatusBadRequest)
        return
    }

    if err := ws.AddWallet(req.Address, req.InitialBalances); err != nil {
        http.Error(w, err.Error(), http.StatusBadRequest)
        return
    }

    w.WriteHeader(http.StatusCreated)
    json.NewEncoder(w).Encode(map[string]string{"status": "success"})
}

// handleGetWallet handles the retrieval of a wallet.
func (ws *WalletStore) handleGetWallet(w http.ResponseWriter, r *http.Request) {
    if !ws.limiter.Allow() {
        http.Error(w, "Too many requests", http.StatusTooManyRequests)
        return
    }

    vars := mux.Vars(r)
    addr := vars["address"]

    wallet, err := ws.GetWallet(addr)
    if err != nil {
        http.Error(w, err.Error(), http.StatusNotFound)
        return
    }

    json.NewEncoder(w).Encode(wallet)
}

// handleGetWalletBalance handles the retrieval of a wallet's balance for a specific token.
func (ws *WalletStore) handleGetWalletBalance(w http.ResponseWriter, r *http.Request) {
    if !ws.limiter.Allow() {
        http.Error(w, "Too many requests", http.StatusTooManyRequests)
        return
    }

    vars := mux.Vars(r)
    addr := vars["address"]
    token := vars["token"]

    balance, err := ws.GetWalletBalance(addr, token)
    if err != nil {
        http.Error(w, err.Error(), http.StatusBadRequest)
        return
    }

    json.NewEncoder(w).Encode(map[string]interface{}{
        "address": addr,
        "token":   token,
        "balance": balance,
    })
}

// handleTransferTokens handles the transfer of tokens between wallets.
func (ws *WalletStore) handleTransferTokens(w http.ResponseWriter, r *http.Request) {
    if !ws.limiter.Allow() {
        http.Error(w, "Too many requests", http.StatusTooManyRequests)
        return
    }

    var req struct {
        From   string  `json:"from"`
        To     string  `json:"to"`
        Token  string  `json:"token"`
        Amount float64 `json:"amount"`
    }

    if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
        http.Error(w, err.Error(), http.StatusBadRequest)
        return
    }

    tx, err := ws.TransferTokens(req.From, req.To, req.Token, req.Amount)
    if err != nil {
        http.Error(w, err.Error(), http.StatusBadRequest)
        return
    }

    json.NewEncoder(w).Encode(tx)
}

// handleGetTransaction handles the retrieval of a transaction.
func (ws *WalletStore) handleGetTransaction(w http.ResponseWriter, r *http.Request) {
    if !ws.limiter.Allow() {
        http.Error(w, "Too many requests", http.StatusTooManyRequests)
        return
    }

    vars := mux.Vars(r)
    txHash := vars["tx_hash"]

    tx, err := ws.GetTransaction(txHash)
    if err != nil {
        http.Error(w, err.Error(), http.StatusNotFound)
        return
    }

    json.NewEncoder(w).Encode(tx)
}

// handleGetTransactionHistory handles the retrieval of a wallet's transaction history.
func (ws *WalletStore) handleGetTransactionHistory(w http.ResponseWriter, r *http.Request) {
    if !ws.limiter.Allow() {
        http.Error(w, "Too many requests", http.StatusTooManyRequests)
        return
    }

    vars := mux.Vars(r)
    addr := vars["address"]

    txs, err := ws.GetTransactionHistory(addr)
    if err != nil {
        http.Error(w, err.Error(), http.StatusBadRequest)
        return
    }

    json.NewEncoder(w).Encode(txs)
}

// handleGetMetrics handles the retrieval of the current metrics.
func (ws *WalletStore) handleGetMetrics(w http.ResponseWriter, r *http.Request) {
    if !ws.limiter.Allow() {
        http.Error(w, "Too many requests", http.StatusTooManyRequests)
        return
    }

    metrics := ws.GetMetrics()
    json.NewEncoder(w).Encode(metrics)
}

// handleWebSocket handles WebSocket connections.
func (ws *WalletStore) handleWebSocket(w http.ResponseWriter, r *http.Request) {
    conn, err := websocket.Upgrade(w, r, nil, 1024, 1024)
    if err != nil {
        log.Printf("Error upgrading to WebSocket: %v", err)
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
            log.Printf("Error reading WebSocket message: %v", err)
            break
        }
    }
}

// ------------------------------------------------------------
// Main Function
// ------------------------------------------------------------

func main() {
    // Initialize wallet store
    store := NewWalletStore()

    // Set up router
    r := mux.NewRouter()

    // API routes
    r.HandleFunc("/api/wallets", store.handleAddWallet).Methods("POST")
    r.HandleFunc("/api/wallets/{address}", store.handleGetWallet).Methods("GET")
    r.HandleFunc("/api/wallets/{address}/balance/{token}", store.handleGetWalletBalance).Methods("GET")
    r.HandleFunc("/api/transactions", store.handleTransferTokens).Methods("POST")
    r.HandleFunc("/api/transactions/{tx_hash}", store.handleGetTransaction).Methods("GET")
    r.HandleFunc("/api/wallets/{address}/transactions", store.handleGetTransactionHistory).Methods("GET")
    r.HandleFunc("/api/metrics", store.handleGetMetrics).Methods("GET")

    // WebSocket route
    r.HandleFunc("/ws", store.handleWebSocket)

    // Start server
    srv := &http.Server{
        Addr:    ":8080",
        Handler: r,
    }

    // Graceful shutdown
    go func() {
        sigint := make(chan os.Signal, 1)
        signal.Notify(sigint, os.Interrupt, syscall.SIGTERM)
        <-sigint

        log.Println("Shutting down server...")
        if err := srv.Shutdown(context.Background()); err != nil {
            log.Printf("Error shutting down server: %v", err)
        }
    }()

    log.Println("Server started on :8080")
    if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
        log.Fatalf("Error starting server: %v", err)
    }
}
