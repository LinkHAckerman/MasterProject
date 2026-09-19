package main

import (
    "encoding/json"
    "fmt"
    "log"
    "net/http"
    "sync"
    "time"
)

// Wallet represents a blockchain wallet
// with address, balance, and transaction history

type Wallet struct {
    Address     string    `json:"address"`
    Balance     float64   `json:"balance"`
    Transactions []string  `json:"transactions"`
}

// Transaction represents a blockchain transaction
// with sender, recipient, amount, and timestamp

type Transaction struct {
    Sender      string    `json:"sender"`
    Recipient   string    `json:"recipient"`
    Amount      float64   `json:"amount"`
    Timestamp   time.Time `json:"timestamp"`
}

// WalletService handles wallet operations
// with thread-safe access to wallet data

type WalletService struct {
    wallets map[string]*Wallet
    mu      sync.Mutex
}

// NewWalletService creates a new WalletService
// with an initial genesis wallet

func NewWalletService() *WalletService {
    ws := &WalletService{
        wallets: make(map[string]*Wallet),
    }
    ws.wallets["genesis"] = &Wallet{
        Address: "genesis",
        Balance: 1000000.0,
        Transactions: []string{},
    }
    return ws
}

// GetWallet retrieves a wallet by address

func (ws *WalletService) GetWallet(address string) (*Wallet, error) {
    ws.mu.Lock()
    defer ws.mu.Unlock()
    
    wallet, exists := ws.wallets[address]
    if !exists {
        return nil, fmt.Errorf("wallet not found")
    }
    return wallet, nil
}

// CreateWallet creates a new wallet

func (ws *WalletService) CreateWallet(address string) (*Wallet, error) {
    ws.mu.Lock()
    defer ws.mu.Unlock()
    
    if _, exists := ws.wallets[address]; exists {
        return nil, fmt.Errorf("wallet already exists")
    }
    
    wallet := &Wallet{
        Address: address,
        Balance: 0.0,
        Transactions: []string{},
    }
    ws.wallets[address] = wallet
    return wallet, nil
}

// SendTransaction sends a transaction from one wallet to another

func (ws *WalletService) SendTransaction(sender, recipient string, amount float64) error {
    ws.mu.Lock()
    defer ws.mu.Unlock()
    
    senderWallet, exists := ws.wallets[sender]
    if !exists {
        return fmt.Errorf("sender wallet not found")
    }
    
    recipientWallet, exists := ws.wallets[recipient]
    if !exists {
        return fmt.Errorf("recipient wallet not found")
    }
    
    if senderWallet.Balance < amount {
        return fmt.Errorf("insufficient balance")
    }
    
    senderWallet.Balance -= amount
    recipientWallet.Balance += amount
    
    transaction := Transaction{
        Sender:    sender,
        Recipient: recipient,
        Amount:    amount,
        Timestamp: time.Now(),
    }
    
    senderWallet.Transactions = append(senderWallet.Transactions, fmt.Sprintf("Sent %.2f to %s", amount, recipient))
    recipientWallet.Transactions = append(recipientWallet.Transactions, fmt.Sprintf("Received %.2f from %s", amount, sender))
    
    return nil
}

// WalletHandler handles HTTP requests for wallet operations

func WalletHandler(ws *WalletService) http.HandlerFunc {
    return func(w http.ResponseWriter, r *http.Request) {
        switch r.Method {
        case http.MethodGet:
            address := r.URL.Query().Get("address")
            if address == "" {
                http.Error(w, "address is required", http.StatusBadRequest)
                return
            }
            
            wallet, err := ws.GetWallet(address)
            if err != nil {
                http.Error(w, err.Error(), http.StatusNotFound)
                return
            }
            
            json.NewEncoder(w).Encode(wallet)
        case http.MethodPost:
            var wallet Wallet
            if err := json.NewDecoder(r.Body).Decode(&wallet); err != nil {
                http.Error(w, err.Error(), http.StatusBadRequest)
                return
            }
            
            if wallet.Address == "" {
                http.Error(w, "address is required", http.StatusBadRequest)
                return
            }
            
            createdWallet, err := ws.CreateWallet(wallet.Address)
            if err != nil {
                http.Error(w, err.Error(), http.StatusConflict)
                return
            }
            
            json.NewEncoder(w).Encode(createdWallet)
        default:
            http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
        }
    }
}

// TransactionHandler handles HTTP requests for transactions

func TransactionHandler(ws *WalletService) http.HandlerFunc {
    return func(w http.ResponseWriter, r *http.Request) {
        if r.Method != http.MethodPost {
            http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
            return
        }
        
        var transaction Transaction
        if err := json.NewDecoder(r.Body).Decode(&transaction); err != nil {
            http.Error(w, err.Error(), http.StatusBadRequest)
            return
        }
        
        if transaction.Sender == "" || transaction.Recipient == "" || transaction.Amount <= 0 {
            http.Error(w, "invalid transaction data", http.StatusBadRequest)
            return
        }
        
        err := ws.SendTransaction(transaction.Sender, transaction.Recipient, transaction.Amount)
        if err != nil {
            http.Error(w, err.Error(), http.StatusBadRequest)
            return
        }
        
        w.WriteHeader(http.StatusCreated)
    }
}

func main() {
    ws := NewWalletService()
    
    http.HandleFunc("/wallet", WalletHandler(ws))
    http.HandleFunc("/transaction", TransactionHandler(ws))
    
    fmt.Println("Server is running on port 8080")
    log.Fatal(http.ListenAndServe(":8080", nil))
}