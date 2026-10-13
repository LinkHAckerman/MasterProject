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
		return fmt.Errorf("insufficient funds: balance is %.4f %s, requested %.4f", src.Balance[token], token, amount)
	}

	// Execute transfer
	src.Balance[token] -= amount
	dst.Balance[token] += amount
	src.Nonce++
	src.UpdatedAt = time.Now()
	dst.UpdatedAt = time.Now()

	// Record Transaction
	now := time.Now()
	tx := &RelayedTx{
		TxHash:    computeTxHash(from, to, token, amount, src.Nonce, now),
		From:      from,
		To:        to,
		Token:     token,
		Amount:    amount,
		Fee:       0.001,
		Nonce:     src.Nonce,
		Status:    StatusConfirmed,
		Timestamp: now,
		BlockNum:  s.currentBlock,
	}

	s.allTxs[tx.TxHash] = tx
	s.txHistory[from] = append(s.txHistory[from], tx)
	s.txHistory[to] = append(s.txHistory[to], tx)

	atomic.AddUint64(&s.metrics.TotalTransfers, 1)
	return nil
}

// RelayTransaction processes gas-abstracted meta-transactions.
func (s *WalletStore) RelayTransaction(txReq *RelayedTx) (*RelayedTx, error) {
	if txReq.Amount <= 0 {
		return nil, fmt.Errorf("transfer amount must be strictly positive")
	}

	s.mu.Lock()
	defer s.mu.Unlock()

	src, ok := s.wallets[txReq.From]
	if !ok {
		return nil, fmt.Errorf("sender wallet does not exist")
	}
	dst, ok := s.wallets[txReq.To]
	if !ok {
		return nil, fmt.Errorf("recipient wallet does not exist")
	}

	// Verify nonce to prevent replay attacks
	if txReq.Nonce != src.Nonce+1 {
		return nil, fmt.Errorf("nonce mismatch: expected %d, got %d", src.Nonce+1, txReq.Nonce)
	}

	totalDeduction := txReq.Amount + txReq.Fee
	if src.Balance[txReq.Token] < totalDeduction {
		return nil, fmt.Errorf("insufficient balance for amount + fee: needed %.4f %s, have %.4f", totalDeduction, txReq.Token, src.Balance[txReq.Token])
	}

	src.Balance[txReq.Token] -= totalDeduction
	dst.Balance[txReq.Token] += txReq.Amount
	src.Nonce++
	src.UpdatedAt = time.Now()
	dst.UpdatedAt = time.Now()

	now := time.Now()
	hash := computeTxHash(txReq.From, txReq.To, txReq.Token, txReq.Amount, txReq.Nonce, now)
	relayed := &RelayedTx{
		TxHash:    hash,
		From:      txReq.From,
		To:        txReq.To,
		Token:     txReq.Token,
		Amount:    txReq.Amount,
		Fee:       txReq.Fee,
		Nonce:     txReq.Nonce,
		Signature: txReq.Signature,
		Status:    StatusRelayed,
		Timestamp: now,
		BlockNum:  s.currentBlock,
	}

	s.mempool = append(s.mempool, relayed)
	s.allTxs[hash] = relayed
	s.txHistory[txReq.From] = append(s.txHistory[txReq.From], relayed)
	s.txHistory[txReq.To] = append(s.txHistory[txReq.To], relayed)

	atomic.AddUint64(&s.metrics.TotalRelayed, 1)
	return relayed, nil
}

