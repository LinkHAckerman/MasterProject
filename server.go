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

var addressRegex = regexp.MustCompile(`^0x[a-fA-F0-9]{40}$`)

var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool {
		return true
	},
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
		limiter:      rate.NewLimiter(rate.Limit(100), 200),
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

	return store
}

func (s *WalletStore) SeedDemoData() {
	s.mu.Lock()
	defer s.mu.Unlock()

	demoAddresses := []struct {
		Addr    string
		Balance map[string]float64
	}{
		{
			Addr: "0x71C7656EC7ab88b098defB751B7401B5f6d8976F",
			Balance: map[string]float64{
				"OPUS": 25000.0,
				"ETH":  14.5,
				"USDC": 120000.0,
				"BTC":  1.25,
				"SOL":  340.0,
			},
		},
		{
			Addr: "0x2546BcD3c84621e976D8185a91A922aE77CCE930",
			Balance: map[string]float64{
				"OPUS": 50000.0,
				"ETH":  42.0,
				"USDC": 350000.0,
				"BTC":  3.8,
				"SOL":  890.0,
			},
		},
		{
			Addr: "0xbDA5B651358093930da805385a402AD067F85599",
			Balance: map[string]float64{
				"OPUS": 1000.0,
				"ETH":  2.1,
				"USDC": 5000.0,
				"BTC":  0.05,
				"SOL":  45.0,
			},
		},
	}

	for _, demo := range demoAddresses {
		s.wallets[strings.ToLower(demo.Addr)] = &Wallet{
			Address:   demo.Addr,
			Balance:   demo.Balance,
			Nonce:     0,
			CreatedAt: time.Now(),
			UpdatedAt: time.Now(),
		}
	}
	s.metrics.ActiveWallets = uint64(len(s.wallets))
}

func isValidAddress(addr string) bool {
	return addressRegex.MatchString(addr)
}

func isValidToken(token string) bool {
	for _, t := range SupportedTokens {
		if strings.EqualFold(t, token) {
			return true
		}
	}
	return false
}

func computeTxHash(from, to, token string, amount float64, nonce uint64, ts int64) string {
	data := fmt.Sprintf("%s:%s:%s:%.8f:%d:%d", strings.ToLower(from), strings.ToLower(to), strings.ToUpper(token), amount, nonce, ts)
	hash := sha256.Sum256([]byte(data))
	return "0x" + hex.EncodeToString(hash[:])
}

// ------------------------------------------------------------
// Store Methods
// ------------------------------------------------------------

func (s *WalletStore) CreateWallet(address string) (*Wallet, error) {
	if !isValidAddress(address) {
		return nil, fmt.Errorf("invalid EVM wallet address format")
	}

	key := strings.ToLower(address)
	s.mu.Lock()
	defer s.mu.Unlock()

	if wallet, exists := s.wallets[key]; exists {
		return wallet, nil
	}

	newWallet := &Wallet{
		Address: address,
		Balance: map[string]float64{
			"OPUS": 100.0,
			"ETH":  0.5,
			"USDC": 500.0,
			"BTC":  0.01,
			"SOL":  5.0,
		},
		Nonce:     0,
		CreatedAt: time.Now(),
		UpdatedAt: time.Now(),
	}

	s.wallets[key] = newWallet
	s.metrics.ActiveWallets = uint64(len(s.wallets))
	return newWallet, nil
}

func (s *WalletStore) GetWallet(address string) (*Wallet, error) {
	key := strings.ToLower(address)
	s.mu.RLock()
	defer s.mu.RUnlock()

	wallet, exists := s.wallets[key]
	if !exists {
		return nil, fmt.Errorf("wallet not found: %s", address)
	}
	return wallet, nil
}

func (s *WalletStore) GetAllWallets() []*Wallet {
	s.mu.RLock()
	defer s.mu.RUnlock()

	list := make([]*Wallet, 0, len(s.wallets))
	for _, w := range s.wallets {
		list = append(list, w)
	}
	return list
}

