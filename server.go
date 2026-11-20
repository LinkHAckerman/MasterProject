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
	s.metrics.TotalTransfers = atomic.AddUint64(&s.metrics.TotalTransfers, 1)
	s.metrics.MempoolSize = uint64(len(s.mempool))

	return tx, nil
}

func (s *WalletStore) RelayTx(req RelayTxRequest) (*RelayedTx, error) {
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
	if req.Fee < 0 {
		atomic.AddUint64(&s.metrics.FailedTransfers, 1)
		return nil, fmt.Errorf("transaction fee cannot be negative")
	}

	s.mu.Lock()
	defer s.mu.Unlock()

	sender, exists := s.wallets[from]
	if !exists {
		atomic.AddUint64(&s.metrics.FailedTransfers, 1)
		return nil, fmt.Errorf("sender wallet does not exist")
	}

	if sender.Nonce != req.Nonce {
		atomic.AddUint64(&s.metrics.FailedTransfers, 1)
		return nil, fmt.Errorf("invalid nonce: expected %d, got %d", sender.Nonce, req.Nonce)
	}

	if sender.Balance[token] < req.Amount+req.Fee {
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

	sender.Balance[token] -= req.Amount + req.Fee
	sender.Nonce++
	sender.UpdatedAt = time.Now()

	recipient.Balance[token] += req.Amount
	recipient.UpdatedAt = time.Now()

	txRaw := fmt.Sprintf("%s:%s:%s:%f:%f:%d:%d:%s", from, to, token, req.Amount, req.Fee, req.Nonce, time.Now().UnixNano(), req.Signature)
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
	s.metrics.TotalRelayed = atomic.AddUint64(&s.metrics.TotalRelayed, 1)
	s.metrics.MempoolSize = uint64(len(s.mempool))

	return tx, nil
}

func (s *WalletStore) GetTransaction(txHash string) (*RelayedTx, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	tx, exists := s.allTxs[txHash]
	return tx, exists
}

func (s *WalletStore) GetTransactionHistory(addr string) ([]*RelayedTx, bool) {
	norm := strings.ToLower(addr)
	s.mu.RLock()
	defer s.mu.RUnlock()
	history, exists := s.txHistory[norm]
	return history, exists
}

func (s *WalletStore) GetMempool() []*RelayedTx {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.mempool
}

func (s *WalletStore) GetMetrics() Metrics {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.metrics
}

func (s *WalletStore) MineBlock() *BlockInfo {
	s.mu.Lock()
	defer s.mu.Unlock()

	if len(s.mempool) == 0 {
		return nil
	}

	block := &BlockInfo{
		BlockNumber: s.currentBlock,
		BlockHash:   computeHash(fmt.Sprintf("block:%d:%d", s.currentBlock, time.Now().UnixNano())),
		TxCount:     len(s.mempool),
		Timestamp:   time.Now(),
		Txs:         make([]*RelayedTx, len(s.mempool)),
	}

	copy(block.Txs, s.mempool)

	for _, tx := range s.mempool {
		tx.Status = StatusConfirmed
		tx.BlockNum = s.currentBlock
	}

	s.blocks = append(s.blocks, block)
	s.mempool = make([]*RelayedTx, 0)
	s.currentBlock++
	s.metrics.MempoolSize = 0

	return block
}

func (s *WalletStore) GetBlocks() []*BlockInfo {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.blocks
}

// ------------------------------------------------------------
// WebSocket Methods
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

func (s *WalletStore) BroadcastWebSocketMessage(msg WebSocketMessage) {
	s.wsMu.Lock()
	defer s.wsMu.Unlock()

	for conn := range s.wsClients {
		go func(c *websocket.Conn) {
			if err := c.WriteJSON(msg); err != nil {
				log.Printf("Error broadcasting WebSocket message: %v", err)
			}
		}(conn)
	}
}

// ------------------------------------------------------------
// HTTP Handlers
// ------------------------------------------------------------

func (s *WalletStore) CreateWalletHandler(w http.ResponseWriter, r *http.Request) {
	atomic.AddUint64(&s.metrics.TotalRequests, 1)

	if !s.limiter.Allow() {
		http.Error(w, "Too many requests", http.StatusTooManyRequests)
		return
	}

	var req CreateWalletRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		resp := APIResponse{
			Success: false,
			Error:   fmt.Sprintf("Invalid request payload: %v", err),
		}
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(resp)
		return
	}

	wallet, err := s.GetOrCreateWallet(req.Address)
	if err != nil {
		resp := APIResponse{
			Success: false,
			Error:   err.Error(),
		}
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(resp)
		return
	}

	resp := APIResponse{
		Success: true,
		Data:    wallet,
	}
	json.NewEncoder(w).Encode(resp)

	msg := WebSocketMessage{
		Type:      "wallet_created",
		Payload:   wallet,
		Timestamp: time.Now(),
	}
	s.BroadcastWebSocketMessage(msg)
}

