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
// with address, balance, and transaction history
// This is a simplified version for demonstration
// In a real application, you would use a proper blockchain library
// and handle private keys securely

type Wallet struct {
    Address     string      `json:"address"`
    Balance     float64     `json:"balance"`
    Nonce       uint64      `json:"nonce"`
    Transactions []Transaction `json:"transactions"`
}

// Transaction represents a blockchain transaction
// with sender, receiver, amount, and timestamp
// This is a simplified version for demonstration
// In a real application, you would include more fields
// and handle transaction signing and verification

type Transaction struct {
    Sender      string    `json:"sender"`
    Receiver    string    `json:"receiver"`
    Amount      float64   `json:"amount"`
    Timestamp   time.Time `json:"timestamp"`
    GasPrice    float64   `json:"gasPrice"`
    GasLimit    uint64    `json:"gasLimit"`
    Nonce       uint64    `json:"nonce"`
    Hash        string    `json:"hash"`
}

// WalletService represents the wallet service
// with a map of wallets and a mutex for thread safety

type WalletService struct {
    wallets map[string]*Wallet
    mu      sync.Mutex
}

// NewWalletService creates a new WalletService
// with an empty map of wallets

func NewWalletService() *WalletService {
    return &WalletService{
        wallets: make(map[string]*Wallet),
    }
}

// CreateWallet creates a new wallet with the given address
// and adds it to the map of wallets

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

// GetWallet returns the wallet with the given address
// or nil if the wallet does not exist

func (ws *WalletService) GetWallet(address string) *Wallet {
    ws.mu.Lock()
    defer ws.mu.Unlock()

    return ws.wallets[address]
}

// SendTransaction sends a transaction from the sender to the receiver
// with the given amount, gas price, and gas limit
// It updates the balances of the sender and receiver
// and adds the transaction to the transaction history
// of both wallets

func (ws *WalletService) SendTransaction(sender, receiver string, amount, gasPrice float64, gasLimit uint64) (*Transaction, error) {
    ws.mu.Lock()
    defer ws.mu.Unlock()

    senderWallet := ws.wallets[sender]
    if senderWallet == nil {
        return nil, fmt.Errorf("sender wallet not found")
    }

    receiverWallet := ws.wallets[receiver]
    if receiverWallet == nil {
        return nil, fmt.Errorf("receiver wallet not found")
    }

    if senderWallet.Balance < amount+gasPrice*float64(gasLimit) {
        return nil, fmt.Errorf("insufficient balance")
    }

    if senderWallet.Nonce+1 != senderWallet.Nonce {
        return nil, fmt.Errorf("invalid nonce")
    }

    tx := &Transaction{
        Sender:    sender,
        Receiver:  receiver,
        Amount:    amount,
        Timestamp: time.Now(),
        GasPrice:  gasPrice,
        GasLimit:  gasLimit,
        Nonce:     senderWallet.Nonce,
        Hash:      fmt.Sprintf("%x", Sha256([]byte(fmt.Sprintf("%s%s%f%d%d%d", sender, receiver, amount, gasPrice, gasLimit, senderWallet.Nonce)))),
    }

    senderWallet.Balance -= amount + gasPrice*float64(gasLimit)
    senderWallet.Nonce++
    senderWallet.Transactions = append(senderWallet.Transactions, *tx)

    receiverWallet.Balance += amount
    receiverWallet.Transactions = append(receiverWallet.Transactions, *tx)

    return tx, nil
}

// GetTransactionHistory returns the transaction history
// of the wallet with the given address

func (ws *WalletService) GetTransactionHistory(address string) ([]Transaction, error) {
    ws.mu.Lock()
    defer ws.mu.Unlock()

    wallet := ws.wallets[address]
    if wallet == nil {
        return nil, fmt.Errorf("wallet not found")
    }

    return wallet.Transactions, nil
}

// GetBalance returns the balance of the wallet with the given address

func (ws *WalletService) GetBalance(address string) (float64, error) {
    ws.mu.Lock()
    defer ws.mu.Unlock()

    wallet := ws.wallets[address]
    if wallet == nil {
        return 0, fmt.Errorf("wallet not found")
    }

    return wallet.Balance, nil
}

// GetNonce returns the nonce of the wallet with the given address