func (s *WalletStore) Transfer(req *TransferRequest) (*RelayedTx, error) {
	if !isValidAddress(req.From) || !isValidAddress(req.To) {
		return nil, fmt.Errorf("invalid sender or recipient address")
	}
	token := strings.ToUpper(req.Token)
	if !isValidToken(token) {
		return nil, fmt.Errorf("unsupported token: %s", req.Token)
	}
	if req.Amount <= 0 {
		return nil, fmt.Errorf("transfer amount must be greater than zero")
	}

	fromKey := strings.ToLower(req.From)
	toKey := strings.ToLower(req.To)

	s.mu.Lock()
	defer s.mu.Unlock()

	fromWallet, exists := s.wallets[fromKey]
	if !exists {
		atomic.AddUint64(&s.metrics.FailedTransfers, 1)
		return nil, fmt.Errorf("sender wallet does not exist")
	}

	toWallet, exists := s.wallets[toKey]
	if !exists {
		toWallet = &Wallet{
			Address:   req.To,
			Balance:   map[string]float64{"OPUS": 0, "ETH": 0, "USDC": 0, "BTC": 0, "SOL": 0},
			Nonce:     0,
			CreatedAt: time.Now(),
			UpdatedAt: time.Now(),
		}
		s.wallets[toKey] = toWallet
		s.metrics.ActiveWallets = uint64(len(s.wallets))
	}

	currentBal := fromWallet.Balance[token]
	if currentBal < req.Amount {
		atomic.AddUint64(&s.metrics.FailedTransfers, 1)
		return nil, fmt.Errorf("insufficient balance: requested %.4f %s, available %.4f", req.Amount, token, currentBal)
	}

	now := time.Now()
	fromWallet.Balance[token] -= req.Amount
	toWallet.Balance[token] += req.Amount
	fromWallet.Nonce++
	fromWallet.UpdatedAt = now
	toWallet.UpdatedAt = now

	txHash := computeTxHash(req.From, req.To, token, req.Amount, fromWallet.Nonce, now.UnixNano())
	tx := &RelayedTx{
		TxHash:    txHash,
		From:      req.From,
		To:        req.To,
		Token:     token,
		Amount:    req.Amount,
		Fee:       0.001,
		Nonce:     fromWallet.Nonce,
		Status:    StatusConfirmed,
		Timestamp: now,
		BlockNum:  s.currentBlock,
	}

	s.allTxs[txHash] = tx
	s.txHistory[fromKey] = append(s.txHistory[fromKey], tx)
	s.txHistory[toKey] = append(s.txHistory[toKey], tx)

	atomic.AddUint64(&s.metrics.TotalTransfers, 1)

	s.BroadcastWS("TRANSFER_CONFIRMED", tx)
	return tx, nil
}

func (s *WalletStore) RelayTransaction(req *RelayTxRequest) (*RelayedTx, error) {
	if !isValidAddress(req.From) || !isValidAddress(req.To) {
		return nil, fmt.Errorf("invalid sender or recipient address")
	}
	token := strings.ToUpper(req.Token)
	if !isValidToken(token) {
		return nil, fmt.Errorf("unsupported token: %s", req.Token)
	}
	if req.Amount <= 0 {
		return nil, fmt.Errorf("relay amount must be greater than zero")
	}
	if req.Signature == "" {
		return nil, fmt.Errorf("missing cryptographic signature for meta-transaction")
	}

	fromKey := strings.ToLower(req.From)
	s.mu.Lock()
	defer s.mu.Unlock()

	fromWallet, exists := s.wallets[fromKey]
	if !exists {
		atomic.AddUint64(&s.metrics.FailedTransfers, 1)
		return nil, fmt.Errorf("sender wallet does not exist")
	}

	// Simple nonce check to prevent replay attacks
	if req.Nonce <= fromWallet.Nonce {
		atomic.AddUint64(&s.metrics.FailedTransfers, 1)
		return nil, fmt.Errorf("invalid nonce: given %d, expected > %d", req.Nonce, fromWallet.Nonce)
	}

	now := time.Now()
	txHash := computeTxHash(req.From, req.To, token, req.Amount, req.Nonce, now.UnixNano())

	tx := &RelayedTx{
		TxHash:    txHash,
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
	s.allTxs[txHash] = tx
	s.metrics.MempoolSize = uint64(len(s.mempool))
	atomic.AddUint64(&s.metrics.TotalRelayed, 1)

	s.BroadcastWS("TX_RELAYED", tx)
	return tx, nil
}

func (s *WalletStore) GetTxByHash(hash string) (*RelayedTx, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	tx, exists := s.allTxs[hash]
	if !exists {
		return nil, fmt.Errorf("transaction not found: %s", hash)
	}
	return tx, nil
}

func (s *WalletStore) GetTxHistory(address string) []*RelayedTx {
	key := strings.ToLower(address)
	s.mu.RLock()
	defer s.mu.RUnlock()

	if history, exists := s.txHistory[key]; exists {
		return history
	}
	return []*RelayedTx{}
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
	return m
}

// ------------------------------------------------------------
// WebSocket Hub
// ------------------------------------------------------------

func (s *WalletStore) RegisterWS(conn *websocket.Conn) {
	s.wsMu.Lock()
	s.wsClients[conn] = true
	s.wsMu.Unlock()
}

func (s *WalletStore) UnregisterWS(conn *websocket.Conn) {
	s.wsMu.Lock()
	if _, ok := s.wsClients[conn]; ok {
		delete(s.wsClients, conn)
		conn.Close()
	}
	s.wsMu.Unlock()
}

func (s *WalletStore) BroadcastWS(msgType string, payload interface{}) {
	s.wsMu.Lock()
	defer s.wsMu.Unlock()

	msg := WebSocketMessage{
		Type:      msgType,
		Payload:   payload,
		Timestamp: time.Now(),
	}

	jsonBytes, err := json.Marshal(msg)
	if err != nil {
		return
	}

	for conn := range s.wsClients {
		err := conn.WriteMessage(websocket.TextMessage, jsonBytes)
		if err != nil {
			conn.Close()
			delete(s.wsClients, conn)
		}
	}
}

// ------------------------------------------------------------
// Background Engine Tasks
// ------------------------------------------------------------

func (s *WalletStore) StartMempoolRelayer(ctx context.Context) {
	ticker := time.NewTicker(3 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			s.processMempool()
		}
	}
}