func (s *WalletStore) TransferHandler(w http.ResponseWriter, r *http.Request) {
	atomic.AddUint64(&s.metrics.TotalRequests, 1)

	if !s.limiter.Allow() {
		http.Error(w, "Too many requests", http.StatusTooManyRequests)
		return
	}

	var req TransferRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		resp := APIResponse{
			Success: false,
			Error:   fmt.Sprintf("Invalid request payload: %v", err),
		}
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(resp)
		return
	}

	tx, err := s.Transfer(req)
	if err != nil {
		resp := APIResponse{
			Success: false,
			Error:   err.Error(),
		}
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(resp)
		return
	}

	resp := APIResponse{
		Success: true,
		Data:    tx,
	}
	json.NewEncoder(w).Encode(resp)

	msg := WebSocketMessage{
		Type:      "transaction_created",
		Payload:   tx,
		Timestamp: time.Now(),
	}
	s.BroadcastWebSocketMessage(msg)
}

func (s *WalletStore) RelayTxHandler(w http.ResponseWriter, r *http.Request) {
	atomic.AddUint64(&s.metrics.TotalRequests, 1)

	if !s.limiter.Allow() {
		http.Error(w, "Too many requests", http.StatusTooManyRequests)
		return
	}

	var req RelayTxRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		resp := APIResponse{
			Success: false,
			Error:   fmt.Sprintf("Invalid request payload: %v", err),
		}
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(resp)
		return
	}

	tx, err := s.RelayTx(req)
	if err != nil {
		resp := APIResponse{
			Success: false,
			Error:   err.Error(),
		}
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(resp)
		return
	}

	resp := APIResponse{
		Success: true,
		Data:    tx,
	}
	json.NewEncoder(w).Encode(resp)

	msg := WebSocketMessage{
		Type:      "transaction_relayed",
		Payload:   tx,
		Timestamp: time.Now(),
	}
	s.BroadcastWebSocketMessage(msg)
}

func (s *WalletStore) GetWalletHandler(w http.ResponseWriter, r *http.Request) {
	atomic.AddUint64(&s.metrics.TotalRequests, 1)

	if !s.limiter.Allow() {
		http.Error(w, "Too many requests", http.StatusTooManyRequests)
		return
	}

	vars := mux.Vars(r)
	addr := vars["address"]

	wallet, exists := s.GetWallet(addr)
	if !exists {
		resp := APIResponse{
			Success: false,
			Error:   "Wallet not found",
		}
		w.WriteHeader(http.StatusNotFound)
		json.NewEncoder(w).Encode(resp)
		return
	}

	resp := APIResponse{
		Success: true,
		Data:    wallet,
	}
	json.NewEncoder(w).Encode(resp)
}

func (s *WalletStore) GetTransactionHandler(w http.ResponseWriter, r *http.Request) {
	atomic.AddUint64(&s.metrics.TotalRequests, 1)

	if !s.limiter.Allow() {
		http.Error(w, "Too many requests", http.StatusTooManyRequests)
		return
	}

	vars := mux.Vars(r)
	txHash := vars["txHash"]

	tx, exists := s.GetTransaction(txHash)
	if !exists {
		resp := APIResponse{
			Success: false,
			Error:   "Transaction not found",
		}
		w.WriteHeader(http.StatusNotFound)
		json.NewEncoder(w).Encode(resp)
		return
	}

	resp := APIResponse{
		Success: true,
		Data:    tx,
	}
	json.NewEncoder(w).Encode(resp)
}

