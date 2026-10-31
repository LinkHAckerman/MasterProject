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

	// Seed the relayer gas-station wallet
	relayer := &Wallet{
		Address: "0x000000000000000000000000000000000000dEaD",
		Balance: map[string]float64{
			"OPUS": 1000000.0,
			"ETH":  5000.0,
			"USDC": 5000000.0,
			"BTC":  100.0,
			"SOL":  10000.0,
		},
		Nonce:     0,
		CreatedAt: time.Now(),
		UpdatedAt: time.Now(),
	}
	store.wallets[relayer.Address] = relayer

	// Seed demo user wallet
	demoUser := &Wallet{
		Address: "0x71C7656EC7ab88b098defB751B7401B5f6d8976F",
		Balance: map[string]float64{
			"OPUS": 12500.0,
			"ETH":  14.5,
			"USDC": 45000.0,
			"BTC":  1.25,
			"SOL":  350.0,
		},
		Nonce:     1,
		CreatedAt: time.Now(),
		UpdatedAt: time.Now(),
	}
	store.wallets[demoUser.Address] = demoUser
	atomic.StoreUint64(&store.metrics.ActiveWallets, 2)

	go store.blockProducer()
	go store.metricsUpdater()

	return store
}

func computeTxHash(from, to, token string, amount float64, nonce uint64, ts time.Time) string {
	data := fmt.Sprintf("%s:%s:%s:%.8f:%d:%d", from, to, token, amount, nonce, ts.UnixNano())
	hash := sha256.Sum256([]byte(data))
	return "0x" + hex.EncodeToString(hash[:])
}

