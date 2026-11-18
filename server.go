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
	CheckOrigin:     func(r *http.Request) bool { return true },
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
				"OPUS": 10000.0 * float64(i+1),
				"ETH":  50.0 * float64(i+1),
				"BTC":  2.5 * float64(i+1),
				"SOL":  250.0 * float64(i+1),
				"USDC": 50000.0 * float64(i+1),
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
		Address: norm,
		Balance: map[string]float64{
			"OPUS": 100.0,
			"ETH":  1.0,
			"BTC":  0.0,
			"SOL":  0.0,
			"USDC": 500.0,
		},
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
	w, exists := s.wallets[norm]
	return w, exists
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

	sender, exists := s.wallets[from]
	if !exists {
		atomic.AddUint64(&s.metrics.FailedTransfers, 1)
		return nil, fmt.Errorf("sender wallet does not exist")
	}

	if sender.Balance[token] < req.Amount {
		atomic.AddUint64(&s.metrics.FailedTransfers, 1)
		return nil, fmt.Errorf("insufficient balance for %s", token)
	}

	recipient, exists := s.wallets[to]
	if !exists {
		recipient = &Wallet{
			Address:   to,
			Balance:   map[string]float64{"OPUS": 0, "ETH": 0, "BTC": 0, "SOL": 0, "USDC": 0},
			Nonce:     0,
			CreatedAt: time.Now(),
			UpdatedAt: time.Now(),
		}
		s.wallets[to] = recipient
		s.txHistory[to] = make([]*RelayedTx, 0)
		s.metrics.ActiveWallets = uint64(len(s.wallets))
	}

	sender.Balance[token] -= req.Amount
	sender.Nonce++
	sender.UpdatedAt = time.Now()

	recipient.Balance[token] += req.Amount
	recipient.UpdatedAt = time.Now()

	txRaw := fmt.Sprintf("%s:%s:%s:%f:%d:%d", from, to, token, req.Amount, sender.Nonce, time.Now().UnixNano())
	txHash := computeHash(txRaw)

	tx := &RelayedTx{
		TxHash:    txHash,
		From:      from,
		To:        to,
		Token:     token,
		Amount:    req.Amount,
		Fee:       0.001,
		Nonce:     sender.Nonce,
		Status:    StatusPending,
		Timestamp: time.Now(),
	}

	s.mempool = append(s.mempool, tx)
	s.allTxs[txHash] = tx
	s.txHistory[from] = append(s.txHistory[from], tx)
	s.txHistory[to] = append(s.txHistory[to], tx)

	atomic.AddUint64(&s.metrics.TotalTransfers, 1)
	s.metrics.MempoolSize = uint64(len(s.mempool))

	go s.BroadcastWS("NEW_TRANSACTION", tx)

	return tx, nil
}

func (s *WalletStore) RelayTransaction(req RelayTxRequest) (*RelayedTx, error) {
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
		return nil, fmt.Errorf("amount must be positive")
	}
	if req.Signature == "" {
		atomic.AddUint64(&s.metrics.FailedTransfers, 1)
		return nil, fmt.Errorf("missing relay signature")
	}

	s.mu.Lock()
	defer s.mu.Unlock()

	sender, exists := s.wallets[from]
	if !exists {
		atomic.AddUint64(&s.metrics.FailedTransfers, 1)
		return nil, fmt.Errorf("sender wallet not found")
	}

	totalDeduction := req.Amount + req.Fee
	if sender.Balance[token] < totalDeduction {
		atomic.AddUint64(&s.metrics.FailedTransfers, 1)
		return nil, fmt.Errorf("insufficient balance including fee")
	}

	recipient, exists := s.wallets[to]
	if !exists {
		recipient = &Wallet{
			Address:   to,
			Balance:   map[string]float64{"OPUS": 0, "ETH": 0, "BTC": 0, "SOL": 0, "USDC": 0},
			Nonce:     0,
			CreatedAt: time.Now(),
			UpdatedAt: time.Now(),
		}
		s.wallets[to] = recipient
		s.txHistory[to] = make([]*RelayedTx, 0)
		s.metrics.ActiveWallets = uint64(len(s.wallets))
	}

	sender.Balance[token] -= totalDeduction
	sender.Nonce++
	sender.UpdatedAt = time.Now()

	recipient.Balance[token] += req.Amount
	recipient.UpdatedAt = time.Now()

	txRaw := fmt.Sprintf("%s:%s:%s:%f:%f:%d:%s", from, to, token, req.Amount, req.Fee, req.Nonce, req.Signature)
	txHash := computeHash(txRaw)

	tx := &RelayedTx{
		TxHash:    txHash,
		From:      from,
		To:        to,
		Token:     token,
		Amount:    req.Amount,
		Fee:       req.Fee,
		Nonce:     req.Nonce,
		Signature: req.Signature,
		Status:    StatusRelayed,
		Timestamp: time.Now(),
	}

	s.mempool = append(s.mempool, tx)
	s.allTxs[txHash] = tx
	s.txHistory[from] = append(s.txHistory[from], tx)
	s.txHistory[to] = append(s.txHistory[to], tx)

	atomic.AddUint64(&s.metrics.TotalRelayed, 1)
	s.metrics.MempoolSize = uint64(len(s.mempool))

	go s.BroadcastWS("RELAYED_TRANSACTION", tx)

	return tx, nil
}

