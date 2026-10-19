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

// TransactionStatus represents the lifecycle state of a relayed transaction.
type TransactionStatus string

const (
	StatusPending   TransactionStatus = "PENDING"
	StatusRelayed   TransactionStatus = "RELAYED"
	StatusConfirmed TransactionStatus = "CONFIRMED"
	StatusFailed    TransactionStatus = "FAILED"
)

// SupportedTokens lists canonical platform assets.
var SupportedTokens = []string{"OPUS", "ETH", "BTC", "SOL", "USDC"}

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

// NewWalletStore instantiates the store with default system reserves.
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

	// Seed the relayer gas-station wallet
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

	// Start background block producer
	go store.blockProducer()
	go store.mempoolProcessor()
	go store.metricsUpdater()

	return store
}

// computeTxHash generates a deterministic SHA-256 transaction identifier.
func computeTxHash(from, to, token string, amount float64, nonce uint64, ts time.Time) string {
	data := fmt.Sprintf("%s:%s:%s:%.8f:%d:%d", from, to, token, amount, nonce, ts.UnixNano())
	hash := sha256.Sum256([]byte(data))
	return "0x" + hex.EncodeToString(hash[:])
}

func (s *WalletStore) Get(address string) (*Wallet, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	w, ok := s.wallets[address]
	if !ok {
		return nil, false
	}
	// Return deep copy of balance map to prevent data races
	balanceCopy := make(map[string]float64, len(w.Balance))
	for k, v := range w.Balance {
		balanceCopy[k] = v
	}
	return &Wallet{
		Address:   w.Address,
		Balance:   balanceCopy,
		Nonce:     w.Nonce,
		CreatedAt: w.CreatedAt,
		UpdatedAt: w.UpdatedAt,
	}, true
}