func isValidAddress(addr string) bool {
	// Simple Ethereum-style address validation (0x + 40 hex chars)
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
// WalletStore Core Operations
// ------------------------------------------------------------

func (ws *WalletStore) GetWallet(addr string) (*Wallet, bool) {
	ws.mu.RLock()
	defer ws.mu.RUnlock()
	w, exists := ws.wallets[strings.ToLower(addr)]
	if !exists {
		w, exists = ws.wallets[addr]
	}
	return w, exists
}

func (ws *WalletStore) GetOrCreateWallet(addr string) *Wallet {
	normalized := strings.ToLower(addr)
	ws.mu.Lock()
	defer ws.mu.Unlock()

	if w, exists := ws.wallets[normalized]; exists {
		return w
	}

	w := &Wallet{
		Address: addr,
		Balance: map[string]float64{
			"OPUS": 1000.0,
			"ETH":  1.0,
			"USDC": 500.0,
			"BTC":  0.0,
			"SOL":  10.0,
		},
		Nonce:     0,
		CreatedAt: time.Now(),
		UpdatedAt: time.Now(),
	}
	ws.wallets[normalized] = w
	atomic.AddUint64(&ws.metrics.ActiveWallets, 1)
	return w
}

func (ws *WalletStore) SubmitTransaction(from, to, token string, amount, fee float64, signature string) (*RelayedTx, error) {
	atomic.AddUint64(&ws.metrics.TotalRequests, 1)

	if !isValidAddress(from) || !isValidAddress(to) {
		atomic.AddUint64(&ws.metrics.FailedTransfers, 1)
		return nil, fmt.Errorf("invalid address format")
	}

	if !isSupportedToken(token) {
		atomic.AddUint64(&ws.metrics.FailedTransfers, 1)
		return nil, fmt.Errorf("unsupported token: %s", token)
	}

	if amount <= 0 {
		atomic.AddUint64(&ws.metrics.FailedTransfers, 1)
		return nil, fmt.Errorf("amount must be positive")
	}

	ws.mu.Lock()
	defer ws.mu.Unlock()

	fromNorm := strings.ToLower(from)
	sender, exists := ws.wallets[fromNorm]
	if !exists {
		atomic.AddUint64(&ws.metrics.FailedTransfers, 1)
		return nil, fmt.Errorf("sender wallet not found")
	}

	currentBal := sender.Balance[token]
	totalRequired := amount
	if token == "ETH" || token == "OPUS" {
		totalRequired += fee
	}

	if currentBal < totalRequired {
		atomic.AddUint64(&ws.metrics.FailedTransfers, 1)
		return nil, fmt.Errorf("insufficient balance: have %.4f, required %.4f", currentBal, totalRequired)
	}

	// Ensure recipient wallet exists
	_ = ws.getOrCreateWalletUnlocked(to)

	sender.Nonce++
	txHash := computeTxHash(from, to, token, amount, sender.Nonce, time.Now())

	tx := &RelayedTx{
		TxHash:    txHash,
		From:      from,
		To:        to,
		Token:     token,
		Amount:    amount,
		Fee:       fee,
		Nonce:     sender.Nonce,
		Signature: signature,
		Status:    StatusPending,
		Timestamp: time.Now(),
	}

	ws.mempool = append(ws.mempool, tx)
	ws.allTxs[txHash] = tx

	fromHistory := ws.txHistory[fromNorm]
	ws.txHistory[fromNorm] = append(fromHistory, tx)

	toNorm := strings.ToLower(to)
	if toNorm != fromNorm {
		toHistory := ws.txHistory[toNorm]
		ws.txHistory[toNorm] = append(toHistory, tx)
	}

	atomic.AddUint64(&ws.metrics.TotalTransfers, 1)
	atomic.StoreUint64(&ws.metrics.MempoolSize, uint64(len(ws.mempool)))

	ws.broadcastUnlocked(WebSocketMessage{
		Type:      "TX_SUBMITTED",
		Payload:   tx,
		Timestamp: time.Now(),
	})

	return tx, nil
}

func (ws *WalletStore) getOrCreateWalletUnlocked(addr string) *Wallet {
	normalized := strings.ToLower(addr)
	if w, exists := ws.wallets[normalized]; exists {
		return w
	}
	w := &Wallet{
		Address: addr,
		Balance: map[string]float64{
			"OPUS": 0.0,
			"ETH":  0.0,
			"USDC": 0.0,
			"BTC":  0.0,
			"SOL":  0.0,
		},
		Nonce:     0,
		CreatedAt: time.Now(),
		UpdatedAt: time.Now(),
	}
	ws.wallets[normalized] = w
	atomic.AddUint64(&ws.metrics.ActiveWallets, 1)
	return w
}

func (ws *WalletStore) RelayMetaTx(from, to, token string, amount, fee float64, nonce uint64, signature string) (*RelayedTx, error) {
	atomic.AddUint64(&ws.metrics.TotalRelayed, 1)
	tx, err := ws.SubmitTransaction(from, to, token, amount, fee, signature)
	if err != nil {
		return nil, err
	}
	tx.Status = StatusRelayed
	return tx, nil
}

func (ws *WalletStore) GetTxHistory(addr string) []*RelayedTx {
	ws.mu.RLock()
	defer ws.mu.RUnlock()
	history, exists := ws.txHistory[strings.ToLower(addr)]
	if !exists {
		return []*RelayedTx{}
	}
	result := make([]*RelayedTx, len(history))
	copy(result, history)
	return result
}

func (ws *WalletStore) GetMempool() []*RelayedTx {
	ws.mu.RLock()
	defer ws.mu.RUnlock()
	result := make([]*RelayedTx, len(ws.mempool))
	copy(result, ws.mempool)
	return result
}

func (ws *WalletStore) GetMetrics() Metrics {
	m := ws.metrics
	m.MempoolSize = uint64(len(ws.GetMempool()))
	m.UptimeSeconds = uint64(time.Since(ws.startTime).Seconds())
	return m
}

// ------------------------------------------------------------
// Block Producer & Telemetry Loops
// ------------------------------------------------------------

func (ws *WalletStore) blockProducer() {
	ticker := time.NewTicker(3 * time.Second)
	defer ticker.Stop()

	for range ticker.C {
		ws.mu.Lock()
		if len(ws.mempool) == 0 {
			ws.mu.Unlock()
			continue
		}

		ws.currentBlock++
		blockNum := ws.currentBlock
		txsToConfirm := ws.mempool
		ws.mempool = make([]*RelayedTx, 0)
		atomic.StoreUint64(&ws.metrics.MempoolSize, 0)

		blockTxs := make([]*RelayedTx, 0, len(txsToConfirm))

		for _, tx := range txsToConfirm {
			fromNorm := strings.ToLower(tx.From)
			toNorm := strings.ToLower(tx.To)

			sender, sExists := ws.wallets[fromNorm]
			recipient, rExists := ws.wallets[toNorm]

			if sExists && rExists && sender.Balance[tx.Token] >= tx.Amount {
				sender.Balance[tx.Token] -= tx.Amount
				if tx.Fee > 0 && tx.Token == "OPUS" {
					sender.Balance[tx.Token] -= tx.Fee
				}
				recipient.Balance[tx.Token] += tx.Amount

				sender.UpdatedAt = time.Now()
				recipient.UpdatedAt = time.Now()

				tx.Status = StatusConfirmed
				tx.BlockNum = blockNum
				blockTxs = append(blockTxs, tx)
			} else {
				tx.Status = StatusFailed
				tx.ErrorMsg = "Execution reverted: balance mismatch or invalid state"
			}
		}

		blockHeaderData := fmt.Sprintf("BLOCK:%d:%d", blockNum, time.Now().Unix())
		blockHash := "0x" + hex.EncodeToString(sha256.New().Sum([]byte(blockHeaderData)))

		blockInfo := BlockInfo{
			BlockNumber: blockNum,
			BlockHash:   blockHash,
			TxCount:     len(blockTxs),
			Timestamp:   time.Now(),
			Txs:         blockTxs,
		}

		ws.broadcastUnlocked(WebSocketMessage{
			Type:      "BLOCK_MINED",
			Payload:   blockInfo,
			Timestamp: time.Now(),
		})

		ws.mu.Unlock()
	}
}

func (ws *WalletStore) metricsUpdater() {
	ticker := time.NewTicker(10 * time.Second)
	defer ticker.Stop()

	for range ticker.C {
		m := ws.GetMetrics()
		ws.Broadcast(WebSocketMessage{
			Type:      "METRICS_UPDATE",
			Payload:   m,
			Timestamp: time.Now(),
		})
	}
}

// ------------------------------------------------------------
// WebSocket Management
// ------------------------------------------------------------

var upgrader = websocket.Upgrader{
	ReadBufferSize:  1024,
	WriteBufferSize: 1024,
	CheckOrigin: func(r *http.Request) bool {
		return true
	},
}

func (ws *WalletStore) Broadcast(msg WebSocketMessage) {
	ws.mu.RLock()
	defer ws.mu.RUnlock()
	ws.broadcastUnlocked(msg)
}

func (ws *WalletStore) broadcastUnlocked(msg WebSocketMessage) {
	ws.wsMu.Lock()
	defer ws.wsMu.Unlock()

	data, err := json.Marshal(msg)
	if err != nil {
		return
	}

	for client := range ws.wsClients {
		err := client.WriteMessage(websocket.TextMessage, data)
		if err != nil {
			client.Close()
			delete(ws.wsClients, client)
		}
	}
}

func (ws *WalletStore) RegisterWS(conn *websocket.Conn) {
	ws.wsMu.Lock()
	ws.wsClients[conn] = true
	ws.wsMu.Unlock()

	welcome := WebSocketMessage{
		Type: "CONNECTED",
		Payload: map[string]interface{}{
			"status":         "CONNECTED",
			"block_number":   atomic.LoadUint64(&ws.currentBlock),
			"active_wallets": atomic.LoadUint64(&ws.metrics.ActiveWallets),
		},
		Timestamp: time.Now(),
	}
	data, _ := json.Marshal(welcome)
	_ = conn.WriteMessage(websocket.TextMessage, data)
}

func (ws *WalletStore) UnregisterWS(conn *websocket.Conn) {
	ws.wsMu.Lock()
	delete(ws.wsClients, conn)
	ws.wsMu.Unlock()
	conn.Close()
}

// ------------------------------------------------------------
// HTTP Handlers & Middleware
// ------------------------------------------------------------

func writeJSON(w http.ResponseWriter, status int, resp APIResponse) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(resp)
}