func (s *WalletStore) Faucet(address, token string, amount float64) error {
	if amount <= 0 || amount > 10000 {
		return fmt.Errorf("drip amount must be between 0 and 10000")
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	wallet, ok := s.wallets[address]
	if !ok {
		return fmt.Errorf("wallet not found")
	}
	wallet.Balance[token] += amount
	wallet.UpdatedAt = time.Now()
	return nil
}

func (s *WalletStore) GetTransactions(address string) []*RelayedTx {
	s.mu.RLock()
	defer s.mu.RUnlock()
	txs := s.txHistory[address]
	result := make([]*RelayedTx, len(txs))
	copy(result, txs)
	return result
}

func (s *WalletStore) GetTxByHash(hash string) (*RelayedTx, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	tx, ok := s.allTxs[hash]
	return tx, ok
}

// MempoolWorker confirms relayed transactions periodically in background.
func (s *WalletStore) StartMempoolWorker(ctx context.Context) {
	ticker := time.NewTicker(2 * time.Second)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			s.mu.Lock()
			s.currentBlock++
			if len(s.mempool) > 0 {
				for _, tx := range s.mempool {
					tx.Status = StatusConfirmed
					tx.BlockNum = s.currentBlock
				}
				s.mempool = s.mempool[:0]
			}
			s.mu.Unlock()
		}
	}
}

// HTTP Handlers

func getWalletHandler(store *WalletStore) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		vars := mux.Vars(r)
		address := vars["address"]
		wallet, ok := store.Get(address)
		if !ok {
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "wallet not found"})
			return
		}
		writeJSON(w, http.StatusOK, wallet)
	}
}

func createWalletHandler(store *WalletStore) http.HandlerFunc {
	type req struct {
		Address string `json:"address"`
	}
	return func(w http.ResponseWriter, r *http.Request) {
		var payload req
		if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
			// If empty or invalid, generate random address
			randBytes := make([]byte, 20)
			rand.Read(randBytes)
			payload.Address = "0x" + hex.EncodeToString(randBytes)
		}
		if strings.TrimSpace(payload.Address) == "" {
			randBytes := make([]byte, 20)
			rand.Read(randBytes)
			payload.Address = "0x" + hex.EncodeToString(randBytes)
		}
		wallet, err := store.Create(payload.Address)
		if err != nil {
			writeJSON(w, http.StatusConflict, map[string]string{"error": err.Error()})
			return
		}
		writeJSON(w, http.StatusCreated, wallet)
	}
}

func transferHandler(store *WalletStore) http.HandlerFunc {
	type req struct {
		To     string  `json:"to"`
		Token  string  `json:"token"`
		Amount float64 `json:"amount"`
	}
	return func(w http.ResponseWriter, r *http.Request) {
		vars := mux.Vars(r)
		from := vars["address"]
		var payload req
		if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid json payload"})
			return
		}
		if payload.Token == "" {
			payload.Token = "OPUS"
		}
		if err := store.Transfer(from, payload.To, payload.Token, payload.Amount); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
			return
		}
		w.WriteHeader(http.StatusNoContent)
	}
}

func relayHandler(store *WalletStore) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var txReq RelayedTx
		if err := json.NewDecoder(r.Body).Decode(&txReq); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "malformed relay transaction"})
			return
		}
		if txReq.Token == "" {
			txReq.Token = "OPUS"
		}
		if txReq.Fee <= 0 {
			txReq.Fee = 0.0005
		}
		relayed, err := store.RelayTransaction(&txReq)
		if err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
			return
		}
		writeJSON(w, http.StatusAccepted, relayed)
	}
}

func faucetHandler(store *WalletStore) http.HandlerFunc {
	type req struct {
		Token  string  `json:"token"`
		Amount float64 `json:"amount"`
	}
	return func(w http.ResponseWriter, r *http.Request) {
		vars := mux.Vars(r)
		address := vars["address"]
		var payload req
		if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
			payload.Token = "OPUS"
			payload.Amount = 50.0
		}
		if payload.Token == "" {
			payload.Token = "OPUS"
		}
		if payload.Amount <= 0 {
			payload.Amount = 50.0
		}
		if err := store.Faucet(address, payload.Token, payload.Amount); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
			return
		}
		wallet, _ := store.Get(address)
		writeJSON(w, http.StatusOK, map[string]interface{}{
			"message": fmt.Sprintf("Dispensed %.2f %s to %s", payload.Amount, payload.Token, address),
			"wallet":  wallet,
		})
	}
}