func (s *WalletStore) Create(address string) (*Wallet, error) {
	if strings.TrimSpace(address) == "" {
		return nil, fmt.Errorf("address cannot be empty")
	}
	if !isValidAddress(address) {
		return nil, fmt.Errorf("invalid address format")
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if _, exists := s.wallets[address]; exists {
		return nil, fmt.Errorf("wallet already exists")
	}
	w := &Wallet{
		Address: address,
		Balance: map[string]float64{
			"OPUS": 100.0,
			"ETH":  1.5,
			"USDC": 2500.0,
			"SOL":  10.0,
			"BTC":  0.05,
		},
		Nonce:     0,
		CreatedAt: time.Now(),
		UpdatedAt: time.Now(),
	}
	s.wallets[address] = w
	atomic.AddUint64(&s.metrics.ActiveWallets, 1)
	return w, nil
}

func (s *WalletStore) Transfer(from, to, token string, amount float64) error {
	if amount <= 0 {
		atomic.AddUint64(&s.metrics.FailedTransfers, 1)
		return fmt.Errorf("amount must be positive")
	}
	if !isValidToken(token) {
		atomic.AddUint64(&s.metrics.FailedTransfers, 1)
		return fmt.Errorf("unsupported token: %s", token)
	}

	s.mu.Lock()
	defer s.mu.Unlock()

	src, ok := s.wallets[from]
	if !ok {
		atomic.AddUint64(&s.metrics.FailedTransfers, 1)
		return fmt.Errorf("source wallet not found")
	}
	dst, ok := s.wallets[to]
	if !ok {
		atomic.AddUint64(&s.metrics.FailedTransfers, 1)
		return fmt.Errorf("destination wallet not found")
	}
	if src.Balance[token] < amount {
		atomic.AddUint64(&s.metrics.FailedTransfers, 1)
		return fmt.Errorf("insufficient balance")
	}

	// Calculate dynamic fee based on token and network congestion
	fee := calculateFee(token, amount, len(s.mempool))
	if src.Balance[token] < amount+fee {
		atomic.AddUint64(&s.metrics.FailedTransfers, 1)
		return fmt.Errorf("insufficient balance for amount + fee")
	}

	// Execute transfer
	src.Balance[token] -= amount + fee
	dst.Balance[token] += amount
	src.Nonce++
	src.UpdatedAt = time.Now()
	dst.UpdatedAt = time.Now()

	// Create transaction record
	tx := &RelayedTx{
		TxHash:    computeTxHash(from, to, token, amount, src.Nonce, time.Now()),
		From:      from,
		To:        to,
		Token:     token,
		Amount:    amount,
		Fee:       fee,
		Nonce:     src.Nonce,
		Status:    StatusPending,
		Timestamp: time.Now(),
	}

	// Add to mempool for async relay
	s.mempool = append(s.mempool, tx)
	s.allTxs[tx.TxHash] = tx
	s.txHistory[from] = append(s.txHistory[from], tx)
	s.txHistory[to] = append(s.txHistory[to], tx)

	atomic.AddUint64(&s.metrics.TotalTransfers, 1)
	atomic.StoreUint64(&s.metrics.MempoolSize, uint64(len(s.mempool)))

	// Broadcast to WebSocket clients
	s.broadcastWS(WebSocketMessage{
		Type:    "tx_pending",
		Payload: tx,
		Timestamp: time.Now(),
	})

	return nil
}

func (s *WalletStore) GetTransaction(txHash string) (*RelayedTx, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	tx, ok := s.allTxs[txHash]
	return tx, ok
}

func (s *WalletStore) GetHistory(address string, limit, offset int) []*RelayedTx {
	s.mu.RLock()
	defer s.mu.RUnlock()
	history := s.txHistory[address]
	if history == nil {
		return []*RelayedTx{}
	}
	// Return newest first
	start := offset
	if start >= len(history) {
		return []*RelayedTx{}
	}
	end := start + limit
	if end > len(history) {
		end = len(history)
	}
	result := make([]*RelayedTx, end-start)
	for i := start; i < end; i++ {
		result[i-start] = history[len(history)-1-i]
	}
	return result
}

func (s *WalletStore) GetMempool(limit int) []*RelayedTx {
	s.mu.RLock()
	defer s.mu.RUnlock()
	if limit <= 0 || limit > len(s.mempool) {
		limit = len(s.mempool)
	}
	result := make([]*RelayedTx, limit)
	copy(result, s.mempool[:limit])
	return result
}

func (s *WalletStore) GetMetrics() Metrics {
	metrics := Metrics{
		TotalRequests:   atomic.LoadUint64(&s.metrics.TotalRequests),
		TotalTransfers:  atomic.LoadUint64(&s.metrics.TotalTransfers),
		TotalRelayed:    atomic.LoadUint64(&s.metrics.TotalRelayed),
		FailedTransfers: atomic.LoadUint64(&s.metrics.FailedTransfers),
		ActiveWallets:   atomic.LoadUint64(&s.metrics.ActiveWallets),
		MempoolSize:     atomic.LoadUint64(&s.metrics.MempoolSize),
		UptimeSeconds:   uint64(time.Since(s.startTime).Seconds()),
	}
	return metrics
}

func (s *WalletStore) blockProducer() {
	ticker := time.NewTicker(12 * time.Second) // ~Ethereum block time
	defer ticker.Stop()
	for range ticker.C {
		s.mu.Lock()
		s.currentBlock++
		blockNum := s.currentBlock
		s.mu.Unlock()
		
		// Process mempool transactions
	s.processMempool(blockNum)
	}
}

func (s *WalletStore) processMempool(blockNum uint64) {
	s.mu.Lock()
	if len(s.mempool) == 0 {
		s.mu.Unlock()
		return
	}
	
	// Process up to 100 txs per block
	processCount := 100
	if len(s.mempool) < processCount {
		processCount = len(s.mempool)
	}
	
	processed := s.mempool[:processCount]
	s.mempool = s.mempool[processCount:]
	atomic.StoreUint64(&s.metrics.MempoolSize, uint64(len(s.mempool)))
	s.mu.Unlock()

	for _, tx := range processed {
		// Simulate network confirmation (95% success rate)
		success := rand.Float64() < 0.95
		
		s.mu.Lock()
		if success {
			tx.Status = StatusConfirmed
			tx.BlockNum = blockNum
			atomic.AddUint64(&s.metrics.TotalRelayed, 1)
		} else {
			tx.Status = StatusFailed
			tx.ErrorMsg = "Network congestion: transaction reverted"
			// Refund sender
			if src, ok := s.wallets[tx.From]; ok {
				src.Balance[tx.Token] += tx.Amount + tx.Fee
				src.UpdatedAt = time.Now()
			}
			atomic.AddUint64(&s.metrics.FailedTransfers, 1)
		}
		s.allTxs[tx.TxHash] = tx
		s.mu.Unlock()
	
		s.broadcastWS(WebSocketMessage{
			Type:      "tx_confirmed",
			Payload:   tx,
			Timestamp: time.Now(),
		})
	}
}

func (s *WalletStore) mempoolProcessor() {
	ticker := time.NewTicker(500 * time.Millisecond)
	defer ticker.Stop()
	for range ticker.C {
		s.mu.RLock()
		mempoolSize := len(s.mempool)
	s.mu.RUnlock()
		if mempoolSize > 1000 {
			// High mempool pressure - log warning
			log.Printf("WARNING: Mempool size %d exceeds threshold", mempoolSize)
		}
	}
}

func (s *WalletStore) metricsUpdater() {
	ticker := time.NewTicker(10 * time.Second)
	defer ticker.Stop()
	for range ticker.C {
		s.mu.RLock()
		atomic.StoreUint64(&s.metrics.ActiveWallets, uint64(len(s.wallets)))
		atomic.StoreUint64(&s.metrics.MempoolSize, uint64(len(s.mempool)))
	s.mu.RUnlock()
	}
}

func (s *WalletStore) broadcastWS(msg WebSocketMessage) {
	s.wsMu.Lock()
	defer s.wsMu.Unlock()
	data, _ := json.Marshal(msg)
	for client := range s.wsClients {
		err := client.WriteMessage(websocket.TextMessage, data)
		if err != nil {
			client.Close()
			delete(s.wsClients, client)
		}
	}
}

func (s *WalletStore) registerWS(conn *websocket.Conn) {
	s.wsMu.Lock()
	defer s.wsMu.Unlock()
	s.wsClients[conn] = true
}

func (s *WalletStore) unregisterWS(conn *websocket.Conn) {
	s.wsMu.Lock()
	defer s.wsMu.Unlock()
	delete(s.wsClients, conn)
}

// HTTP Handlers

func (s *WalletStore) handleCreateWallet(w http.ResponseWriter, r *http.Request) {
	atomic.AddUint64(&s.metrics.TotalRequests, 1)
	if !s.limiter.Allow() {
		http.Error(w, `{"error":"rate limit exceeded"}`, http.StatusTooManyRequests)
		return
	}

	var req struct {
		Address string `json:"address"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"invalid JSON"}`, http.StatusBadRequest)
		return
	}

	wallet, err := s.Create(req.Address)
	if err != nil {
		http.Error(w, fmt.Sprintf(`{"error":"%s"}`, err.Error()), http.StatusBadRequest)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(wallet)
}

func (s *WalletStore) handleGetWallet(w http.ResponseWriter, r *http.Request) {
	atomic.AddUint64(&s.metrics.TotalRequests, 1)
	vars := mux.Vars(r)
	address := vars["address"]

	wallet, ok := s.Get(address)
	if !ok {
		http.Error(w, `{"error":"wallet not found"}`, http.StatusNotFound)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(wallet)
}

func (s *WalletStore) handleTransfer(w http.ResponseWriter, r *http.Request) {
	atomic.AddUint64(&s.metrics.TotalRequests, 1)
	if !s.limiter.Allow() {
		http.Error(w, `{"error":"rate limit exceeded"}`, http.StatusTooManyRequests)
		return
	}

	var req struct {
		From   string  `json:"from"`
		To     string  `json:"to"`
		Token  string  `json:"token"`
		Amount float64 `json:"amount"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"invalid JSON"}`, http.StatusBadRequest)
		return
	}

	if err := s.Transfer(req.From, req.To, req.Token, req.Amount); err != nil {
		http.Error(w, fmt.Sprintf(`{"error":"%s"}`, err.Error()), http.StatusBadRequest)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "pending"})
}