func (s *WalletStore) processMempool() {
	s.mu.Lock()
	defer s.mu.Unlock()

	if len(s.mempool) == 0 {
		return
	}

	minedTxs := make([]*RelayedTx, 0)
	remainingMempool := make([]*RelayedTx, 0)

	for _, tx := range s.mempool {
		fromKey := strings.ToLower(tx.From)
		toKey := strings.ToLower(tx.To)

		fromWallet, hasFrom := s.wallets[fromKey]
		toWallet, hasTo := s.wallets[toKey]

		if !hasFrom || fromWallet.Balance[tx.Token] < (tx.Amount+tx.Fee) {
			tx.Status = StatusFailed
			tx.ErrorMsg = "Insufficient balance or gas fee"
			atomic.AddUint64(&s.metrics.FailedTransfers, 1)
			continue
		}

		if !hasTo {
			toWallet = &Wallet{
				Address:   tx.To,
				Balance:   map[string]float64{"OPUS": 0, "ETH": 0, "USDC": 0, "BTC": 0, "SOL": 0},
				Nonce:     0,
				CreatedAt: time.Now(),
				UpdatedAt: time.Now(),
			}
			s.wallets[toKey] = toWallet
		}

		// Execute state transition
		fromWallet.Balance[tx.Token] -= (tx.Amount + tx.Fee)
		toWallet.Balance[tx.Token] += tx.Amount
		fromWallet.Nonce = tx.Nonce
		fromWallet.UpdatedAt = time.Now()
		toWallet.UpdatedAt = time.Now()

		// Pay fee to relayer
		relayer := s.wallets["0x000000000000000000000000000000000000dead"]
		if relayer != nil {
			relayer.Balance[tx.Token] += tx.Fee
		}

		s.currentBlock++
		tx.Status = StatusConfirmed
		tx.BlockNum = s.currentBlock

		s.txHistory[fromKey] = append(s.txHistory[fromKey], tx)
		s.txHistory[toKey] = append(s.txHistory[toKey], tx)
		minedTxs = append(minedTxs, tx)
	}

	s.mempool = remainingMempool
	s.metrics.MempoolSize = uint64(len(s.mempool))
	s.metrics.ActiveWallets = uint64(len(s.wallets))

	if len(minedTxs) > 0 {
		blockHashData := fmt.Sprintf("%d:%d", s.currentBlock, time.Now().UnixNano())
		hash := sha256.Sum256([]byte(blockHashData))
		block := &BlockInfo{
			BlockNumber: s.currentBlock,
			BlockHash:   "0x" + hex.EncodeToString(hash[:]),
			TxCount:     len(minedTxs),
			Timestamp:   time.Now(),
			Txs:         minedTxs,
		}
		s.blocks = append(s.blocks, block)
		if len(s.blocks) > 50 {
			s.blocks = s.blocks[1:]
		}
		s.BroadcastWS("BLOCK_MINED", block)
	}
}