func (ws *WalletStore) RateLimitMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !ws.limiter.Allow() {
			writeJSON(w, http.StatusTooManyRequests, APIResponse{
				Success: false,
				Error:   "Rate limit exceeded. Please try again shortly.",
			})
			return
		}
		next.ServeHTTP(w, r)
	})
}

func CORSMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS, PUT, DELETE")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization, X-Requested-With")

		if r.Method == "OPTIONS" {
			w.WriteHeader(http.StatusOK)
			return
		}

		next.ServeHTTP(w, r)
	})
}

func (ws *WalletStore) HealthCheckHandler(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, APIResponse{
		Success: true,
		Data: map[string]interface{}{
			"status":       "HEALTHY",
			"service":      "Magnum Opus Web3 Relay Engine",
			"version":      "2.5.0-production",
			"block_number": atomic.LoadUint64(&ws.currentBlock),
			"timestamp":    time.Now(),
		},
	})
}

func (ws *WalletStore) MetricsHandler(w http.ResponseWriter, r *http.Request) {
	metrics := ws.GetMetrics()
	writeJSON(w, http.StatusOK, APIResponse{
		Success: true,
		Data:    metrics,
	})
}

func (ws *WalletStore) GetWalletHandler(w http.ResponseWriter, r *http.Request) {
	vars := mux.Vars(r)
	address := vars["address"]

	if !isValidAddress(address) {
		writeJSON(w, http.StatusBadRequest, APIResponse{
			Success: false,
			Error:   "Invalid Ethereum address format",
		})
		return
	}

	wallet, exists := ws.GetWallet(address)
	if !exists {
		wallet = ws.GetOrCreateWallet(address)
	}

	writeJSON(w, http.StatusOK, APIResponse{
		Success: true,
		Data:    wallet,
	})
}