func (s *WalletStore) GetTransactionHistoryHandler(w http.ResponseWriter, r *http.Request) {
	atomic.AddUint64(&s.metrics.TotalRequests, 1)

	if !s.limiter.Allow() {
		http.Error(w, "Too many requests", http.StatusTooManyRequests)
		return
	}

	vars := mux.Vars(r)
	addr := vars["address"]

	history, exists := s.GetTransactionHistory(addr)
	if !exists {
		resp := APIResponse{
			Success: false,
			Error:   "Wallet not found",
		}
		w.WriteHeader(http.StatusNotFound)
		json.NewEncoder(w).Encode(resp)
		return
	}

	resp := APIResponse{
		Success: true,
		Data:    history,
	}
	json.NewEncoder(w).Encode(resp)
}

func (s *WalletStore) GetMempoolHandler(w http.ResponseWriter, r *http.Request) {
	atomic.AddUint64(&s.metrics.TotalRequests, 1)

	if !s.limiter.Allow() {
		http.Error(w, "Too many requests", http.StatusTooManyRequests)
		return
	}

	mempool := s.GetMempool()

	resp := APIResponse{
		Success: true,
		Data:    mempool,
	}
	json.NewEncoder(w).Encode(resp)
}

func (s *WalletStore) GetMetricsHandler(w http.ResponseWriter, r *http.Request) {
	atomic.AddUint64(&s.metrics.TotalRequests, 1)

	if !s.limiter.Allow() {
		http.Error(w, "Too many requests", http.StatusTooManyRequests)
		return
	}

	metrics := s.GetMetrics()

	resp := APIResponse{
		Success: true,
		Data:    metrics,
	}
	json.NewEncoder(w).Encode(resp)
}

func (s *WalletStore) MineBlockHandler(w http.ResponseWriter, r *http.Request) {
	atomic.AddUint64(&s.metrics.TotalRequests, 1)

	if !s.limiter.Allow() {
		http.Error(w, "Too many requests", http.StatusTooManyRequests)
		return
	}

	block := s.MineBlock()
	if block == nil {
		resp := APIResponse{
			Success: false,
			Error:   "No transactions in mempool",
		}
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(resp)
		return
	}

	resp := APIResponse{
		Success: true,
		Data:    block,
	}
	json.NewEncoder(w).Encode(resp)

	msg := WebSocketMessage{
		Type:      "block_mined",
		Payload:   block,
		Timestamp: time.Now(),
	}
	s.BroadcastWebSocketMessage(msg)
}

func (s *WalletStore) GetBlocksHandler(w http.ResponseWriter, r *http.Request) {
	atomic.AddUint64(&s.metrics.TotalRequests, 1)

	if !s.limiter.Allow() {
		http.Error(w, "Too many requests", http.StatusTooManyRequests)
		return
	}

	blocks := s.GetBlocks()

	resp := APIResponse{
		Success: true,
		Data:    blocks,
	}
	json.NewEncoder(w).Encode(resp)
}

func (s *WalletStore) WebSocketHandler(w http.ResponseWriter, r *http.Request) {
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("Error upgrading WebSocket connection: %v", err)
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

	r.HandleFunc("/wallets", store.CreateWalletHandler).Methods("POST")
	r.HandleFunc("/wallets/{address}", store.GetWalletHandler).Methods("GET")
	r.HandleFunc("/transactions", store.TransferHandler).Methods("POST")
	r.HandleFunc("/transactions/relay", store.RelayTxHandler).Methods("POST")
	r.HandleFunc("/transactions/{txHash}", store.GetTransactionHandler).Methods("GET")
	r.HandleFunc("/wallets/{address}/transactions", store.GetTransactionHistoryHandler).Methods("GET")
	r.HandleFunc("/mempool", store.GetMempoolHandler).Methods("GET")
	r.HandleFunc("/metrics", store.GetMetricsHandler).Methods("GET")
	r.HandleFunc("/mine", store.MineBlockHandler).Methods("POST")
	r.HandleFunc("/blocks", store.GetBlocksHandler).Methods("GET")
	r.HandleFunc("/ws", store.WebSocketHandler)

	srv := &http.Server{
		Handler:      r,
		Addr:         ":8080",
		WriteTimeout: 15 * time.Second,
		ReadTimeout:  15 * time.Second,
	}

	done := make(chan os.Signal, 1)
	signal.Notify(done, os.Interrupt, syscall.SIGINT, syscall.SIGTERM)

	go func() {
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("ListenAndServe(): %v", err)
		}
	}()

	log.Println("Server started on :8080")

	<-done

	log.Println("Server stopped")

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if err := srv.Shutdown(ctx); err != nil {
		log.Fatalf("Server shutdown failed: %v", err)
	}

	log.Println("Server exited properly")
}