func (s *WalletStore) handleGetTransaction(w http.ResponseWriter, r *http.Request) {
	atomic.AddUint64(&s.metrics.TotalRequests, 1)
	vars := mux.Vars(r)
	txHash := vars["txHash"]

	tx, ok := s.GetTransaction(txHash)
	if !ok {
		http.Error(w, `{"error":"transaction not found"}`, http.StatusNotFound)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(tx)
}

func (s *WalletStore) handleGetHistory(w http.ResponseWriter, r *http.Request) {
	atomic.AddUint64(&s.metrics.TotalRequests, 1)
	vars := mux.Vars(r)
	address := vars["address"]

	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	if limit <= 0 || limit > 100 {
		limit = 20
	}
	offset, _ := strconv.Atoi(r.URL.Query().Get("offset"))
	if offset < 0 {
		offset = 0
	}

	history := s.GetHistory(address, limit, offset)
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"address": address,
		"transactions": history,
		"limit":    limit,
		"offset":   offset,
	})
}

func (s *WalletStore) handleGetMempool(w http.ResponseWriter, r *http.Request) {
	atomic.AddUint64(&s.metrics.TotalRequests, 1)
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	if limit <= 0 || limit > 100 {
		limit = 50
	}

	mempool := s.GetMempool(limit)
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"mempool": mempool,
		"count":   len(mempool),
	})
}

