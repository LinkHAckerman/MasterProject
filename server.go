package main

import (
    "crypto/sha256"
    "encoding/hex"
    "encoding/json"
    "log"
    "math/rand"
    "net/http"
    "os"
    "os/signal"
    "strconv"
    "strings"
    "sync"
    "syscall"
    "time"
)

// Wallet represents a simple wallet with an address and balances.
type Wallet struct {
    Address string            `json:"address"`
    Balances map[string]float64 `json:"balances"` // token symbol -> amount
}

// Transaction represents a minimal transaction payload.
type Transaction struct {
    From   string  `json:"from"`
    To     string  `json:"to"`
    Token  string  `json:"token"`
    Amount float64 `json:"amount"`
    Nonce  uint64  `json:"nonce"`
    Hash   string  `json:"hash,omitempty"`
}

var (
    wallets      = make(map[string]*Wallet)
    walletsMutex sync.RWMutex
    txNonce      uint64 = 0
    nonceMutex   sync.Mutex
)

func main() {
    // Seed random generator
    rand.Seed(time.Now().UnixNano())

    http.HandleFunc("/wallet/create", handleCreateWallet)
    http.HandleFunc("/wallet/", handleWallet) // prefix for balance endpoint
    http.HandleFunc("/transaction/relay", handleRelayTransaction)

    srv := &http.Server{Addr: ":8080"}

    // Graceful shutdown handling
    go func() {
        log.Println("Server listening on :8080")
        if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
            log.Fatalf("listen: %s\n", err)
        }
    }()

    quit := make(chan os.Signal, 1)
    signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
    <-quit
    log.Println("Shutting down server...")
    if err := srv.Close(); err != nil {
        log.Fatalf("Server Close: %v", err)
    }
    log.Println("Server stopped")
}

// handleCreateWallet creates a new mock wallet and returns its address.
func handleCreateWallet(w http.ResponseWriter, r *http.Request) {
    if r.Method != http.MethodPost {
        http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
        return
    }
    addr := generateAddress()
    wallet := &Wallet{Address: addr, Balances: map[string]float64{"ETH": 0, "USDT": 0}}
    walletsMutex.Lock()
    wallets[addr] = wallet
    walletsMutex.Unlock()

    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(wallet)
}

// handleWallet routes sub‑paths for wallet operations (currently only balance).
func handleWallet(w http.ResponseWriter, r *http.Request) {
    // Expected pattern: /wallet/{address}/balance
    parts := strings.Split(strings.TrimPrefix(r.URL.Path, "/wallet/"), "/")
    if len(parts) < 2 {
        http.Error(w, "Invalid wallet endpoint", http.StatusBadRequest)
        return
    }
    address := parts[0]
    action := parts[1]

    switch action {
    case "balance":
        handleGetBalance(w, r, address)
    default:
        http.Error(w, "Unsupported wallet action", http.StatusBadRequest)
    }
}

// handleGetBalance returns the balances of a wallet.
func handleGetBalance(w http.ResponseWriter, r *http.Request, address string) {
    if r.Method != http.MethodGet {
        http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
        return
    }
    walletsMutex.RLock()
    wallet, ok := wallets[address]
    walletsMutex.RUnlock()
    if !ok {
        http.Error(w, "Wallet not found", http.StatusNotFound)
        return
    }
    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(struct {
        Address  string            `json:"address"`
        Balances map[string]float64 `json:"balances"`
    }{Address: wallet.Address, Balances: wallet.Balances})
}

// handleRelayTransaction validates, updates balances, and returns a transaction hash.
func handleRelayTransaction(w http.ResponseWriter, r *http.Request) {
    if r.Method != http.MethodPost {
        http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
        return
    }
    var tx Transaction
    if err := json.NewDecoder(r.Body).Decode(&tx); err != nil {
        http.Error(w, "Invalid JSON payload", http.StatusBadRequest)
        return
    }
    // Basic validation
    if tx.From == "" || tx.To == "" || tx.Token == "" || tx.Amount <= 0 {
        http.Error(w, "Missing or invalid transaction fields", http.StatusBadRequest)
        return
    }
    // Retrieve wallets
    walletsMutex.RLock()
    fromWallet, fromOk := wallets[tx.From]
    toWallet, toOk := wallets[tx.To]
    walletsMutex.RUnlock()
    if !fromOk || !toOk {
        http.Error(w, "One or both wallets not found", http.StatusNotFound)
        return
    }
    // Check balance
    walletsMutex.RLock()
    balance, balOk := fromWallet.Balances[tx.Token]
    walletsMutex.RUnlock()
    if !balOk || balance < tx.Amount {
        http.Error(w, "Insufficient balance", http.StatusBadRequest)
        return
    }
    // Perform transfer atomically
    walletsMutex.Lock()
    fromWallet.Balances[tx.Token] -= tx.Amount
    toWallet.Balances[tx.Token] += tx.Amount
    walletsMutex.Unlock()

    // Generate nonce and hash
    nonceMutex.Lock()
    txNonce++
    tx.Nonce = txNonce
    nonceMutex.Unlock()
    tx.Hash = computeTxHash(tx)

    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(tx)
}

// generateAddress creates a pseudo‑random 40‑character hex address prefixed with 0x.
func generateAddress() string {
    b := make([]byte, 20) // 20 bytes = 40 hex chars
    _, err := rand.Read(b)
    if err != nil {
        // fallback to math/rand if crypto/rand fails (unlikely in this mock)
        for i := range b {
            b[i] = byte(rand.Intn(256))
        }
    }
    return "0x" + hex.EncodeToString(b)
}

// computeTxHash creates a deterministic hash of the transaction fields.
func computeTxHash(tx Transaction) string {
    // Concatenate fields in a stable order
    data := tx.From + tx.To + tx.Token + strconv.FormatFloat(tx.Amount, 'f', 8, 64) + strconv.FormatUint(tx.Nonce, 10)
    sum := sha256.Sum256([]byte(data))
    return "0x" + hex.EncodeToString(sum[:])
}