func (s *WalletStore) GetTxHistory(addr string) []*RelayedTx {
	norm := strings.ToLower(addr)
	s.mu.RLock()
	defer s.mu.RUnlock()
	if history, exists := s.txHistory[norm]; exists {
		result := make([]*RelayedTx, len(history))
		copy(result, history)
		return result
	}
	return []*RelayedTx{}
}

func (s *WalletStore) GetTxByHash(hash string) (*RelayedTx, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	tx, exists := s.allTxs[hash]
	return tx, exists
}

func (s *WalletStore) GetMempool() []*RelayedTx {
	s.mu.RLock()
	defer s.mu.RUnlock()
	result := make([]*RelayedTx, len(s.mempool))
	copy(result, s.mempool)
	return result
}

func (s *WalletStore) GetBlocks() []*BlockInfo {
	s.mu.RLock()
	defer s.mu.RUnlock()
	result := make([]*BlockInfo, len(s.blocks))
	copy(result, s.blocks)
	return result
}

func (s *WalletStore) GetMetrics() Metrics {
	s.mu.RLock()
	defer s.mu.RUnlock()

	m := s.metrics
	m.UptimeSeconds = uint64(time.Since(s.startTime).Seconds())
	m.MempoolSize = uint64(len(s.mempool))
	m.ActiveWallets = uint64(len(s.wallets))
	return m
}

// ------------------------------------------------------------
// WebSocket Management
// ------------------------------------------------------------

func (s *WalletStore) RegisterWSConn(conn *websocket.Conn) {
	s.wsMu.Lock()
	s.wsClients[conn] = true
	s.wsMu.Unlock()
}

func (s *WalletStore) UnregisterWSConn(conn *websocket.Conn) {
	s.wsMu.Lock()
	if _, exists := s.wsClients[conn]; exists {
		delete(s.wsClients, conn)
		conn.Close()
	}
	s.wsMu.Unlock()
}

func (s *WalletStore) BroadcastWS(msgType string, payload interface{}) {
	msg := WebSocketMessage{
		Type:      msgType,
		Payload:   payload,
		Timestamp: time.Now(),
	}
	data, err := json.Marshal(msg)
	if err != nil {
		return
	}

	s.wsMu.Lock()
	defer s.wsMu.Unlock()

	for conn := range s.wsClients {
		if err := conn.WriteMessage(websocket.TextMessage, data); err != nil {
			conn.Close()
			delete(s.wsClients, conn)
		}
	}
}

// ------------------------------------------------------------
// Background Block Miner Worker
// ------------------------------------------------------------

