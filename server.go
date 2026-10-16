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
	return w, nil
}

func (s *WalletStore) Transfer(from, to, token string, amount float64) error {
	if amount <= 0 {
		atomic.AddUint64(&s.metrics.FailedTransfers, 1)
		return fmt.Errorf("amount must be positive")
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
		return fmt.Errorf("insufficient balance for token %s", token)
	}

	src.Balance[token] -= amount
	dst.Balance[token] += amount
	src.Nonce++
	src.UpdatedAt = time.Now()
	dst.UpdatedAt = time.Now()

	atomic.AddUint64(&s.metrics.TotalTransfers, 1)
	return nil
}

// RelayTransaction processes a transaction through the mempool and assigns a hash.
func (s *WalletStore) RelayTransaction(from, to, token string, amount, fee float64) (*RelayedTx, error) {
	if amount <= 0 {
		atomic.AddUint64(&s.metrics.FailedTransfers, 1)
		return nil, fmt.Errorf("amount must be positive")
	}

	s.mu.Lock()
	defer s.mu.Unlock()

	src, ok := s.wallets[from]
	if !ok {
		atomic.AddUint64(&s.metrics.FailedTransfers, 1)
		return nil, fmt.Errorf("source wallet not found")
	}
	dst, ok := s.wallets[to]
	if !ok {
		atomic.AddUint64(&s.metrics.FailedTransfers, 1)
		return nil, fmt.Errorf("destination wallet not found")
	}
	if src.Balance[token] < amount+fee {
		atomic.AddUint64(&s.metrics.FailedTransfers, 1)
		return nil, fmt.Errorf("insufficient balance for token %s including fee", token)
	}

	nonce := src.Nonce
	ts := time.Now()
	txHash := computeTxHash(from, to, token, amount, nonce, ts)
	tx := &RelayedTx{
		TxHash:    txHash,
		From:      from,
		To:        to,
		Token:     token,
		Amount:    amount,
		Fee:       fee,
		Nonce:     nonce,
		Status:    StatusPending,
		Timestamp: ts,
	}

	s.mempool = append(s.mempool, tx)
	s.allTxs[txHash] = tx
	s.txHistory[from] = append(s.txHistory[from], tx)
	s.txHistory[to] = append(s.txHistory[to], tx)

	atomic.AddUint64(&s.metrics.TotalRelayed, 1)
	return tx, nil
}

// ConfirmTransaction marks a pending transaction as confirmed and updates balances.
func (s *WalletStore) ConfirmTransaction(txHash string) (*RelayedTx, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	tx, ok := s.allTxs[txHash]
	if !ok {
		return nil, fmt.Errorf("transaction not found")
	}
	if tx.Status != StatusPending {
		return nil, fmt.Errorf("transaction already processed")
	}
	src, ok := s.wallets[tx.From]
	if !ok {
		return nil, fmt.Errorf("source wallet not found")
	}
	dst, ok := s.wallets[tx.To]
	if !ok {
		return nil, fmt.Errorf("destination wallet not found")
	}
	src.Balance[tx.Token] -= tx.Amount + tx.Fee
	dst.Balance[tx.Token] += tx.Amount
	src.Nonce++
	src.UpdatedAt = time.Now()
	dst.UpdatedAt = time.Now()
	s.currentBlock++
	tx.Status = StatusConfirmed
	tx.BlockNum = s.currentBlock
	return tx, nil
}

// FailTransaction marks a pending transaction as failed.
func (s *WalletStore) FailTransaction(txHash, errorMsg string) (*RelayedTx, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	tx, ok := s.allTxs[txHash]
	if !ok {
		return nil, fmt.Errorf("transaction not found")
	}
	if tx.Status != StatusPending {
		return nil, fmt.Errorf("transaction already processed")
	}
	tx.Status = StatusFailed
	tx.ErrorMsg = errorMsg
	atomic.AddUint64(&s.metrics.FailedTransfers, 1)
	return tx, nil
}

// ProcessMempool attempts to confirm all pending transactions in the mempool.
func (s *WalletStore) ProcessMempool() {
	s.mu.Lock()
	defer s.mu.Unlock()
	for _, tx := range s.mempool {
		if tx.Status == StatusPending {
			src, ok := s.wallets[tx.From]
			if !ok {
				tx.Status = StatusFailed
				tx.ErrorMsg = "source wallet not found"
				continue
			}
			dst, ok := s.wallets[tx.To]
			if !ok {
				tx.Status = StatusFailed
				tx.ErrorMsg = "destination wallet not found"
				continue
			}
			if src.Balance[tx.Token] < tx.Amount+tx.Fee {
				tx.Status = StatusFailed
				tx.ErrorMsg = "insufficient balance"
				continue
			}
			src.Balance[tx.Token] -= tx.Amount + tx.Fee
			dst.Balance[tx.Token] += tx.Amount
			src.Nonce++
			src.UpdatedAt = time.Now()
			dst.UpdatedAt = time.Now()
			s.currentBlock++
			tx.Status = StatusConfirmed
			tx.BlockNum = s.currentBlock
		}
	}
	s.mempool = make([]*RelayedTx, 0)
}

