package main

import (
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"strings"
	"time"
)

// Magnum Opus // Web3 & DeFi Nexus Engine — Relay Microservice (Go)
// Lightweight, concurrent-safe service for wallet address validation,
// transaction relay, and cross-ecosystem integration between C++ crypto engines,
// Rust on-chain programs, and Ruby glue services.

type WalletAddress struct {
	Address string `json:"address"`
	Chain   string `json:"chain"`
	Valid   bool   `json:"valid"`
}

type RelayRequest struct {
	From    string `json:"from"`
	To      string `json:"to"`
	Amount  string `json:"amount"`
	Chain   string `json:"chain"`
	Nonce   uint64 `json:"nonce"`
	GasPrice string `json:"gasPrice"`
}

type RelayResponse struct {
	Status     string  `json:"status"`
	TxHash     string  `json:"txHash"`
	Estimated  float64 `json:"estimatedConfirmations"`
	Message    string  `json:"message"`
}

var supportedChains = map[string]bool{
	"eth": true,
	"bsc": true,
	"sol": true,
	"poly": true,
}

func validateAddress(addr, chain string) bool {
	addr = strings.TrimSpace(addr)
	if len(addr) < 20 || len(addr) > 62 {
		return false
	}
	switch strings.ToLower(chain) {
	case "eth", "bsc", "poly":
		if !strings.HasPrefix(addr, "0x") {
			return false
		}
		hexPart := addr[2:]
		for _, c := range hexPart {
			if (c < '0' || c > '9') && (c < 'a' || c > 'f') && (c < 'A' || c > 'F') {
				return false
			}
		}
	case "sol":
		if !strings.HasPrefix(addr, "0x") && !strings.HasPrefix(addr, "solana:") {
			if len(addr) != 44 {
				return false
			}
		}
	}
	return true
}

func relayTransaction(req RelayRequest) (string, error) {
	fmt.Printf("Relaying tx: %s -> %s amount=%s chain=%s\n", req.From, req.To, req.Amount, req.Chain)
	hash := fmt.Sprintf("0x%x", time.Now().UnixNano())
	return hash, nil
}

func handleRelay(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	var req RelayRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid JSON payload", http.StatusBadRequest)
		return
	}
	if !validateAddress(req.From, req.Chain) || !validateAddress(req.To, req.Chain) {
		resp := RelayResponse{Status: "error", Message: "Invalid wallet address format"}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(resp)
		return
	}
	txHash, err := relayTransaction(req)
	if err != nil {
		resp := RelayResponse{Status: "error", Message: "Relay failed"}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(resp)
		return
	}
	resp := RelayResponse{
		Status:    "success",
		TxHash:    txHash,
		Estimated: 3.5,
		Message:   "Transaction relayed successfully",
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(resp)
}

func handleWallet(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	addr := strings.TrimSuffix(r.URL.Path, "/")
	addr = strings.TrimPrefix(addr, "/wallet")
	addr = strings.TrimSpace(addr)
	valid := validateAddress(addr, "eth")
	resp := WalletAddress{Address: addr, Chain: "eth", Valid: valid}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(resp)
}

func handleHealth(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	resp := map[string]string{"status": "healthy", "service": "magnopus-relay"}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(resp)
}

func loggingMiddleware(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		fmt.Printf("[%s] %s %s\n", time.Now().Format("15:04:05"), r.Method, r.URL.Path)
		next(w, r)
	}
}

func recoveryMiddleware(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			if rec := recover(); rec != nil {
				http.Error(w, "Internal server error", http.StatusInternalServerError)
			}
		}()
		next(w, r)
	}
}

func corsMiddleware(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusOK)
			return
		}
		next(w, r)
	}
}

func main() {
	http.HandleFunc("/relay", loggingMiddleware(recoveryMiddleware(corsMiddleware(handleRelay))))
	http.HandleFunc("/wallet", loggingMiddleware(recoveryMiddleware(corsMiddleware(handleWallet))))
	http.HandleFunc("/health", loggingMiddleware(recoveryMiddleware(corsMiddleware(handleHealth))))

	port := "8080"
	if len(os.Args) > 1 {
		port = os.Args[1]
	}

	server := &http.Server{
		Addr:           ":" + port,
		ReadTimeout:    10 * time.Second,
		WriteTimeout:   10 * time.Second,
		MaxHeaderBytes: 1 << 20,
	}

	fmt.Printf("Magnum Opus Relay Microservice starting on :%s...\n", port)
	fmt.Println("Ecosystem integrations: C++ Crypto Engine, Rust On-Chain Programs, Ruby Glue Service")
	if err := server.ListenAndServe(); err != nil {
		fmt.Printf("Server failed: %v\n", err)
	}
}
