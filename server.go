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
	"sync"
	"syscall"
	"time"
)

type TransactionRequest struct {
	From     string  `json:"from"`
	To       string  `json:"to"`
	Amount   float64 `json:"amount"`
	Token    string  `json:"token"`
	GasPrice uint64  `json:"gas_price"`
}

type TransactionResponse struct {
	TxHash  string `json:"tx_hash"`
	Status  string `json:"status"`
	Message string `json:"message"`
}

var (
	txStore = make(map[string]string) // txHash -> status
	storeMu sync.RWMutex
)

func main() {
	http.HandleFunc("/relay", relayHandler)
	http.HandleFunc("/status/", statusHandler) // expects /status/{txHash}
	http.HandleFunc("/healthz", healthHandler)

	srv := &http.Server{
		Addr:    ":8080",
		Handler: nil,
	}

	go func() {
		log.Println("🚀 Server listening on :8080")
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("listen: %s\n", err)
		}
	}()

	// Graceful shutdown
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit
	log.Println("Shutting down server...")

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := srv.Shutdown(ctx); err != nil {
		log.Fatalf("Server forced to shutdown: %v", err)
	}
	log.Println("Server exiting")
}

func relayHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	var req TransactionRequest
	decoder := json.NewDecoder(r.Body)
	if err := decoder.Decode(&req); err != nil {
		http.Error(w, "Invalid JSON payload", http.StatusBadRequest)
		return
	}
	if req.From == "" || req.To == "" || req.Amount <= 0 || req.Token == "" {
		http.Error(w, "Missing or invalid fields", http.StatusBadRequest)
		return
	}

	// Simulate transaction processing
	txHash := generateTxHash(req)
	storeMu.Lock()
	txStore[txHash] = "pending"
	storeMu.Unlock()

	go processTransaction(txHash)

	resp := TransactionResponse{
		TxHash:  txHash,
		Status:  "pending",
		Message: "Transaction received and is being processed",
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(resp)
}

func statusHandler(w http.ResponseWriter, r *http.Request) {
	// URL pattern: /status/{txHash}
	txHash := r.URL.Path[len("/status/"):]
	if txHash == "" {
		http.Error(w, "TxHash required", http.StatusBadRequest)
		return
	}
	storeMu.RLock()
	status, ok := txStore[txHash]
	storeMu.RUnlock()
	if !ok {
		http.Error(w, "Transaction not found", http.StatusNotFound)
		return
	}
	resp := map[string]string{
		"tx_hash": txHash,
		"status":  status,
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(resp)
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
	w.Write([]byte("OK"))
}

func generateTxHash(req TransactionRequest) string {
	data := req.From + req.To + req.Token + fmt.Sprintf("%f", req.Amount) + fmt.Sprintf("%d", req.GasPrice) + time.Now().String()
	hash := sha256.Sum256([]byte(data))
	return "0x" + hex.EncodeToString(hash[:])
}

func processTransaction(txHash string) {
	// Simulate processing delay
	time.Sleep(2 * time.Second)
	storeMu.Lock()
	txStore[txHash] = "confirmed"
	storeMu.Unlock()
}
