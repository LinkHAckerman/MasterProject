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
		Address:   "0x000000000000000000000000000000000000dEaD",
		Balance:   make(map[string]float64),
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
	w := &Wallet{
		Address:   address,
		Balance:   make(map[string]float64),
		Nonce:     0,
		CreatedAt: time.Now(),
		UpdatedAt: time.Now(),
	}
	// Initialize zero balances for all supported tokens
	for _, t := range SupportedTokens {
		w.Balance[t] = 0
	}
	s.wallets[address] = w
	atomic.AddUint64(&s.metrics.ActiveWallets, 1)
	return w, nil
}

func (s *WalletStore) GetWallet(address string) (*Wallet, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	w, ok := s.wallets[address]
	return w, ok
}

func (s *WalletStore) recordTx(tx *RelayedTx) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.allTxs[tx.TxHash] = tx
	s.txHistory[tx.From] = append(s.txHistory[tx.From], tx)
	s.txHistory[tx.To] = append(s.txHistory[tx.To], tx)
}

func (s *WalletStore) addToMempool(tx *RelayedTx) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.mempool = append(s.mempool, tx)
	atomic.StoreUint64(&s.metrics.MempoolSize, uint64(len(s.mempool)))
}

func (s *WalletStore) popMempoolBatch(max int) []*RelayedTx {
	s.mu.Lock()
	defer s.mu.Unlock()
	if len(s.mempool) == 0 {
		return nil
	}
	batchSize := max
	if batchSize > len(s.mempool) {
		batchSize = len(s.mempool)
	}
	batch := s.mempool[:batchSize]
	s.mempool = s.mempool[batchSize:]
	atomic.StoreUint64(&s.metrics.MempoolSize, uint64(len(s.mempool)))
	return batch
}

func (s *WalletStore) createBlock(txs []*RelayedTx) *BlockInfo {
	blockNum := atomic.AddUint64(&s.currentBlock, 1)
	prevHash := ""
	if len(s.blocks) > 0 {
		prevHash = s.blocks[len(s.blocks)-1].BlockHash
	}
	// Simple block hash: sha256(prevHash + concatenated tx hashes + timestamp)
	hashInput := prevHash + strconv.FormatInt(time.Now().UnixNano(), 10)
	for _, tx := range txs {
		hashInput += tx.TxHash
	}
	h := sha256.Sum256([]byte(hashInput))
	blockHash := hex.EncodeToString(h[:])

	block := &BlockInfo{
		BlockNumber: blockNum,
		BlockHash:   blockHash,
		TxCount:     len(txs),
		Timestamp:   time.Now(),
		Txs:         txs,
	}
	// Update tx status
	for _, tx := range txs {
		tx.Status = StatusConfirmed
		tx.BlockNum = blockNum
		tx.Timestamp = time.Now()
	}
	s.blocks = append(s.blocks, block)
	return block
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

// ------------------------------------------------------------
// Core Transaction Logic
// ------------------------------------------------------------

func (s *WalletStore) ProcessTransfer(req TransferRequest) (*RelayedTx, error) {
	if !addressRegex.MatchString(req.From) || !addressRegex.MatchString(req.To) {
		return nil, fmt.Errorf("invalid address")
	}
	if !s.isSupportedToken(req.Token) {
		return nil, fmt.Errorf("unsupported token")
	}
	if req.Amount <= 0 {
		return nil, fmt.Errorf("amount must be positive")
	}

	fromW, ok := s.GetWallet(req.From)
	if !ok {
		return nil, fmt.Errorf("sender wallet not found")
	}
	toW, ok := s.GetWallet(req.To)
	if !ok {
		return nil, fmt.Errorf("receiver wallet not found")
	}

	// Simple balance check
	s.mu.Lock()
	if fromW.Balance[req.Token] < req.Amount {
		s.mu.Unlock()
		return nil, fmt.Errorf("insufficient balance")
	}
	fromW.Balance[req.Token] -= req.Amount
	toW.Balance[req.Token] += req.Amount
	fromW.Nonce++
	fromW.UpdatedAt = time.Now()
	toW.UpdatedAt = time.Now()
	s.mu.Unlock()

	tx := &RelayedTx{
		TxHash:    generateTxHash(req.From, req.To, req.Token, req.Amount, time.Now()),
		From:      req.From,
		To:        req.To,
		Token:     strings.ToUpper(req.Token),
		Amount:    req.Amount,
		Fee:       0,
		Nonce:     fromW.Nonce,
		Status:    StatusConfirmed,
		Timestamp: time.Now(),
	}
	s.recordTx(tx)
	atomic.AddUint64(&s.metrics.TotalTransfers, 1)
	return tx, nil
}

func (s *WalletStore) ProcessRelayTx(req RelayTxRequest) (*RelayedTx, error) {
	if !addressRegex.MatchString(req.From) || !addressRegex.MatchString(req.To) {
		return nil, fmt.Errorf("invalid address")
	}
	if !s.isSupportedToken(req.Token) {
		return nil, fmt.Errorf("unsupported token")
	}
	if req.Amount <= 0 {
		return nil, fmt.Errorf("amount must be positive")
	}

	// Placeholder signature verification – in real world you'd verify ECDSA etc.
	if len(req.Signature) == 0 {
		return nil, fmt.Errorf("missing signature")
	}

	// Create a pending transaction and push to mempool
	tx := &RelayedTx{
		TxHash:    generateTxHash(req.From, req.To, req.Token, req.Amount, time.Now()),
		From:      req.From,
		To:        req.To,
		Token:     strings.ToUpper(req.Token),
		Amount:    req.Amount,
		Fee:       req.Fee,
		Nonce:     req.Nonce,
		Signature: req.Signature,
		Status:    StatusPending,
		Timestamp: time.Now(),
	}
	s.recordTx(tx)
	s.addToMempool(tx)
	atomic.AddUint64(&s.metrics.TotalRelayed, 1)
	return tx, nil
}

func generateTxHash(from, to, token string, amount float64, t time.Time) string {
	h := sha256.New()
	payload := fmt.Sprintf("%s|%s|%s|%f|%d", from, to, token, amount, t.UnixNano())
	h.Write([]byte(payload))
	return hex.EncodeToString(h.Sum(nil))
}

// ------------------------------------------------------------
// HTTP Handlers
// ------------------------------------------------------------

func writeJSON(w http.ResponseWriter, status int, resp APIResponse) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(resp)
}