func historyHandler(store *WalletStore) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		vars := mux.Vars(r)
		address := vars["address"]
		txs := store.GetTransactions(address)
		writeJSON(w, http.StatusOK, map[string]interface{}{
			"address":      address,
			"count":        len(txs),
			"transactions": txs,
		})
	}
}

func txLookupHandler(store *WalletStore) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		vars := mux.Vars(r)
		hash := vars["hash"]
		tx, ok := store.GetTxByHash(hash)
		if !ok {
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "transaction hash not found"})
			return
		}
		writeJSON(w, http.StatusOK, tx)
	}
}

func healthHandler(store *WalletStore) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		store.mu.RLock()
		walletCount := len(store.wallets)
		mempoolDepth := len(store.mempool)
		block := store.currentBlock
		uptime := time.Since(store.startTime).Truncate(time.Second).String()
		store.mu.RUnlock()

		status := map[string]interface{}{
			"status":         "OK",
			"service":        "MagnumOpus-Relay-Engine",
			"version":        "2.4.0",
			"uptime":         uptime,
			"block_height":   block,
			"active_wallets": walletCount,
			"mempool_depth":  mempoolDepth,
			"network":        "MagnumOpus-Mainnet-Beta",
		}
		writeJSON(w, http.StatusOK, status)
	}
}

func metricsHandler(store *WalletStore) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		metrics := map[string]interface{}{
			"total_requests":   atomic.LoadUint64(&store.metrics.TotalRequests),
			"total_transfers":  atomic.LoadUint64(&store.metrics.TotalTransfers),
			"total_relayed":    atomic.LoadUint64(&store.metrics.TotalRelayed),
			"failed_transfers": atomic.LoadUint64(&store.metrics.FailedTransfers),
		}
		writeJSON(w, http.StatusOK, metrics)
	}
}

func writeJSON(w http.ResponseWriter, code int, payload interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	json.NewEncoder(w).Encode(payload)
}

// Middlewares

func loggingMiddleware(store *WalletStore) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			atomic.AddUint64(&store.metrics.TotalRequests, 1)
			start := time.Now()
			next.ServeHTTP(w, r)
			log.Printf("[%s] %s %s - %v", r.Method, r.RequestURI, r.RemoteAddr, time.Since(start))
		})
	}
}

func corsMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS, PUT, DELETE")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization, X-Requested-With")
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func main() {
	store := NewWalletStore()

	ctx, cancelMempool := context.WithCancel(context.Background())
	defer cancelMempool()
	go store.StartMempoolWorker(ctx)

	r := mux.NewRouter()
	r.Use(loggingMiddleware(store), corsMiddleware)

	// Core & Relaying APIs
	r.HandleFunc("/health", healthHandler(store)).Methods("GET")
	r.HandleFunc("/metrics", metricsHandler(store)).Methods("GET")
	r.HandleFunc("/wallet", createWalletHandler(store)).Methods("POST")
	r.HandleFunc("/wallet/{address}", getWalletHandler(store)).Methods("GET")
	r.HandleFunc("/wallet/{address}/transfer", transferHandler(store)).Methods("POST")
	r.HandleFunc("/wallet/{address}/faucet", faucetHandler(store)).Methods("POST")
	r.HandleFunc("/wallet/{address}/history", historyHandler(store)).Methods("GET")
	r.HandleFunc("/relay", relayHandler(store)).Methods("POST")
	r.HandleFunc("/tx/{hash}", txLookupHandler(store)).Methods("GET")

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	srv := &http.Server{
		Addr:         ":" + port,
		Handler:      r,
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 10 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	go func() {
		log.Printf("⚡ Magnum Opus Relay & Microservice Engine active on :%s", port)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("fatal server error: %v", err)
		}
	}()

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	log.Println("Gracefully shutting down Magnum Opus Relay Engine...")
	shutdownCtx, cancelShutdown := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancelShutdown()
	if err := srv.Shutdown(shutdownCtx); err != nil {
		log.Fatalf("forced shutdown error: %v", err)
	}
	log.Println("Server cleanly exited")
}
