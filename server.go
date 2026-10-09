package main

import (
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"regexp"
	"sync/atomic"
	"time"
)

// Simple in-memory mock wallet balances
var balances = map[string]float64{
	"0x1111111111111111111111111111111111111111": 1000.0,
	"0x2222222222222222222222222222222222222222": 500.0,
}

var requestCount uint64

// healthHandler returns a basic health check
func healthHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
}

// balanceHandler returns the ETH balance for a given address
func balanceHandler(w http.ResponseWriter, r *http.Request) {
	address := r.URL.Query().Get("address")
	if !isValidEthAddress(address) {
		http.Error(w, "invalid address", http.StatusBadRequest)
		return
	}
	balance, ok := balances[address]
	if !ok {
		balance = 0.0
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{"address": address, "balance": balance})
}

// transactionRelayHandler accepts a transaction payload and pretends to relay it
func transactionRelayHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	var tx struct {
		From      string  `json:"from"`
		To        string  `json:"to"`
		Amount    float64 `json:"amount"`
		Token     string  `json:"token"`
		Nonce     uint64  `json:"nonce"`
		Signature string  `json:"signature"`
	}
	if err := json.NewDecoder(r.Body).Decode(&tx); err != nil {
		http.Error(w, "invalid json", http.StatusBadRequest)
		return
	}
	if !isValidEthAddress(tx.From) || !isValidEthAddress(tx.To) {
		http.Error(w, "invalid from/to address", http.StatusBadRequest)
		return
	}
	if tx.Amount <= 0 {
		http.Error(w, "amount must be positive", http.StatusBadRequest)
		return
	}
	// Mock processing delay
	time.Sleep(100 * time.Millisecond)
	// Log the transaction (in real world you would forward to a node)
	log.Printf("relayed tx: %+v", tx)
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "submitted", "txHash": generateMockTxHash(tx)})
}

// isValidEthAddress validates a hex Ethereum address (0x followed by 40 hex chars)
func isValidEthAddress(addr string) bool {
	var ethAddrRegex = regexp.MustCompile(`^0x[0-9a-fA-F]{40}$`)
	return ethAddrRegex.MatchString(addr)
}

// generateMockTxHash creates a deterministic mock hash for demonstration purposes
func generateMockTxHash(tx interface{}) string {
	b, _ := json.Marshal(tx)
	return "0x" + fmt.Sprintf("%x", sha256Sum(b))[:64]
}

func sha256Sum(data []byte) []byte {
	h := sha256.New()
	h.Write(data)
	return h.Sum(nil)
}

// loggingMiddleware adds request ID and logs basic info
func loggingMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		id := atomic.AddUint64(&requestCount, 1)
		start := time.Now()
		log.Printf("[%d] %s %s", id, r.Method, r.URL.Path)
		next.ServeHTTP(w, r)
		log.Printf("[%d] completed in %v", id, time.Since(start))
	})
}

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	mux := http.NewServeMux()
	mux.HandleFunc("/health", healthHandler)
	mux.HandleFunc("/wallet/balance", balanceHandler)
	mux.HandleFunc("/transaction/relay", transactionRelayHandler)

	loggedMux := loggingMiddleware(mux)
	log.Printf("starting server on :%s", port)
	if err := http.ListenAndServe(":"+port, loggedMux); err != nil {
		log.Fatalf("server failed: %v", err)
	}
}
