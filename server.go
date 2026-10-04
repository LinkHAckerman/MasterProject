package main

import (
    "context"
    "crypto/rand"
    "encoding/hex"
    "encoding/json"
    "log"
    "math/big"
    "net/http"
    "os"
    "os/signal"
    "strconv"
    "sync"
    "syscall"
    "time"
)

// Wallet represents a simple crypto wallet.
type Wallet struct {
    Address string             `json:"address"`
    Balance map[string]float64 `json:"balance"`
    Mutex   sync.Mutex         `json:"-"`
    // Transactions are stored per wallet for quick lookup.
    Transactions []Transaction `json:"-"`
}

// Transaction represents a mock transfer between wallets.
type Transaction struct {
    ID        string    `json:"id"`
    From      string    `json:"from"`
    To        string    `json:"to"`
    Token     string    `json:"token"`
    Amount    float64   `json:"amount"`
    Timestamp time.Time `json:"timestamp"`
}

var (
    wallets   = make(map[string]*Wallet)
    walletsMu sync.RWMutex
)

func main() {
    // Load configuration.
    port := getEnv("PORT", "8080")
    addr := ":" + port

    // Setup HTTP server and routes.
    mux := http.NewServeMux()
    mux.HandleFunc("/health", healthHandler)
    mux.HandleFunc("/wallets", walletsHandler)                     // POST create
    mux.HandleFunc("/wallets/", walletSubrouter) // catch all subpaths

    srv := &http.Server{
        Addr:    addr,
        Handler: loggingMiddleware(corsMiddleware(mux)),
    }

    // Graceful shutdown handling.
    go func() {
        log.Printf("Server listening on %s", addr)
        if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
            log.Fatalf("listen: %s\n", err)
        }
    }()

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

// healthHandler returns a simple OK status.
func healthHandler(w http.ResponseWriter, r *http.Request) {
    w.Header().Set("Content-Type", "application/json")
    w.WriteHeader(http.StatusOK)
    json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
}

// walletsHandler handles POST /wallets to create a new wallet.
func walletsHandler(w http.ResponseWriter, r *http.Request) {
    if r.Method != http.MethodPost {
        http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
        return
    }
    wallet := newWallet()
    walletsMu.Lock()
    wallets[wallet.Address] = wallet
    walletsMu.Unlock()

    w.Header().Set("Content-Type", "application/json")
    w.WriteHeader(http.StatusCreated)
    json.NewEncoder(w).Encode(wallet)
}

// walletSubrouter dispatches sub‑paths for a specific wallet.
func walletSubrouter(w http.ResponseWriter, r *http.Request) {
    // Expected pattern: /wallets/{address}[/*]
    path := r.URL.Path[len("/wallets/"):]
    // Extract address (up to next slash or end).
    var address, subPath string
    if idx := indexOf(path, '/'); idx != -1 {
        address = path[:idx]
        subPath = path[idx:]
    } else {
        address = path
        subPath = ""
    }

    walletsMu.RLock()
    wallet, exists := wallets[address]
    walletsMu.RUnlock()
    if !exists {
        http.Error(w, "Wallet not found", http.StatusNotFound)
        return
    }

    switch {
    case subPath == "" && r.Method == http.MethodGet:
        getWalletHandler(w, r, wallet)
    case subPath == "/transfer" && r.Method == http.MethodPost:
        transferHandler(w, r, wallet)
    case subPath == "/transactions" && r.Method == http.MethodGet:
        getTransactionsHandler(w, r, wallet)
    default:
        http.Error(w, "Not found", http.StatusNotFound)
    }
}

func getWalletHandler(w http.ResponseWriter, r *http.Request, wallet *Wallet) {
    wallet.Mutex.Lock()
    defer wallet.Mutex.Unlock()
    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(wallet)
}

func getTransactionsHandler(w http.ResponseWriter, r *http.Request, wallet *Wallet) {
    wallet.Mutex.Lock()
    defer wallet.Mutex.Unlock()
    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(wallet.Transactions)
}

// transferRequest defines the expected JSON payload for a transfer.
type transferRequest struct {
    To    string  `json:"to"`
    Token string  `json:"token"`
    Amount float64 `json:"amount"`
}