func (s *WalletStore) StartBlockMiner(ctx context.Context, interval time.Duration) {
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

func (s *WalletStore) mineBlock() {
	s.mu.Lock()
	if len(s.mempool) == 0 {
		s.mu.Unlock()
		return
	}

	txsToMine := s.mempool
	s.mempool = make([]*RelayedTx, 0)
	s.currentBlock++
	blockNum := s.currentBlock
	s.metrics.MempoolSize = 0
	s.mu.Unlock()

	blockHeader := fmt.Sprintf("%d:%d:%d", blockNum, time.Now().UnixNano(), len(txsToMine))
	blockHash := computeHash(blockHeader)

	for _, tx := range txsToMine {
		tx.Status = StatusConfirmed
		tx.BlockNum = blockNum
	}

	block := &BlockInfo{
		BlockNumber: blockNum,
		BlockHash:   blockHash,
		TxCount:     len(txsToMine),
		Timestamp:   time.Now(),
		Txs:         txsToMine,
	}

	s.mu.Lock()
	s.blocks = append(s.blocks, block)
	if len(s.blocks) > 100 {
		s.blocks = s.blocks[len(s.blocks)-100:]
	}
	s.mu.Unlock()

	log.Printf("[MINER] Mined Block #%d (Hash: %s) with %d transactions", blockNum, blockHash[:10]+"...", len(txsToMine))
	go s.BroadcastWS("NEW_BLOCK", block)
}

// ------------------------------------------------------------
// HTTP Middleware & Handlers
// ------------------------------------------------------------

func sendJSON(w http.ResponseWriter, status int, response APIResponse) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(response)
}

func (s *WalletStore) Middleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		atomic.AddUint64(&s.metrics.TotalRequests, 1)

		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")

		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusOK)
			return
		}

		if !s.limiter.Allow() {
			sendJSON(w, http.StatusTooManyRequests, APIResponse{
				Success: false,
				Error:   "Rate limit exceeded",
			})
			return
		}

		next.ServeHTTP(w, r)
	})
}

func (s *WalletStore) HandleHealth(w http.ResponseWriter, r *http.Request) {
	sendJSON(w, http.StatusOK, APIResponse{
		Success: true,
		Data: map[string]interface{}{
			"status":  "healthy",
			"service": "Magnum Opus Relay & Wallet Microservice",
			"time":    time.Now(),
		},
	})
}

func (s *WalletStore) HandleMetrics(w http.ResponseWriter, r *http.Request) {
	metrics := s.GetMetrics()
	sendJSON(w, http.StatusOK, APIResponse{
		Success: true,
		Data:    metrics,
	})
}

func (s *WalletStore) HandleCreateWallet(w http.ResponseWriter, r *http.Request) {
	var req CreateWalletRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		sendJSON(w, http.StatusBadRequest, APIResponse{Success: false, Error: "Invalid JSON payload"})
		return
	}

	wallet, err := s.GetOrCreateWallet(req.Address)
	if err != nil {
		sendJSON(w, http.StatusBadRequest, APIResponse{Success: false, Error: err.Error()})
		return
	}

	sendJSON(w, http.StatusCreated, APIResponse{Success: true, Data: wallet})
}

func (s *WalletStore) HandleGetWallet(w http.ResponseWriter, r *http.Request) {
	vars := mux.Vars(r)
	address := vars["address"]

	wallet, exists := s.GetWallet(address)
	if !exists {
		sendJSON(w, http.StatusNotFound, APIResponse{Success: false, Error: "Wallet not found"})
		return
	}

	sendJSON(w, http.StatusOK, APIResponse{Success: true, Data: wallet})
}

func (s *WalletStore) HandleTransfer(w http.ResponseWriter, r *http.Request) {
	var req TransferRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		sendJSON(w, http.StatusBadRequest, APIResponse{Success: false, Error: "Invalid JSON payload"})
		return
	}

	tx, err := s.Transfer(req)
	if err != nil {
		sendJSON(w, http.StatusBadRequest, APIResponse{Success: false, Error: err.Error()})
		return
	}

	sendJSON(w, http.StatusAccepted, APIResponse{Success: true, Data: tx})
}

func (s *WalletStore) HandleRelay(w http.ResponseWriter, r *http.Request) {
	var req RelayTxRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		sendJSON(w, http.StatusBadRequest, APIResponse{Success: false, Error: "Invalid JSON payload"})
		return
	}

	tx, err := s.RelayTransaction(req)
	if err != nil {
		sendJSON(w, http.StatusBadRequest, APIResponse{Success: false, Error: err.Error()})
		return
	}

	sendJSON(w, http.StatusAccepted, APIResponse{Success: true, Data: tx})
}

