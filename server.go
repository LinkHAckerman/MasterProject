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

// RelayedTx models an on-chain or meta‑transaction handled by the relay microservice.
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

// Metrics tracks real‑time telemetry of the microservice.
type Metrics struct {
	TotalRequests   uint64 `json:"total_requests"`
	TotalTransfers  uint64 `json:"total_transfers"`
	TotalRelayed    uint64 `json:"total_relayed"`
	FailedTransfers uint64 `json:"failed_transfers"`
	ActiveWallets   uint64 `json:"active_wallets"`
	MempoolSize     uint64 `json:"mempool_size"`
	UptimeSeconds   uint64 `json:"uptime_seconds"`
}

// WebSocketMessage represents a real‑time update pushed to clients.
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

	// Seed the relayer gas‑station wallet
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
	// Simple Ethereum‑style address validation (0x + 40 hex chars)
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
// Wallet Operations
// ------------------------------------------------------------

func (s *WalletStore) Get(address string) (*Wallet, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	w, ok := s.wallets[address]
	if !ok {
		return nil, false
	}
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

	newWallet := &Wallet{
		Address:   address,
		Balance:   make(map[string]float64),
		Nonce:     0,
		CreatedAt: time.Now(),
		UpdatedAt: time.Now(),
	}
	// Initialise zero balance for each supported token
	for _, t := range SupportedTokens {
		newWallet.Balance[t] = 0.0
	}
	s.wallets[address] = newWallet
	atomic.AddUint64(&s.metrics.ActiveWallets, 1)
	return newWallet, nil
}

// ------------------------------------------------------------
// Transaction Lifecycle
// ------------------------------------------------------------

func (s *WalletStore) SubmitTx(from, to, token string, amount float64, signature string) (*RelayedTx, error) {
	if !isSupportedToken(token) {
		return nil, fmt.Errorf("unsupported token %s", token)
	}

	// Basic validation of wallets
	src, ok := s.Get(from)
	if !ok {
		return nil, fmt.Errorf("source wallet not found")
	}
	dst, ok := s.Get(to)
	if !ok {
		return nil, fmt.Errorf("destination wallet not found")
	}

	if amount <= 0 {
		return nil, fmt.Errorf("amount must be positive")
	}

	// Simulated fee: 0.1% of amount, minimum 0.0001
	fee := amount * 0.001
	if fee < 0.0001 {
		fee = 0.0001
	}

	if src.Balance[token] < amount+fee {
		return nil, fmt.Errorf("insufficient balance")
	}

	// Nonce check – must match current nonce of source wallet
	s.mu.Lock()
	if src.Nonce != s.wallets[from].Nonce {
		// This should never happen because Get returns a copy, but we double‑check
		s.mu.Unlock()
		return nil, fmt.Errorf("nonce mismatch")
	}
	nonce := s.wallets[from].Nonce
	// Increment nonce pre‑emptively
	s.wallets[from].Nonce++
	s.mu.Unlock()

	// Create transaction object
	tx := &RelayedTx{
		From:      from,
		To:        to,
		Token:     token,
		Amount:    amount,
		Fee:       fee,
		Nonce:     nonce,
		Signature: signature,
		Status:    StatusPending,
		Timestamp: time.Now(),
	}
	tx.TxHash = computeTxHash(from, to, token, amount, nonce, tx.Timestamp)

	// Store transaction
	s.mu.Lock()
	s.allTxs[tx.TxHash] = tx
	s.txHistory[from] = append(s.txHistory[from], tx)
	s.txHistory[to] = append(s.txHistory[to], tx)
	s.mempool = append(s.mempool, tx)
	atomic.AddUint64(&s.metrics.TotalTransfers, 1)
	atomic.AddUint64(&s.metrics.MempoolSize, 1)
	s.mu.Unlock()

	return tx, nil
}

func (s *WalletStore) processMempoolTx(tx *RelayedTx) {
	// Simulate processing delay
	time.Sleep(time.Duration(rand.Intn(200)+100) * time.Millisecond)

	// Random failure simulation (5% chance)
	if rand.Float64() < 0.05 {
		tx.Status = StatusFailed
		tx.ErrorMsg = "simulated network error"
		atomic.AddUint64(&s.metrics.FailedTransfers, 1)
		return
	}

	// Apply balances atomically
	s.mu.Lock()
	defer s.mu.Unlock()

	src := s.wallets[tx.From]
	dst := s.wallets[tx.To]

	// Deduct amount + fee from source
	src.Balance[tx.Token] -= tx.Amount + tx.Fee
	// Credit amount to destination
	dst.Balance[tx.Token] += tx.Amount
	// Credit fee to relayer (dead address) – already has huge balance, ignore

	// Update timestamps
	src.UpdatedAt = time.Now()
	dst.UpdatedAt = time.Now()

	tx.Status = StatusConfirmed
	tx.BlockNum = s.currentBlock
	tx.Timestamp = time.Now()

	atomic.AddUint64(&s.metrics.TotalRelayed, 1)
}

