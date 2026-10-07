package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"sync"
	"time"
	"github.com/gorilla/mux"
)

// Wallet represents a blockchain wallet
// with its associated metadata
// and transaction history

type Wallet struct {
	Address     string    `json:"address"`
	Balance     float64   `json:"balance"`
	ChainID     string    `json:"chainId"`
	NetworkName string    `json:"networkName"`
	Tokens      []Token   `json:"tokens"`
	TxHistory   []Tx      `json:"txHistory"`
}

// Token represents a cryptocurrency token
// with its associated metadata

type Token struct {
	Symbol  string  `json:"symbol"`
	Name    string  `json:"name"`
	Balance float64 `json:"balance"`
	Price   float64 `json:"price"`
}

// Tx represents a blockchain transaction
// with its associated metadata

type Tx struct {
	Hash        string    `json:"hash"`
	From        string    `json:"from"`
	To          string    `json:"to"`
	Value       float64   `json:"value"`
	GasPrice    float64   `json:"gasPrice"`
	GasUsed     float64   `json:"gasUsed"`
	Timestamp   time.Time `json:"timestamp"`
	Status      string    `json:"status"`
}

// WalletService represents the wallet service
// with its associated wallets and mutex

type WalletService struct {
	wallets map[string]Wallet
	mu      sync.Mutex
}

// NewWalletService creates a new WalletService

func NewWalletService() *WalletService {
	return &WalletService{
		wallets: make(map[string]Wallet),
	}
}

// GetWalletHandler handles the GET /wallets/{address} endpoint

func (ws *WalletService) GetWalletHandler(w http.ResponseWriter, r *http.Request) {
	vars := mux.Vars(r)
	address := vars["address"]

	ws.mu.Lock()
	wallet, ok := ws.wallets[address]
	ws.mu.Unlock()

	if !ok {
		w.WriteHeader(http.StatusNotFound)
		json.NewEncoder(w).Encode(map[string]string{"error": "Wallet not found"})
		return
	}

	json.NewEncoder(w).Encode(wallet)
}

// CreateWalletHandler handles the POST /wallets endpoint

func (ws *WalletService) CreateWalletHandler(w http.ResponseWriter, r *http.Request) {
	var wallet Wallet
	err := json.NewDecoder(r.Body).Decode(&wallet)
	if err != nil {
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(map[string]string{"error": "Invalid request payload"})
		return
	}

	ws.mu.Lock()
	ws.wallets[wallet.Address] = wallet
	ws.mu.Unlock()

	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(wallet)
}

// UpdateWalletHandler handles the PUT /wallets/{address} endpoint

func (ws *WalletService) UpdateWalletHandler(w http.ResponseWriter, r *http.Request) {
	vars := mux.Vars(r)
	address := vars["address"]

	var wallet Wallet
	err := json.NewDecoder(r.Body).Decode(&wallet)
	if err != nil {
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(map[string]string{"error": "Invalid request payload"})
		return
	}

	ws.mu.Lock()
	ws.wallets[address] = wallet
	ws.mu.Unlock()

	json.NewEncoder(w).Encode(wallet)
}

// DeleteWalletHandler handles the DELETE /wallets/{address} endpoint

func (ws *WalletService) DeleteWalletHandler(w http.ResponseWriter, r *http.Request) {
	vars := mux.Vars(r)
	address := vars["address"]

	ws.mu.Lock()
	delete(ws.wallets, address)
	ws.mu.Unlock()

	w.WriteHeader(http.StatusNoContent)
}

// GetWalletTxHistoryHandler handles the GET /wallets/{address}/tx-history endpoint

func (ws *WalletService) GetWalletTxHistoryHandler(w http.ResponseWriter, r *http.Request) {
	vars := mux.Vars(r)
	address := vars["address"]

	ws.mu.Lock()
	wallet, ok := ws.wallets[address]
	ws.mu.Unlock()

	if !ok {
		w.WriteHeader(http.StatusNotFound)
		json.NewEncoder(w).Encode(map[string]string{"error": "Wallet not found"})
		return
	}

	json.NewEncoder(w).Encode(wallet.TxHistory)
}

// AddWalletTxHandler handles the POST /wallets/{address}/tx-history endpoint

func (ws *WalletService) AddWalletTxHandler(w http.ResponseWriter, r *http.Request) {
	vars := mux.Vars(r)
	address := vars["address"]

	var tx Tx
	err := json.NewDecoder(r.Body).Decode(&tx)
	if err != nil {
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(map[string]string{"error": "Invalid request payload"})
		return
	}

	ws.mu.Lock()
	wallet, ok := ws.wallets[address]
	if !ok {
		ws.mu.Unlock()
		w.WriteHeader(http.StatusNotFound)
		json.NewEncoder(w).Encode(map[string]string{"error": "Wallet not found"})
		return
	}

	wallet.TxHistory = append(wallet.TxHistory, tx)
	ws.wallets[address] = wallet
	ws.mu.Unlock()

	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(tx)
}

// main is the entry point of the application

func main() {
	r := mux.NewRouter()

	walletService := NewWalletService()

	r.HandleFunc("/wallets/{address}", walletService.GetWalletHandler).Methods("GET")
	r.HandleFunc("/wallets", walletService.CreateWalletHandler).Methods("POST")
	r.HandleFunc("/wallets/{address}", walletService.UpdateWalletHandler).Methods("PUT")
	r.HandleFunc("/wallets/{address}", walletService.DeleteWalletHandler).Methods("DELETE")
	r.HandleFunc("/wallets/{address}/tx-history", walletService.GetWalletTxHistoryHandler).Methods("GET")
	r.HandleFunc("/wallets/{address}/tx-history", walletService.AddWalletTxHandler).Methods("POST")

	srv := &http.Server{
		Handler:      r,
		Addr:         "127.0.0.1:8000",
		WriteTimeout: 15 * time.Second,
		ReadTimeout:  15 * time.Second,
	}

	fmt.Println("Server is running on port 8000")
	log.Fatal(srv.ListenAndServe())
}