func (ws *WalletStore) CreateWalletHandler(w http.ResponseWriter, r *http.Request) {
	var req CreateWalletRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, APIResponse{
			Success: false,
			Error:   "Invalid JSON payload",
		})
		return
	}

	if req.Address == "" {
		b := make([]byte, 20)
		_, _ = rand.Read(b)
		req.Address = "0x" + hex.EncodeToString(b)
	} else if !isValidAddress(req.Address) {
		writeJSON(w, http.StatusBadRequest, APIResponse{
			Success: false,
			Error:   "Invalid Ethereum address format",
		})
		return
	}

	wallet := ws.GetOrCreateWallet(req.Address)
	writeJSON(w, http.StatusCreated, APIResponse{
		Success: true,
		Data:    wallet,
	})
}

func (ws *WalletStore) TransferHandler(w http.ResponseWriter, r *http.Request) {
	var req TransferRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, APIResponse{
			Success: false,
			Error:   "Invalid request payload",
		})
		return
	}

	tx, err := ws.SubmitTransaction(req.From, req.To, req.Token, req.Amount, 0.001, "")
	if err != nil {
		writeJSON(w, http.StatusBadRequest, APIResponse{
			Success: false,
			Error:   err.Error(),
		})
		return
	}

	writeJSON(w, http.StatusAccepted, APIResponse{
		Success: true,
		Data:    tx,
	})
}