// GetTransactionHistory returns the transaction history for a given address.
func (s *WalletStore) GetTransactionHistory(address string) []*RelayedTx {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.txHistory[address]
}

// GetMempool returns the current mempool of pending transactions.
func (s *WalletStore) GetMempool() []*RelayedTx {
	s.mu.RLock()
	defer s.mu.RUnlock()
	result := make([]*RelayedTx, len(s.mempool))
	copy(result, s.mempool)
	return result
}

// GetMetrics returns the current metrics snapshot.
func (s *WalletStore) GetMetrics() Metrics {
	return Metrics{
		TotalRequests:   atomic.LoadUint64(&s.metrics.TotalRequests),
		TotalTransfers:  atomic.LoadUint64(&s.metrics.TotalTransfers),
		TotalRelayed:    atomic.LoadUint64(&s.metrics.TotalRelayed),
		FailedTransfers: atomic.LoadUint64(&s.metrics.FailedTransfers),
	}
}

// GetBlockNumber returns the current simulated block number.
func (s *WalletStore) GetBlockNumber() uint64 {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.currentBlock
}

// isValidAddress checks if a string is a valid Ethereum-style address.
var addressRegex = regexp.MustCompile(`^0x[a-fA-F0-9]{40}$`)

func isValidAddress(addr string) bool {
	return addressRegex.MatchString(addr)
}

// isValidToken checks if a token is supported.
func isValidToken(token string) bool {
	for _, t := range SupportedTokens {
		if t == token {
			return true
		}
	}
	return false
}

// HTTP Handlers

