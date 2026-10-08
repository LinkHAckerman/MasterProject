package main

import (
    "context"
    "encoding/json"
    "fmt"
    "log"
    "net/http"
    "os"
    "os/signal"
    "strconv"
    "sync"
    "syscall"
    "time"

    "github.com/gorilla/mux"
)

type Wallet struct {
    Address  string  `json:"address"`
    Balance  float64 `json:"balance"`
    Currency string  `json:"currency"`
}

type Transaction struct {
    From      string  `json:"from"`
    To        string  `json:"to"`
    Amount    float64 `json:"amount"`
    Currency  string  `json:"currency"`
    Nonce     uint64  `json:"nonce"`
    Signature string  `json:"signature"`
}

type Store struct {
    mu      sync.RWMutex
    wallets map[string]*Wallet
    nonces  map[string]uint64
}

func NewStore() *Store {
    return &Store{
        wallets: make(map[string]*Wallet),
        nonces:  make(map[string]uint64),
    }
}

func (s *Store) GetBalance(address string) (float64, bool) {
    s.mu.RLock()
    defer s.mu.RUnlock()
    w, ok := s.wallets[address]
    if !ok {
        return 0, false
    }
    return w.Balance, true
}

func (s *Store) EnsureWallet(address string) *Wallet {
    s.mu.Lock()
    defer s.mu.Unlock()
    w, ok := s.wallets[address]
    if !ok {
        w = &Wallet{Address: address, Balance: 0, Currency: "ETH"}
        s.wallets[address] = w
        s.nonces[address] = 0
    }
    return w
}

func (s *Store) IncrementNonce(address string) uint64 {
    s.mu.Lock()
    defer s.mu.Unlock()
    s.nonces[address]++
    return s.nonces[address]
}

func (s *Store) GetNonce(address string) uint64 {
    s.mu.RLock()
    defer s.mu.RUnlock()
    return s.nonces[address]
}

func (s *Store) ProcessTx(tx *Transaction) error {
    if tx.From == "" || tx.To == "" {
        return fmt.Errorf("missing from or to address")
    }
    if tx.Amount <= 0 {
        return fmt.Errorf("amount must be positive")
    }
    fromWallet := s.EnsureWallet(tx.From)
    toWallet := s.EnsureWallet(tx.To)
    expectedNonce := s.GetNonce(tx.From) + 1
    if tx.Nonce != expectedNonce {
        return fmt.Errorf("invalid nonce: expected %d, got %d", expectedNonce, tx.Nonce)
    }
    if fromWallet.Balance < tx.Amount {
        return fmt.Errorf("insufficient funds")
    }
    fromWallet.Balance -= tx.Amount
    toWallet.Balance += tx.Amount
    s.IncrementNonce(tx.From)
    return nil
}

// Middleware for logging each request
func loggingMiddleware(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        start := time.Now()
        next.ServeHTTP(w, r)
        log.Printf("%s %s %s", r.Method, r.RequestURI, time.Since(start))
    })
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
}

func balanceHandler(store *Store) http.HandlerFunc {
    return func(w http.ResponseWriter, r *http.Request) {
        vars := mux.Vars(r)
        address := vars["address"]
        balance, ok := store.GetBalance(address)
        w.Header().Set("Content-Type", "application/json")
        if !ok {
            w.WriteHeader(http.StatusNotFound)
            json.NewEncoder(w).Encode(map[string]string{"error": "wallet not found"})
            return
        }
        json.NewEncoder(w).Encode(map[string]interface{}{"address": address, "balance": balance})
    }
}

func relayHandler(store *Store) http.HandlerFunc {
    return func(w http.ResponseWriter, r *http.Request) {
        var tx Transaction
        if err := json.NewDecoder(r.Body).Decode(&tx); err != nil {
            w.WriteHeader(http.StatusBadRequest)
            json.NewEncoder(w).Encode(map[string]string{"error": "invalid JSON payload"})
            return
        }
        // In a real implementation, verify signature here.
        if err := store.ProcessTx(&tx); err != nil {
            w.WriteHeader(http.StatusBadRequest)
            json.NewEncoder(w).Encode(map[string]string{"error": err.Error()})
            return
        }
        w.WriteHeader(http.StatusAccepted)
        json.NewEncoder(w).Encode(map[string]string{"status": "transaction relayed"})
    }
}

func main() {
    port := os.Getenv("PORT")
    if port == "" {
        port = "8080"
    }
    store := NewStore()
    // Seed some demo wallets for quick testing
    store.EnsureWallet("0xDemoAlice").Balance = 10.0
    store.EnsureWallet("0xDemoBob").Balance = 5.0

    r := mux.NewRouter()
    r.Use(loggingMiddleware)
    r.HandleFunc("/health", healthHandler).Methods("GET")
    r.HandleFunc("/wallet/{address}/balance", balanceHandler(store)).Methods("GET")
    r.HandleFunc("/relay", relayHandler(store)).Methods("POST")

    srv := &http.Server{
        Addr:    ":" + port,
        Handler: r,
    }

    // Graceful shutdown handling
    go func() {
        log.Printf("Server listening on port %s", port)
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
