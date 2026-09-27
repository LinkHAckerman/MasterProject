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
// with balance and transaction history

// Wallet represents a blockchain wallet with balance and transaction history
type Wallet struct {
    Address     string      `json:"address"`
    Balance     float64     `json:"balance"`
    Nonce       uint64      `json:"nonce"`
    Transactions []Transaction `json:"transactions"`
}

// Transaction represents a blockchain transaction
type Transaction struct {
    Hash        string    `json:"hash"`
    From        string    `json:"from"`
    To          string    `json:"to"`
    Value       float64   `json:"value"`
    GasPrice    float64   `json:"gasPrice"`
    GasLimit    uint64    `json:"gasLimit"`
    Nonce       uint64    `json:"nonce"`
    Timestamp   time.Time `json:"timestamp"`
    Status      string    `json:"status"`
}

// WalletService manages wallet operations
// with thread-safe access

type WalletService struct {
    wallets map[string]*Wallet
    mu      sync.RWMutex
}

// NewWalletService creates a new WalletService
func NewWalletService() *WalletService {
    return &WalletService{
        wallets: make(map[string]*Wallet),
    }
}

// GetWallet retrieves a wallet by address
func (ws *WalletService) GetWallet(address string) (*Wallet, error) {
    ws.mu.RLock()
    defer ws.mu.RUnlock()

    wallet, exists := ws.wallets[address]
    if !exists {
        return nil, fmt.Errorf("wallet not found")
    }
    return wallet, nil
}

// CreateWallet creates a new wallet
func (ws *WalletService) CreateWallet(address string) *Wallet {
    ws.mu.Lock()
    defer ws.mu.Unlock()

    wallet := &Wallet{
        Address: address,
        Balance: 0,
        Nonce:   0,
    }
    ws.wallets[address] = wallet
    return wallet
}

// AddTransaction adds a transaction to a wallet
func (ws *WalletService) AddTransaction(tx Transaction) error {
    ws.mu.Lock()
    defer ws.mu.Unlock()

    fromWallet, exists := ws.wallets[tx.From]
    if !exists {
        return fmt.Errorf("sender wallet not found")
    }

    toWallet, exists := ws.wallets[tx.To]
    if !exists {
        return fmt.Errorf("recipient wallet not found")
    }

    // Update balances
    fromWallet.Balance -= tx.Value
    toWallet.Balance += tx.Value

    // Update nonces
    fromWallet.Nonce++
    toWallet.Nonce++

    // Add transaction to both wallets
    fromWallet.Transactions = append(fromWallet.Transactions, tx)
    toWallet.Transactions = append(toWallet.Transactions, tx)

    return nil
}

// GetTransactionHistory retrieves transaction history for a wallet
func (ws *WalletService) GetTransactionHistory(address string) ([]Transaction, error) {
    ws.mu.RLock()
    defer ws.mu.RUnlock()

    wallet, exists := ws.wallets[address]
    if !exists {
        return nil, fmt.Errorf("wallet not found")
    }
    return wallet.Transactions, nil
}

// WalletHandler handles wallet-related HTTP requests

type WalletHandler struct {
    service *WalletService
}

// NewWalletHandler creates a new WalletHandler
func NewWalletHandler(service *WalletService) *WalletHandler {
    return &WalletHandler{service: service}
}

// GetWalletHandler handles GET requests for wallet information
func (wh *WalletHandler) GetWalletHandler(w http.ResponseWriter, r *http.Request) {
    vars := mux.Vars(r)
    address := vars["address"]

    wallet, err := wh.service.GetWallet(address)
    if err != nil {
        http.Error(w, err.Error(), http.StatusNotFound)
        return
    }

    json.NewEncoder(w).Encode(wallet)
}

// CreateWalletHandler handles POST requests for creating a new wallet
func (wh *WalletHandler) CreateWalletHandler(w http.ResponseWriter, r *http.Request) {
    vars := mux.Vars(r)
    address := vars["address"]

    wallet := wh.service.CreateWallet(address)
    json.NewEncoder(w).Encode(wallet)
}

// AddTransactionHandler handles POST requests for adding a transaction
func (wh *WalletHandler) AddTransactionHandler(w http.ResponseWriter, r *http.Request) {
    var tx Transaction
    if err := json.NewDecoder(r.Body).Decode(&tx); err != nil {
        http.Error(w, err.Error(), http.StatusBadRequest)
        return
    }

    if err := wh.service.AddTransaction(tx); err != nil {
        http.Error(w, err.Error(), http.StatusBadRequest)
        return
    }

    w.WriteHeader(http.StatusCreated)
}

// GetTransactionHistoryHandler handles GET requests for transaction history
func (wh *WalletHandler) GetTransactionHistoryHandler(w http.ResponseWriter, r *http.Request) {
    vars := mux.Vars(r)
    address := vars["address"]

    transactions, err := wh.service.GetTransactionHistory(address)
    if err != nil {
        http.Error(w, err.Error(), http.StatusNotFound)
        return
    }

    json.NewEncoder(w).Encode(transactions)
}

func main() {
    // Initialize wallet service
    walletService := NewWalletService()

    // Initialize wallet handler
    walletHandler := NewWalletHandler(walletService)

    // Create router
    r := mux.NewRouter()

    // Define routes
    r.HandleFunc("/wallets/{address}", walletHandler.GetWalletHandler).Methods("GET")
    r.HandleFunc("/wallets/{address}", walletHandler.CreateWalletHandler).Methods("POST")
    r.HandleFunc("/transactions", walletHandler.AddTransactionHandler).Methods("POST")
    r.HandleFunc("/wallets/{address}/transactions", walletHandler.GetTransactionHistoryHandler).Methods("GET")

    // Start server
    log.Println("Starting server on :8080")
    log.Fatal(http.ListenAndServe(":8080", r))
}