func transferHandler(w http.ResponseWriter, r *http.Request, fromWallet *Wallet) {
    var req transferRequest
    if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
        http.Error(w, "Invalid JSON payload", http.StatusBadRequest)
        return
    }
    if req.Amount <= 0 {
        http.Error(w, "Amount must be positive", http.StatusBadRequest)
        return
    }
    if req.Token == "" {
        http.Error(w, "Token field required", http.StatusBadRequest)
        return
    }

    // Locate destination wallet.
    walletsMu.RLock()
    toWallet, exists := wallets[req.To]
    walletsMu.RUnlock()
    if !exists {
        http.Error(w, "Destination wallet not found", http.StatusNotFound)
        return
    }

    // Perform atomic balance update.
    // Lock ordering: always lock lower address first to avoid deadlock.
    first, second := orderLocks(fromWallet, toWallet)
    first.Lock()
    second.Lock()
    defer second.Unlock()
    defer first.Unlock()

    // Ensure sender has sufficient balance.
    bal, ok := fromWallet.Balance[req.Token]
    if !ok || bal < req.Amount {
        http.Error(w, "Insufficient balance", http.StatusBadRequest)
        return
    }

    // Update balances.
    fromWallet.Balance[req.Token] -= req.Amount
    toWallet.Balance[req.Token] += req.Amount

    // Record transaction.
    tx := Transaction{
        ID:        generateTxID(),
        From:      fromWallet.Address,
        To:        toWallet.Address,
        Token:     req.Token,
        Amount:    req.Amount,
        Timestamp: time.Now().UTC(),
    }
    fromWallet.Transactions = append(fromWallet.Transactions, tx)
    toWallet.Transactions = append(toWallet.Transactions, tx)

    w.Header().Set("Content-Type", "application/json")
    w.WriteHeader(http.StatusCreated)
    json.NewEncoder(w).Encode(tx)
}

// orderLocks returns two mutex pointers ordered by wallet address to avoid deadlocks.
func orderLocks(a, b *Wallet) (*sync.Mutex, *sync.Mutex) {
    if a.Address < b.Address {
        return &a.Mutex, &b.Mutex
    }
    return &b.Mutex, &a.Mutex
}

func newWallet() *Wallet {
    addr := generateAddress()
    return &Wallet{
        Address: addr,
        Balance: map[string]float64{"ETH": 0, "USDT": 0, "BTC": 0},
    }
}

func generateAddress() string {
    // Generate 20 random bytes (Ethereum‑like address length).
    b := make([]byte, 20)
    _, err := rand.Read(b)
    if err != nil {
        // Fallback to pseudo‑random if crypto fails.
        for i := range b {
            n, _ := rand.Int(rand.Reader, big.NewInt(256))
            b[i] = byte(n.Int64())
        }
    }
    return "0x" + hex.EncodeToString(b)
}

func generateTxID() string {
    ts := strconv.FormatInt(time.Now().UnixNano(), 10)
    rnd := make([]byte, 4)
    rand.Read(rnd)
    return "tx_" + ts + "_" + hex.EncodeToString(rnd)
}

func getEnv(key, fallback string) string {
    if value, exists := os.LookupEnv(key); exists {
        return value
    }
    return fallback
}

// Simple CORS middleware allowing any origin (adjust for production).
func corsMiddleware(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        w.Header().Set("Access-Control-Allow-Origin", "*")
        w.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")
        if r.Method == http.MethodOptions {
            w.WriteHeader(http.StatusNoContent)
            return
        }
        next.ServeHTTP(w, r)
    })
}

// loggingMiddleware logs each request with method, path and duration.
func loggingMiddleware(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        start := time.Now()
        next.ServeHTTP(w, r)
        log.Printf("%s %s %s", r.Method, r.URL.Path, time.Since(start))
    })
}

// indexOf returns the index of the first occurrence of sep in s, or -1.
func indexOf(s string, sep byte) int {
    for i := 0; i < len(s); i++ {
        if s[i] == sep {
            return i
        }
    }
    return -1
}