func (ws *WalletService) GetNonce(address string) (uint64, error) {
    ws.mu.Lock()
    defer ws.mu.Unlock()

    wallet := ws.wallets[address]
    if wallet == nil {
        return 0, fmt.Errorf("wallet not found")
    }

    return wallet.Nonce, nil
}

// Sha256 computes the SHA-256 hash of the given data
// This is a simplified version for demonstration
// In a real application, you would use a proper cryptographic library

func Sha256(data []byte) []byte {
    // This is a placeholder for the actual SHA-256 implementation
    // In a real application, you would use a proper cryptographic library
    // such as crypto/sha256 in the Go standard library
    return data
}

// main is the entry point of the application
// It creates a new WalletService and starts the HTTP server

func main() {
    walletService := NewWalletService()

    // Create some wallets for demonstration
    walletService.CreateWallet("0x123...")
    walletService.CreateWallet("0x456...")

    // Create a new router
    r := mux.NewRouter()

    // Define the routes
    r.HandleFunc("/wallets", func(w http.ResponseWriter, r *http.Request) {
        switch r.Method {
        case "POST":
            var wallet Wallet
            err := json.NewDecoder(r.Body).Decode(&wallet)
            if err != nil {
                http.Error(w, err.Error(), http.StatusBadRequest)
                return
            }

            createdWallet := walletService.CreateWallet(wallet.Address)
            json.NewEncoder(w).Encode(createdWallet)
        default:
            http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
        }
    }).Methods("POST")

    r.HandleFunc("/wallets/{address}", func(w http.ResponseWriter, r *http.Request) {
        vars := mux.Vars(r)
        address := vars["address"]

        switch r.Method {
        case "GET":
            wallet := walletService.GetWallet(address)
            if wallet == nil {
                http.Error(w, "Wallet not found", http.StatusNotFound)
                return
            }

            json.NewEncoder(w).Encode(wallet)
        default:
            http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
        }
    }).Methods("GET")

    r.HandleFunc("/wallets/{address}/balance", func(w http.ResponseWriter, r *http.Request) {
        vars := mux.Vars(r)
        address := vars["address"]

        switch r.Method {
        case "GET":
            balance, err := walletService.GetBalance(address)
            if err != nil {
                http.Error(w, err.Error(), http.StatusNotFound)
                return
            }

            json.NewEncoder(w).Encode(map[string]float64{"balance": balance})
        default:
            http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
        }
    }).Methods("GET")

    r.HandleFunc("/wallets/{address}/nonce", func(w http.ResponseWriter, r *http.Request) {
        vars := mux.Vars(r)
        address := vars["address"]

        switch r.Method {
        case "GET":
            nonce, err := walletService.GetNonce(address)
            if err != nil {
                http.Error(w, err.Error(), http.StatusNotFound)
                return
            }

            json.NewEncoder(w).Encode(map[string]uint64{"nonce": nonce})
        default:
            http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
        }
    }).Methods("GET")

    r.HandleFunc("/transactions", func(w http.ResponseWriter, r *http.Request) {
        switch r.Method {
        case "POST":
            var tx Transaction
            err := json.NewDecoder(r.Body).Decode(&tx)
            if err != nil {
                http.Error(w, err.Error(), http.StatusBadRequest)
                return
            }

            createdTx, err := walletService.SendTransaction(tx.Sender, tx.Receiver, tx.Amount, tx.GasPrice, tx.GasLimit)
            if err != nil {
                http.Error(w, err.Error(), http.StatusBadRequest)
                return
            }

            json.NewEncoder(w).Encode(createdTx)
        default:
            http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
        }
    }).Methods("POST")

    r.HandleFunc("/wallets/{address}/transactions", func(w http.ResponseWriter, r *http.Request) {
        vars := mux.Vars(r)
        address := vars["address"]

        switch r.Method {
        case "GET":
            txs, err := walletService.GetTransactionHistory(address)
            if err != nil {
                http.Error(w, err.Error(), http.StatusNotFound)
                return
            }

            json.NewEncoder(w).Encode(txs)
        default:
            http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
        }
    }).Methods("GET")

    // Start the HTTP server
    log.Println("Starting server on :8080")
    log.Fatal(http.ListenAndServe(":8080", r))
}