func (s *WalletStore) handleCreateWallet(w http.ResponseWriter, r *http.Request) {
	atomic.AddUint64(&s.metrics.TotalRequests, 1)
	var req struct {
		Address string `json:"address"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	if !isValidAddress(req.Address) {
		http.Error(w, "invalid wallet address format", http.StatusBadRequest)
		return
	}
	wallet, err := s.Create(req.Address)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(wallet)
}

func (s *WalletStore) handleGetWallet(w http.ResponseWriter, r *http.Request) {
	atomic.AddUint64(&s.metrics.TotalRequests, 1)
	vars := mux.Vars(r)
	address := vars["address"]
	if !isValidAddress(address) {
		http.Error(w, "invalid wallet address format", http.StatusBadRequest)
		return
	}
	wallet, ok := s.Get(address)
	if !ok {
		http.Error(w, "wallet not found", http.StatusNotFound)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(wallet)
}

func (s *WalletStore) handleTransfer(w http.ResponseWriter, r *http.Request) {
	atomic.AddUint64(&s.metrics.TotalRequests, 1)
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
	if !isValidAddress(req.From) || !isValidAddress(req.To) {
		http.Error(w, "invalid wallet address format", http.StatusBadRequest)
		return
	}
	if !isValidToken(req.Token) {
		http.Error(w, "unsupported token", http.StatusBadRequest)
		return
	}
	err := s.Transfer(req.From, req.To, req.Token, req.Amount)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "success"})
}

func (s *WalletStore) handleRelayTransaction(w http.ResponseWriter, r *http.Request) {
	atomic.AddUint64(&s.metrics.TotalRequests, 1)
	var req struct {
		From   string  `json:"from"`
		To     string  `json:"to"`
		Token  string  `json:"token"`
		Amount Float64String `json:"amount"`
		Fee    Float64String `json:"fee"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	if !isValidAddress(req.From) || !isValidAddress(req.To) {
		http.Error(w, "invalid wallet address format", http.StatusBadRequest)
		return
	}
	if !isValidToken(req.Token) {
		http.Error(w, "unsupported token", http.StatusBadRequest)
		return
	}
	tx, err := s.RelayTransaction(req.From, req.To, req.Token, float64(req.Amount), float64(req.Fee))
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(tx)
}

func (s *WalletStore) handleConfirmTransaction(w http.ResponseWriter, r *http.Request) {
	atomic.AddUint64(&s.metrics.TotalRequests, 1)
	vars := mux.Vars(r)
	txHash := vars["txHash"]
	tx, err := s.ConfirmTransaction(txHash)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(tx)
}

func (s *WalletStore) handleFailTransaction(w http.ResponseWriter, r *http.Request) {
	atomic.AddUint64(&s.metrics.TotalRequests, 1)
	var req struct {
		TxHash   string `json:"tx_hash"`
		ErrorMsg string `json:"error_msg"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	tx, err := s.FailTransaction(req.TxHash, req.ErrorMsg)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(tx)
}

func (s *WalletStore) handleGetTransaction(w http.ResponseWriter, r *http.Request) {
	atomic.AddUint64(&s.metrics.TotalRequests, 1)
	vars := mux.Vars(r)
	txHash := vars["txHash"]
	s.mu.RLock()
	tx, ok := s.allTxs[txHash]
	s.mu.RUnlock()
	if !ok {
		http.Error(w, "transaction not found", http.StatusNotFound)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(tx)
}

func (s *WalletStore) handleGetTransactionHistory(w http.ResponseWriter, r *http.Request) {
	atomic.AddUint64(&s.metrics.TotalRequests, 1)
	vars := mux.Vars(r)
	address := vars["address"]
	if !isValidAddress(address) {
		http.Error(w, "invalid wallet address format", http.StatusBadRequest)
		return
	}
	history := s.GetTransactionHistory(address)
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(history)
}

func (s *WalletStore) handleGetMempool(w http.ResponseWriter, r *http.Request) {
	atomic.AddUint64(&s.metrics.TotalRequests, 1)
	mempool := s.GetMempool()
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(mempool)
}

func (s *WalletStore) handleGetMetrics(w http.ResponseWriter, r *http.Request) {
	atomic.AddUint64(&s.metrics.TotalRequests, 1)
	metrics := s.GetMetrics()
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(metrics)
}

func (s *WalletStore) handleGetBlockNumber(w http.ResponseWriter, r *http.Request) {
	atomic.AddUint64(&s.metrics.TotalRequests, 1)
	blockNum := s.GetBlockNumber()
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]uint64{"block_number": blockNum})
}

func (s *WalletStore) handleProcessMempool(w http.ResponseWriter, r *http.Request) {
	atomic.AddUint64(&s.metrics.TotalRequests, 1)
	s.ProcessMempool()
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "mempool processed"})
}

// Float64String is a helper type for JSON decoding of float64 values that may arrive as strings.
type Float64String float64

func (f *Float64String) UnmarshalJSON(data []byte) error {
	// Handle both numeric and string representations
	str := strings.Trim(string(data), `"`)
	val, err := strconv.ParseFloat(str, 64)
	if err != nil {
		return err
	}
	*f = Float64String(val)
	return nil
}

func main() {
	store := NewWalletStore()

	// Start background mempool processor
	go func() {
		ticker := time.NewTicker(5 * time.Second)
		defer ticker.Stop()
		for range ticker.C {
			store.ProcessMempool()
		}
	}()

	r := mux.NewRouter()

	// Wallet routes
	r.HandleFunc("/wallets", store.handleCreateWallet).Methods("POST")
	r.HandleFunc("/wallets/{address}", store.handleGetWallet).Methods("GET")

	// Transfer route
	r.HandleFunc("/transfer", store.handleTransfer).Methods("POST")

	// Transaction routes
	r.HandleFunc("/transactions/relay", store.handleRelayTransaction).Methods("POST")
	r.HandleFunc("/transactions/confirm/{txHash}", store.handleConfirmTransaction).Methods("POST")
	r.HandleFunc("/transactions/fail", store.handleFailTransaction).Methods("POST")
	r.HandleFunc("/transactions/{txHash}", store.handleGetTransaction).Methods("GET")
	r.HandleFunc("/transactions/history/{address}", store.handleGetTransactionHistory).Methods("GET")
	r.HandleFunc("/transactions/mempool", store.handleGetMempool).Methods("GET")
	r.HandleFunc("/transactions/process", store.handleProcessMempool).Methods("POST")

	// Metrics and block routes
	r.HandleFunc("/metrics", store.handleGetMetrics).Methods("GET")
	r.HandleFunc("/block", store.handleGetBlockNumber).Methods("GET")

	// Health check
	r.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
	}).Methods("GET")

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	addr := ":" + port
	server := &http.Server{
		Addr:    addr,
		Handler: r,
	}

	// Graceful shutdown
	go func() {
		log.Printf("Server starting on %s", addr)
		if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("Server error: %v", err)
		}
	}()

	// Wait for interrupt signal
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit
	log.Println("Shutting down server...")

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := server.Shutdown(ctx); err != nil {
		log.Fatalf("Server forced to shutdown: %v", err)
	}
	log.Println("Server exiting")
}