func (s *WalletStore) handleMetrics(w http.ResponseWriter, r *http.Request) {
	atomic.AddUint64(&s.metrics.TotalRequests, 1)
	metrics := s.GetMetrics()
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(metrics)
}

func (s *WalletStore) handleHealth(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{
		"status":  "healthy",
		"version": "1.0.0",
		"time":    time.Now().UTC().Format(time.RFC3339),
	})
}

func (s *WalletStore) handleWebSocket(w http.ResponseWriter, r *http.Request) {
	upgrader := websocket.Upgrader{
		CheckOrigin: func(r *http.Request) bool { return true },
	}
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("WebSocket upgrade error: %v", err)
		return
	}
	defer conn.Close()

	s.registerWS(conn)
	defer s.unregisterWS(conn)

	// Send initial state
	metrics := s.GetMetrics()
	conn.WriteJSON(WebSocketMessage{
		Type:      "init",
		Payload:   metrics,
		Timestamp: time.Now(),
	})

	// Keep connection alive
	for {
		_, _, err := conn.ReadMessage()
		if err != nil {
			break
		}
	}
}

func (s *WalletStore) handleTokens(w http.ResponseWriter, r *http.Request) {
	atomic.AddUint64(&s.metrics.TotalRequests, 1)
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"tokens": SupportedTokens,
	})
}

// Utility functions

func isValidAddress(address string) bool {
	matched, _ := regexp.MatchString(`^0x[a-fA-F0-9]{40}$`, address)
	return matched
}

func isValidToken(token string) bool {
	for _, t := range SupportedTokens {
		if strings.EqualFold(t, token) {
			return true
		}
	}
	return false
}

func calculateFee(token string, amount float64, mempoolSize int) float64 {
	baseFee := map[string]float64{
		"OPUS": 0.001,
		"ETH":  0.0005,
		"BTC":  0.0001,
		"SOL":  0.000005,
		"USDC": 0.5,
	}
	fee := baseFee[token]
	if fee == 0 {
		fee = 0.001
	}
	// Dynamic fee based on mempool congestion
	congestionMultiplier := 1.0 + float64(mempoolSize)/10000.0
	if congestionMultiplier > 5.0 {
		congestionMultiplier = 5.0
	}
	return fee * congestionMultiplier
}

func loggingMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		next.ServeHTTP(w, r)
		log.Printf("%s %s %v", r.Method, r.URL.Path, time.Since(start))
	})
}

func corsMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")
		if r.Method == "OPTIONS" {
			w.WriteHeader(http.StatusOK)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func main() {
	rand.Seed(time.Now().UnixNano())

	store := NewWalletStore()

	r := mux.NewRouter()
	r.Use(loggingMiddleware, corsMiddleware)

	// API routes
	api := r.PathPrefix("/api/v1").Subrouter()
	api.HandleFunc("/health", store.handleHealth).Methods("GET")
	api.HandleFunc("/tokens", store.handleTokens).Methods("GET")
	api.HandleFunc("/wallets", store.handleCreateWallet).Methods("POST")
	api.HandleFunc("/wallets/{address}", store.handleGetWallet).Methods("GET")
	api.HandleFunc("/wallets/{address}/history", store.handleGetHistory).Methods("GET")
	api.HandleFunc("/transfer", store.handleTransfer).Methods("POST")
	api.HandleFunc("/transactions/{txHash}", store.handleGetTransaction).Methods("GET")
	api.HandleFunc("/mempool", store.handleGetMempool).Methods("GET")
	api.HandleFunc("/metrics", store.handleMetrics).Methods("GET")
	api.HandleFunc("/ws", store.handleWebSocket).Methods("GET")

	srv := &http.Server{
		Addr:         ":8080",
		Handler:      r,
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 15 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	// Graceful shutdown
	go func() {
		sigCh := make(chan os.Signal, 1)
		signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)
		<-sigCh
		log.Println("Shutting down server...")
		ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cancel()
		if err := srv.Shutdown(ctx); err != nil {
			log.Fatalf("Server forced to shutdown: %v", err)
		}
	}()

	log.Println("Magnum Opus Relay Service starting on :8080")
	if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		log.Fatalf("Server error: %v", err)
	}
	log.Println("Server stopped")
}