func (s *WalletStore) StartBlockProducer(ctx context.Context) {
	ticker := time.NewTicker(6 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			s.produceEmptyBlock()
		}
	}
}

func (s *WalletStore) produceEmptyBlock() {
	s.mu.Lock()
	defer s.mu.Unlock()

	s.currentBlock++
	blockHashData := fmt.Sprintf("empty:%d:%d", s.currentBlock, time.Now().UnixNano())
	hash := sha256.Sum256([]byte(blockHashData))
	block := &BlockInfo{
		BlockNumber: s.currentBlock,
		BlockHash:   "0x" + hex.EncodeToString(hash[:]),
		TxCount:     0,
		Timestamp:   time.Now(),
		Txs:         []*RelayedTx{},
	}
	s.blocks = append(s.blocks, block)
	if len(s.blocks) > 50 {
		s.blocks = s.blocks[1:]
	}
	s.BroadcastWS("NEW_HEADER", block)
}

// ------------------------------------------------------------
// HTTP Handlers & Response Helpers
// ------------------------------------------------------------

func JSONResponse(w http.ResponseWriter, status int, success bool, data interface{}, err string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(APIResponse{
		Success: success,
		Data:    data,
		Error:   err,
	})
}

func HandleHealthCheck(w http.ResponseWriter, r *http.Request) {
	JSONResponse(w, http.StatusOK, true, map[string]string{
		"status":    "ONLINE",
		"service":   "Magnum Opus Meta-Relayer Microservice",
		"version":   "2.4.0-release",
		"timestamp": time.Now().Format(time.RFC3339),
	}, "")
}

func HandleMetrics(store *WalletStore) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		metrics := store.GetMetrics()
		JSONResponse(w, http.StatusOK, true, metrics, "")
	}
}

func HandleCreateWallet(store *WalletStore) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var req CreateWalletRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			JSONResponse(w, http.StatusBadRequest, false, nil, "Invalid JSON payload")
			return
		}

		wallet, err := store.CreateWallet(req.Address)
		if err != nil {
			JSONResponse(w, http.StatusBadRequest, false, nil, err.Error())
			return
		}
		JSONResponse(w, http.StatusCreated, true, wallet, "")
	}
}

func HandleGetWallet(store *WalletStore) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		vars := mux.Vars(r)
		address := vars["address"]
		wallet, err := store.GetWallet(address)
		if err != nil {
			JSONResponse(w, http.StatusNotFound, false, nil, err.Error())
			return
		}
		JSONResponse(w, http.StatusOK, true, wallet, "")
	}
}

func HandleListWallets(store *WalletStore) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		wallets := store.GetAllWallets()
		JSONResponse(w, http.StatusOK, true, wallets, "")
	}
}

func HandleTransfer(store *WalletStore) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var req TransferRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			JSONResponse(w, http.StatusBadRequest, false, nil, "Invalid transaction payload")
			return
		}

		tx, err := store.Transfer(&req)
		if err != nil {
			JSONResponse(w, http.StatusBadRequest, false, nil, err.Error())
			return
		}
		JSONResponse(w, http.StatusOK, true, tx, "")
	}
}

func HandleRelayTx(store *WalletStore) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var req RelayTxRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			JSONResponse(w, http.StatusBadRequest, false, nil, "Invalid relay payload")
			return
		}

		tx, err := store.RelayTransaction(&req)
		if err != nil {
			JSONResponse(w, http.StatusBadRequest, false, nil, err.Error())
			return
		}
		JSONResponse(w, http.StatusAccepted, true, tx, "")
	}
}

func HandleGetTx(store *WalletStore) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		vars := mux.Vars(r)
		hash := vars["hash"]
		tx, err := store.GetTxByHash(hash)
		if err != nil {
			JSONResponse(w, http.StatusNotFound, false, nil, err.Error())
			return
		}
		JSONResponse(w, http.StatusOK, true, tx, "")
	}
}

func HandleGetTxHistory(store *WalletStore) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		vars := mux.Vars(r)
		address := vars["address"]
		history := store.GetTxHistory(address)
		JSONResponse(w, http.StatusOK, true, history, "")
	}
}