func (s *WalletStore) createWalletHandler(w http.ResponseWriter, r *http.Request) {
	if !s.limiter.Allow() {
		writeJSON(w, http.StatusTooManyRequests, APIResponse{Success: false, Error: "rate limit exceeded"})
		return
	}
	var req CreateWalletRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, APIResponse{Success: false, Error: "invalid json"})
		return
	}
	wallet, err := s.AddWallet(strings.TrimSpace(req.Address))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, APIResponse{Success: false, Error: err.Error()})
		return
	}
	writeJSON(w, http.StatusCreated, APIResponse{Success: true, Data: wallet})
}

func (s *WalletStore) getWalletHandler(w http.ResponseWriter, r *http.Request) {
	if !s.limiter.Allow() {
		writeJSON(w, http.StatusTooManyRequests, APIResponse{Success: false, Error: "rate limit exceeded"})
		return
	}
	addr := mux.Vars(r)["address"]
	wallet, ok := s.GetWallet(addr)
	if !ok {
		writeJSON(w, http.StatusNotFound, APIResponse{Success: false, Error: "wallet not found"})
		return
	}
	writeJSON(w, http.StatusOK, APIResponse{Success: true, Data: wallet})
}

func (s *WalletStore) transferHandler(w http.ResponseWriter, r *http.Request) {
	if !s.limiter.Allow() {
		writeJSON(w, http.StatusTooManyRequests, APIResponse{Success: false, Error: "rate limit exceeded"})
		return
	}
	var req TransferRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, APIResponse{Success: false, Error: "invalid json"})
		return
	}
	tx, err := s.ProcessTransfer(req)
	if err != nil {
		atomic.AddUint64(&s.metrics.FailedTransfers, 1)
		writeJSON(w, http.StatusBadRequest, APIResponse{Success: false, Error: err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, APIResponse{Success: true, Data: tx})
}

func (s *WalletStore) relayTxHandler(w http.ResponseWriter, r *http.Request) {
	if !s.limiter.Allow() {
		writeJSON(w, http.StatusTooManyRequests, APIResponse{Success: false, Error: "rate limit exceeded"})
		return
	}
	var req RelayTxRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, APIResponse{Success: false, Error: "invalid json"})
		return
	}
	tx, err := s.ProcessRelayTx(req)
	if err != nil {
		atomic.AddUint64(&s.metrics.FailedTransfers, 1)
		writeJSON(w, http.StatusBadRequest, APIResponse{Success: false, Error: err.Error()})
		return
	}
	writeJSON(w, http.StatusAccepted, APIResponse{Success: true, Data: tx})
}

