package main

import (
	"encoding/json"
	"log"
	"math/rand"
	"net/http"
	"sync"
	"time"

	"github.com/google/uuid"
)

// Transaction represents a simplified blockchain transaction.
type Transaction struct {
	ID        string    `json:"id"`
	From      string    `json:"from"`
	To        string    `json:"to"`
	Amount    float64   `json:"amount"`
	ChainID   string    `json:"chainId"`
	Status    string    `json:"status"` // pending, confirmed, failed
	Timestamp time.Time `json:"timestamp"`
}

// TransactionRequest is the payload accepted from clients.
type TransactionRequest struct {
	From    string  `json:"from"`
	To      string  `json:"to"`
	Amount  float64 `json:"amount"`
	ChainID string  `json:"chainId"`
}

// TransactionResponse is returned after a transaction is accepted.
type TransactionResponse struct {
	ID     string `json:"id"`
	Status string `json:"status"`
}

// Server holds in‑memory transaction state.
type Server struct {
	mu  sync.RWMutex
	txs map[string]*Transaction
}

func NewServer() *Server {
	return &Server{txs: make(map[string]*Transaction)}
}

// validateAddress performs a very light check on an address string.
func validateAddress(addr string) bool {
	// Simple regex: 0x followed by 40 hex chars.
	const pattern = `^0x[0-9a-fA-F]{40}$`
	matched, _ := regexp.MatchString(pattern, addr)
	return matched
}

func (s *Server) handleRelay(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req TransactionRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "invalid json payload", http.StatusBadRequest)
		return
	}

	// Basic validation
	if !validateAddress(req.From) || !validateAddress(req.To) {
		http.Error(w, "invalid address format", http.StatusBadRequest)
		return
	}
	if req.Amount <= 0 {
		http.Error(w, "amount must be positive", http.StatusBadRequest)
		return
	}
	if req.ChainID == "" {
		http.Error(w, "chainId required", http.StatusBadRequest)
		return
	}

	tx := &Transaction{
		ID:        uuid.NewString(),
		From:      req.From,
		To:        req.To,
		Amount:    req.Amount,
		ChainID:   req.ChainID,
		Status:    "pending",
		Timestamp: time.Now().UTC(),
	}

	// Store transaction
	s.mu.Lock()
	s.txs[tx.ID] = tx
	s.mu.Unlock()

	// Simulate async processing
	go s.processTransaction(tx.ID)

	resp := TransactionResponse{ID: tx.ID, Status: tx.Status}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(resp)
}

func (s *Server) processTransaction(id string) {
	// Random processing time between 1‑3 seconds
	delay := time.Duration(1+rand.Intn(3)) * time.Second
	time.Sleep(delay)

	s.mu.Lock()
	defer s.mu.Unlock()
	if tx, ok := s.txs[id]; ok {
		// In a real implementation we would verify signatures, nonce, etc.
		// Here we simply mark as confirmed.
		tx.Status = "confirmed"
	}
}

func (s *Server) handleGetTx(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	id := r.URL.Path[len("/tx/"):]
	if id == "" {
		http.Error(w, "transaction id required", http.StatusBadRequest)
		return
	}

	s.mu.RLock()
	tx, ok := s.txs[id]
	s.mu.RUnlock()
	if !ok {
		http.Error(w, "transaction not found", http.StatusNotFound)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(tx)
}

func (s *Server) handleHealth(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
	w.Write([]byte("OK"))
}

func main() {
	rand.Seed(time.Now().UnixNano())
	server := NewServer()

	http.HandleFunc("/relay", server.handleRelay)
	http.HandleFunc("/tx/", server.handleGetTx) // expects /tx/{id}
	http.HandleFunc("/health", server.handleHealth)

	addr := ":8080"
	log.Printf("Magnum Opus transaction relay listening on %s", addr)
	if err := http.ListenAndServe(addr, nil); err != nil {
		log.Fatalf("server failed: %v", err)
	}
}