func HandleGetMempool(store *WalletStore) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		mempool := store.GetMempool()
		JSONResponse(w, http.StatusOK, true, mempool, "")
	}
}

func HandleGetBlocks(store *WalletStore) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		blocks := store.GetBlocks()
		JSONResponse(w, http.StatusOK, true, blocks, "")
	}
}

func HandleWebSocket(store *WalletStore) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		conn, err := upgrader.Upgrade(w, r, nil)
		if err != nil {
			log.Printf("[WS] Upgrade error: %v", err)
			return
		}
		store.RegisterWS(conn)
		defer store.UnregisterWS(conn)

		// Send connection ack
		ack := WebSocketMessage{
			Type:      "CONNECTED",
			Payload:   map[string]string{"message": "Connected to Magnum Opus Web3 Relay Stream"},
			Timestamp: time.Now(),
		}
		conn.WriteJSON(ack)

		for {
			_, _, err := conn.ReadMessage()
			if err != nil {
				break
			}
		}
	}
}

// ------------------------------------------------------------
// Middleware
// ------------------------------------------------------------

func CORSAndSecurityMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS, PUT, DELETE")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization, X-Requested-With")
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("X-Frame-Options", "DENY")
		w.Header().Set("X-XSS-Protection", "1; mode=block")

		if r.Method == "OPTIONS" {
			w.WriteHeader(http.StatusOK)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func RateLimiterMiddleware(store *WalletStore, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !store.limiter.Allow() {
			JSONResponse(w, http.StatusTooManyRequests, false, nil, "Rate limit exceeded")
			return
		}
		atomic.AddUint64(&store.metrics.TotalRequests, 1)
		next.ServeHTTP(w, r)
	})
}

func LoggingMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		next.ServeHTTP(w, r)
		log.Printf("[%s] %s %s - %v", r.Method, r.RequestURI, r.RemoteAddr, time.Since(start))
	})
}

// ------------------------------------------------------------
// Main Service Entrypoint
// ------------------------------------------------------------

func main() {
	log.Println("============================================================")
	log.Println(" MAGNUM OPUS // Web3 Wallet Relay & Microservice Engine")
	log.Println("============================================================")

	store := NewWalletStore()
	store.SeedDemoData()

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	go store.StartMempoolRelayer(ctx)
	go store.StartBlockProducer(ctx)

	r := mux.NewRouter()

	// API Routes
	api := r.PathPrefix("/api/v1").Subrouter()
	api.HandleFunc("/health", HandleHealthCheck).Methods("GET")
	api.HandleFunc("/metrics", HandleMetrics(store)).Methods("GET")
	api.HandleFunc("/wallets", HandleListWallets(store)).Methods("GET")
	api.HandleFunc("/wallets", HandleCreateWallet(store)).Methods("POST")
	api.HandleFunc("/wallets/{address}", HandleGetWallet(store)).Methods("GET")
	api.HandleFunc("/wallets/{address}/history", HandleGetTxHistory(store)).Methods("GET")
	api.HandleFunc("/transfer", HandleTransfer(store)).Methods("POST")
	api.HandleFunc("/relay", HandleRelayTx(store)).Methods("POST")
	api.HandleFunc("/tx/{hash}", HandleGetTx(store)).Methods("GET")
	api.HandleFunc("/mempool", HandleGetMempool(store)).Methods("GET")
	api.HandleFunc("/blocks", HandleGetBlocks(store)).Methods("GET")
	api.HandleFunc("/ws", HandleWebSocket(store))

	// Apply global middleware
	chain := LoggingMiddleware(CORSAndSecurityMiddleware(RateLimiterMiddleware(store, r)))

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	srv := &http.Server{
		Addr:         ":" + port,
		Handler:      chain,
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 15 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, os.Interrupt, syscall.SIGTERM)

	go func() {
		log.Printf("[SERVER] Microservice starting on port %s...", port)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("[SERVER] Listen error: %v", err)
		}
	}()

	<-stop
	log.Println("[SERVER] Shutting down gracefully...")

	shutdownCtx, shutdownCancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer shutdownCancel()

	if err := srv.Shutdown(shutdownCtx); err != nil {
		log.Fatalf("[SERVER] Forced shutdown error: %v", err)
	}

	log.Println("[SERVER] Magnum Opus Relayer service stopped cleanly.")
}