func (s *WalletStore) getTxHandler(w http.ResponseWriter, r *http.Request) {
	if !s.limiter.Allow() {
		writeJSON(w, http.StatusTooManyRequests, APIResponse{Success: false, Error: "rate limit exceeded"})
		return
	}
	txHash := mux.Vars(r)["hash"]
	s.mu.RLock()
	tx, ok := s.allTxs[txHash]
	s.mu.RUnlock()
	if !ok {
		writeJSON(w, http.StatusNotFound, APIResponse{Success: false, Error: "transaction not found"})
		return
	}
	writeJSON(w, http.StatusOK, APIResponse{Success: true, Data: tx})
}

func (s *WalletStore) metricsHandler(w http.ResponseWriter, r *http.Request) {
	uptime := uint64(time.Since(s.startTime).Seconds())
	atomic.StoreUint64(&s.metrics.UptimeSeconds, uptime)
	writeJSON(w, http.StatusOK, APIResponse{Success: true, Data: s.metrics})
}

func (s *WalletStore) wsHandler(w http.ResponseWriter, r *http.Request) {
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("WebSocket upgrade error: %v", err)
		return
	}
	s.wsMu.Lock()
	s.wsClients[conn] = true
	s.wsMu.Unlock()

	// Simple read loop to keep connection alive; we ignore messages.
	for {
		if _, _, err := conn.NextReader(); err != nil {
			conn.Close()
			s.wsMu.Lock()
			delete(s.wsClients, conn)
			s.wsMu.Unlock()
			break
		}
	}
}

// ------------------------------------------------------------
// Background Block Miner
// ------------------------------------------------------------

func (s *WalletStore) startMiner(ctx context.Context, interval time.Duration) {
	ticker := time.NewTicker(interval)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			batch := s.popMempoolBatch(10) // up to 10 tx per block
			if len(batch) == 0 {
				continue
			}
			block := s.createBlock(batch)
			msg := WebSocketMessage{Type: "new_block", Payload: block, Timestamp: time.Now()}
			s.broadcastWS(msg)
		}
	}
}

// ------------------------------------------------------------
// Main
// ------------------------------------------------------------

func main() {
	store := NewWalletStore()
	router := mux.NewRouter()

	api := router.PathPrefix("/api/v1").Subrouter()
	api.HandleFunc("/wallet", store.createWalletHandler).Methods("POST")
	api.HandleFunc("/wallet/{address}", store.getWalletHandler).Methods("GET")
	api.HandleFunc("/transfer", store.transferHandler).Methods("POST")
	api.HandleFunc("/relay", store.relayTxHandler).Methods("POST")
	api.HandleFunc("/tx/{hash}", store.getTxHandler).Methods("GET")
	api.HandleFunc("/metrics", store.metricsHandler).Methods("GET")
	router.HandleFunc("/ws", store.wsHandler)

	srv := &http.Server{Addr: ":8080", Handler: router}

	// Graceful shutdown handling
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, os.Interrupt, syscall.SIGTERM)

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	go store.startMiner(ctx, 5*time.Second)

	go func() {
		log.Printf("Server listening on %s", srv.Addr)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("listen error: %v", err)
		}
	}()

	<-stop
	log.Println("Shutting down server...")
	timeoutCtx, cancelTimeout := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancelTimeout()
	if err := srv.Shutdown(timeoutCtx); err != nil {
		log.Fatalf("Server forced to shutdown: %v", err)
	}
	log.Println("Server exited gracefully")
}
