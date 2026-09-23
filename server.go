package main

import (
	"encoding/json"
	"fmt"
	"net/http"
	"sync"
	"time"
)

// --- Magnum Opus: Web3 & DeFi Nexus Engine ---
// Go Microservice: Wallet & Transaction Relay
// Purpose: Lightweight, high-performance relay for wallet state queries
// and transaction propagation across supported ecosystems.

// --- Core Types ---

type Wallet struct {
	Address     string  `json:"address"`
	BalanceEth  float64 `json:"balance_eth"`
	BalanceMopus float64 `json:"balance_mopus"`
	BalanceUsdc float64 `json:"balance_usdc"`
	ChainID     uint64  `json:"chain_id"`
	Connected   bool    `json:"connected"`
}

type Transaction struct {
	ID        string  `json:"id"`
	From      string  `json:"from"`
	To        string  `json:"to"`
	Value     float64 `json:"value"`
	GasPrice  uint64  `json:"gas_price"`
	GasLimit  uint64  `json:"gas_limit"`
	Status    string  `json:"status"`
	Timestamp int64   `json:"timestamp"`
}

type RelayRequest struct {
	Tx      Transaction `json:"tx"`
	Source  string      `json:"source"`
	Sig     string      `json:"sig"`
}

type RelayResponse struct {
	Success bool     `json:"success"`
	TxID    string   `json:"tx_id"`
	Message string   `json:"message"`
	Details *Transaction `json:"details,omitempty"`
}

// --- Mock State ---

var (
	wallets map[string]*Wallet
	mempool []Transaction
	mu      sync.RWMutex
)

func initState() {
	wallets = map[string]*Wallet{
		"0xAbC123": {Address: "0xAbC123", BalanceEth: 14.8520, BalanceMopus: 4500.00, BalanceUsdc: 18500.25, ChainID: 1, Connected: true},
		"0xDef456": {Address: "0xDef456", BalanceEth: 2.3150, BalanceMopus: 1200.50, BalanceUsdc: 50000.00, ChainID: 1, Connected: true},
	}
	mempool = []Transaction{}
}

// --- HTTP Handlers ---

func handleWalletBalance(w http.ResponseWriter, r *http.Request) {
	mu.RLock()
	defer mu.RUnlock()

	addr := r.PathValue("address")
	if addr == "" {
		http.Error(w, "address parameter required", http.StatusBadRequest)
		return
	}
	wlt, exists := wallets[addr]
	if !exists {
		wlt = &Wallet{Address: addr, BalanceEth: 0, BalanceMopus: 0, BalanceUsdc: 0, ChainID: 1, Connected: false}
	}
	wltJSON, _ := json.Marshal(wlt)
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("X-Theme", "magnum-opus-dark")
	w.Write(wltJSON)
}

func handleRelayTx(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req RelayRequest
	dec := json.NewDecoder(r.Body)
	if err := dec.Decode(&req); err != nil {
		http.Error(w, "invalid JSON payload", http.StatusBadRequest)
		return
	}
	mu.Lock()
	mempool = append(mempool, req.Tx)
	mu.Unlock()

	// Simulate consensus inclusion
	tx := req.Tx
tx.Status = "pending"
tx.Timestamp = time.Now().Unix()

	resp := RelayResponse{
		Success: true,
		TxID:    fmt.Sprintf("0x%x", []byte(tx.ID[:8])),
		Message: "transaction relayed to mempool",
		Details: &tx,
}

	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("X-Transaction-ID", resp.TxID)
	json.NewEncoder(w).Encode(resp)
}

func handleMempoolStats(w http.ResponseWriter, r *http.Request) {
	mu.RLock()
	defer mu.RUnlock()

	total := len(mempool)
	var totalValue float64
	for _, tx := range mempool {
		totalValue += tx.Value
	}
	type Stats struct {
		TotalTxs   int     `json:"total_txs"`
		TotalValue float64 `json:"total_value"`
		AvgFee     float64 `json:"avg_fee"`
	}
	json.NewEncoder(w).Encode(Stats{TotalTxs: total, TotalValue: totalValue})
}

// --- Middleware ---

func loggingMiddleware(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		next(w, r)
		fmt.Printf("[%s] %s %s %v\n", r.Method, r.URL.Path, r.RemoteAddr, time.Since(start))
	}
}

func corsMiddleware(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusOK)
			return
		}
		next(w, r)
	}
}

// --- Main ---

func main() {
	initState()

	mux := http.NewServeMux()

	mux.HandleFunc("/wallet/{address}/balance", handleWalletBalance)
	mux.HandleFunc("/tx/relay", handleRelayTx)
	mux.HandleFunc("/mempool/stats", handleMempoolStats)

	wrapped := corsMiddleware(loggingMiddleware(func(w http.ResponseWriter, r *http.Request) {
		http.NotFound(w, r)
	}))

	srv := &http.Server{
		Addr:         ":8080",
		Handler:      wrapped,
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 15 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	fmt.Printf("[Magnum Opus] Go Relay Service starting on %s\n", srv.Addr)
	if err := srv.ListenAndServe(); err != nil {
		fmt.Printf("[Magnum Opus] Server error: %v\n", err)
	}
}