func (ws *WalletStore) RelayTxHandler(w http.ResponseWriter, r *http.Request) {
	var req RelayTxRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, APIResponse{
			Success: false,
			Error:   "Invalid JSON request body",
		})
		return
	}

	tx, err := ws.RelayMetaTx(req.From, req.To, req.Token, req.Amount, req.Fee, req.Nonce, req.Signature)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, APIResponse{
			Success: false,
			Error:   err.Error(),
		})
		return
	}

	writeJSON(w, http.StatusAccepted, APIResponse{
		Success: true,
		Data:    tx,
	})
}

func (ws *WalletStore) GetTxHistoryHandler(w http.ResponseWriter, r *http.Request) {
	vars := mux.Vars(r)
	address := vars["address"]

	if !isValidAddress(address) {
		writeJSON(w, http.StatusBadRequest, APIResponse{
			Success: false,
			Error:   "Invalid wallet address",
		})
		return
	}

	history := ws.GetTxHistory(address)
	writeJSON(w, http.StatusOK, APIResponse{
		Success: true,
		Data:    history,
	})
}

func (ws *WalletStore) GetMempoolHandler(w http.ResponseWriter, r *http.Request) {
	mempool := ws.GetMempool()
	writeJSON(w, http.StatusOK, APIResponse{
		Success: true,
		Data: map[string]interface{}{
			"count":   len(mempool),
			"mempool": mempool,
		},
	})
}

func (ws *WalletStore) WebSocketHandler(w http.ResponseWriter, r *http.Request) {
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("[WS ERROR] Failed to upgrade connection: %v", err)
		return
	}

	ws.RegisterWS(conn)

	go func() {
		defer ws.UnregisterWS(conn)
		for {
			_, _, err := conn.ReadMessage()
			if err != nil {
				break
			}
		}
	}()
}

// ------------------------------------------------------------
// Application Entry Point
// ------------------------------------------------------------

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	store := NewWalletStore()

	r := mux.NewRouter()
	r.Use(CORSMiddleware)
	r.Use(store.RateLimitMiddleware)

	// API Endpoints
	r.HandleFunc("/health", store.HealthCheckHandler).Methods("GET", "OPTIONS")
	r.HandleFunc("/ws", store.WebSocketHandler)

	api := r.PathPrefix("/api/v1").Subrouter()
	api.HandleFunc("/metrics", store.MetricsHandler).Methods("GET", "OPTIONS")
	api.HandleFunc("/wallet", store.CreateWalletHandler).Methods("POST", "OPTIONS")
	api.HandleFunc("/wallet/{address}", store.GetWalletHandler).Methods("GET", "OPTIONS")
	api.HandleFunc("/wallet/{address}/history", store.GetTxHistoryHandler).Methods("GET", "OPTIONS")
	api.HandleFunc("/transfer", store.TransferHandler).Methods("POST", "OPTIONS")
	api.HandleFunc("/relay", store.RelayTxHandler).Methods("POST", "OPTIONS")
	api.HandleFunc("/mempool", store.GetMempoolHandler).Methods("GET", "OPTIONS")

	srv := &http.Server{
		Addr:         ":" + port,
		Handler:      r,
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 15 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	stopChan := make(chan os.Signal, 1)
	signal.Notify(stopChan, os.Interrupt, syscall.SIGTERM)

	go func() {
		log.Printf("==========================================================================")
		log.Printf(" MAGNUM OPUS // Web3 & DeFi Relay Microservice running on port :%s", port)
		log.Printf(" WebSocket Feed: ws://localhost:%s/ws", port)
		log.Printf(" REST API Base:  http://localhost:%s/api/v1", port)
		log.Printf("==========================================================================")

		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("[FATAL ERROR] HTTP server failed: %v", err)
		}
	}()

	<-stopChan
	log.Println("\n[SHUTDOWN] Terminating Magnum Opus Microservice gracefully...")

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if err := srv.Shutdown(ctx); err != nil {
		log.Fatalf("[SHUTDOWN ERROR] Server forced to shutdown: %v", err)
	}

	log.Println("[SHUTDOWN] Microservice stopped cleanly.")
}