func (s *WalletStore) HandleGetTxByHash(w http.ResponseWriter, r *http.Request) {
	vars := mux.Vars(r)
	hash := vars["hash"]

	tx, exists := s.GetTxByHash(hash)
	if !exists {
		sendJSON(w, http.StatusNotFound, APIResponse{Success: false, Error: "Transaction hash not found"})
		return
	}

	sendJSON(w, http.StatusOK, APIResponse{Success: true, Data: tx})
}

func (s *WalletStore) HandleGetTxHistory(w http.ResponseWriter, r *http.Request) {
	vars := mux.Vars(r)
	address := vars["address"]

	history := s.GetTxHistory(address)
	sendJSON(w, http.StatusOK, APIResponse{Success: true, Data: history})
}

func (s *WalletStore) HandleGetMempool(w http.ResponseWriter, r *http.Request) {
	mempool := s.GetMempool()
	sendJSON(w, http.StatusOK, APIResponse{Success: true, Data: mempool})
}

func (s *WalletStore) HandleGetBlocks(w http.ResponseWriter, r *http.Request) {
	blocks := s.GetBlocks()
	sendJSON(w, http.StatusOK, APIResponse{Success: true, Data: blocks})
}

func (s *WalletStore) HandleWebSocket(w http.ResponseWriter, r *http.Request) {
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("WebSocket upgrade failed: %v", err)
		return
	}

	s.RegisterWSConn(conn)

	// Keep alive & read pump
	go func() {
		defer s.UnregisterWSConn(conn)
		for {
			_, _, err := conn.ReadMessage()
			if err != nil {
				break
			}
		}
	}()
}

// ------------------------------------------------------------
// Main Application Entry Point
// ------------------------------------------------------------

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	store := NewWalletStore()

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// Start background miner (mines mempool into blocks every 5 seconds)
	go store.StartBlockMiner(ctx, 5*time.Second)

	router := mux.NewRouter()
	router.Use(store.Middleware)

	// Endpoint Registration
	router.HandleFunc("/health", store.HandleHealth).Methods("GET", "OPTIONS")
	router.HandleFunc("/api/v1/metrics", store.HandleMetrics).Methods("GET", "OPTIONS")
	router.HandleFunc("/api/v1/wallets", store.HandleCreateWallet).Methods("POST", "OPTIONS")
	router.HandleFunc("/api/v1/wallets/{address}", store.HandleGetWallet).Methods("GET", "OPTIONS")
	router.HandleFunc("/api/v1/transfer", store.HandleTransfer).Methods("POST", "OPTIONS")
	router.HandleFunc("/api/v1/relay", store.HandleRelay).Methods("POST", "OPTIONS")
	router.HandleFunc("/api/v1/transactions/{hash}", store.HandleGetTxByHash).Methods("GET", "OPTIONS")
	router.HandleFunc("/api/v1/wallets/{address}/history", store.HandleGetTxHistory).Methods("GET", "OPTIONS")
	router.HandleFunc("/api/v1/mempool", store.HandleGetMempool).Methods("GET", "OPTIONS")
	router.HandleFunc("/api/v1/blocks", store.HandleGetBlocks).Methods("GET", "OPTIONS")
	router.HandleFunc("/ws", store.HandleWebSocket)

	srv := &http.Server{
		Addr:         ":" + port,
		Handler:      router,
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 15 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	log.Printf("[SERVER] Starting Magnum Opus Relay Microservice on port %s...", port)

	go func() {
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("Server error: %v", err)
		}
	}()

	// Graceful Shutdown Handler
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, os.Interrupt, syscall.SIGTERM)
	<-stop

	log.Println("[SERVER] Shutting down gracefully...")
	shutdownCtx, shutdownCancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer shutdownCancel()

	if err := srv.Shutdown(shutdownCtx); err != nil {
		log.Fatalf("Server forced to shutdown: %v", err)
	}

	log.Println("[SERVER] Microservice stopped successfully.")
}