func (s *WalletStore) mempoolProcessor() {
	for {
		time.Sleep(500 * time.Millisecond)
		s.mu.Lock()
		if len(s.mempool) == 0 {
			s.mu.Unlock()
			continue
		}
		// Take a snapshot of current mempool and clear it
		batch := s.mempool
		s.mempool = make([]*RelayedTx, 0)
		atomic.StoreUint64(&s.metrics.MempoolSize, 0)
		s.mu.Unlock()

		for _, tx := range batch {
			if tx.Status != StatusPending {
				continue
			}
			// Process transaction
			s.processMempoolTx(tx)
			// Broadcast result via WebSocket
			s.broadcastWS(WebSocketMessage{Type: "tx_update", Payload: tx, Timestamp: time.Now()})
		}
	}
}

func (s *WalletStore) blockProducer() {
	ticker := time.NewTicker(5 * time.Second)
	defer ticker.Stop()
	for range ticker.C {
		atomic.AddUint64(&s.currentBlock, 1)
	}
}

func (s *WalletStore) metricsUpdater() {
	ticker := time.NewTicker(1 * time.Second)
	defer ticker.Stop()
	for range ticker.C {
		uptime := uint64(time.Since(s.startTime).Seconds())
		atomic.StoreUint64(&s.metrics.UptimeSeconds, uptime)
	}
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
// HTTP Handlers
// ------------------------------------------------------------

var store = NewWalletStore()

func rateLimit(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !store.limiter.Allow() {
			http.Error(w, "rate limit exceeded", http.StatusTooManyRequests)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func jsonResponse(w http.ResponseWriter, data interface{}) {
	w.Header().Set("Content-Type", "application/json")
	enc := json.NewEncoder(w)
	enc.SetEscapeHTML(false)
	if err := enc.Encode(data); err != nil {
		log.Printf("failed to encode json response: %v", err)
	}
}

func createWalletHandler(w http.ResponseWriter, r *http.Request) {
	type req struct { Address string `json:"address"` }
	var payload req
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		http.Error(w, "invalid json", http.StatusBadRequest)
		return
	}
	wallet, err := store.Create(strings.TrimSpace(payload.Address))
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	jsonResponse(w, wallet)
}

func getWalletHandler(w http.ResponseWriter, r *http.Request) {
	addr := mux.Vars(r)["address"]
	wallet, ok := store.Get(addr)
	if !ok {
		http.Error(w, "wallet not found", http.StatusNotFound)
		return
	}
	jsonResponse(w, wallet)
}

func submitTxHandler(w http.ResponseWriter, r *http.Request) {
	type req struct {
		From      string  `json:"from"`
		To        string  `json:"to"`
		Token     string  `json:"token"`
		Amount    float64 `json:"amount"`
		Signature string  `json:"signature,omitempty"`
	}
	var payload req
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		http.Error(w, "invalid json", http.StatusBadRequest)
		return
	}
	tx, err := store.SubmitTx(strings.TrimSpace(payload.From), strings.TrimSpace(payload.To), strings.TrimSpace(payload.Token), payload.Amount, payload.Signature)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	jsonResponse(w, tx)
}

func getTxHandler(w http.ResponseWriter, r *http.Request) {
	hash := mux.Vars(r)["hash"]
	store.mu.RLock()
	tx, ok := store.allTxs[hash]
	store.mu.RUnlock()
	if !ok {
		http.Error(w, "transaction not found", http.StatusNotFound)
		return
	}
	jsonResponse(w, tx)
}

func metricsHandler(w http.ResponseWriter, r *http.Request) {
	store.mu.RLock()
	m := store.metrics
	store.mu.RUnlock()
	jsonResponse(w, m)
}

var upgrader = websocket.Upgrader{CheckOrigin: func(r *http.Request) bool { return true }}

func wsHandler(w http.ResponseWriter, r *http.Request) {
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("websocket upgrade failed: %v", err)
		return
	}
	store.wsMu.Lock()
	store.wsClients[conn] = true
	store.wsMu.Unlock()

	// Simple read loop to keep connection alive; we ignore incoming messages.
	for {
		if _, _, err := conn.NextReader(); err != nil {
			conn.Close()
			store.wsMu.Lock()
			delete(store.wsClients, conn)
			store.wsMu.Unlock()
			break
		}
	}
}

func routes() http.Handler {
	r := mux.NewRouter()
	r.Use(rateLimit)

	api := r.PathPrefix("/api").Subrouter()
	api.HandleFunc("/wallet", createWalletHandler).Methods("POST")
	api.HandleFunc("/wallet/{address}", getWalletHandler).Methods("GET")
	api.HandleFunc("/tx", submitTxHandler).Methods("POST")
	api.HandleFunc("/tx/{hash}", getTxHandler).Methods("GET")
	api.HandleFunc("/metrics", metricsHandler).Methods("GET")

	r.HandleFunc("/ws", wsHandler)

	return r
}

func main() {
	port := "8080"
	if p := os.Getenv("PORT"); p != "" {
		port = p
	}

	srv := &http.Server{Addr: ":" + port, Handler: routes()}

	go func() {
		log.Printf("Magnum Opus relay service listening on %s", port)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("listen: %s", err)
		}
	}()

	// Graceful shutdown handling
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit
	log.Println("Shutting down server…")

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := srv.Shutdown(ctx); err != nil {
		log.Fatalf("Server forced to shutdown: %v", err)
	}
	log.Println("Server exiting")
}
