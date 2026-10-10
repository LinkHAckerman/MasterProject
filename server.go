package main

import (
    "context"
    "encoding/json"
    "fmt"
    "log"
    "net/http"
    "os"
    "os/signal"
    "sync"
    "syscall"
    "time"

    "github.com/gorilla/mux"
)

type Wallet struct {
    Address string             `json:\"address\"`
    Balance map[string]float64 `json:\"balance\"`
}

type WalletStore struct {
    mu      sync.RWMutex
    wallets map[string]*Wallet
}

func NewWalletStore() *WalletStore {
    return &WalletStore{
        wallets: make(map[string]*Wallet),
    }
}

func (s *WalletStore) Get(address string) (*Wallet, bool) {
    s.mu.RLock()
    defer s.mu.RUnlock()
    w, ok := s.wallets[address]
    return w, ok
}

func (s *WalletStore) Create(address string) (*Wallet, error) {
    s.mu.Lock()
    defer s.mu.Unlock()
    if _, exists := s.wallets[address]; exists {
        return nil, fmt.Errorf("wallet already exists")
    }
    w := &Wallet{
        Address: address,
        Balance: make(map[string]float64),
    }
    s.wallets[address] = w
    return w, nil
}

func (s *WalletStore) Transfer(from, to, token string, amount float64) error {
    if amount <= 0 {
        return fmt.Errorf("amount must be positive")
    }
    s.mu.Lock()
    defer s.mu.Unlock()
    src, ok := s.wallets[from]
    if !ok {
        return fmt.Errorf("source wallet not found")
    }
    dst, ok := s.wallets[to]
    if !ok {
        return fmt.Errorf("destination wallet not found")
    }
    if src.Balance[token] < amount {
        return fmt.Errorf("insufficient funds")
    }
    src.Balance[token] -= amount
    dst.Balance[token] += amount
    return nil
}

func getWalletHandler(store *WalletStore) http.HandlerFunc {
    return func(w http.ResponseWriter, r *http.Request) {
        vars := mux.Vars(r)
        address := vars["address"]
        wallet, ok := store.Get(address)
        if !ok {
            http.Error(w, "wallet not found", http.StatusNotFound)
            return
        }
        json.NewEncoder(w).Encode(wallet)
    }
}

func createWalletHandler(store *WalletStore) http.HandlerFunc {
    type req struct {
        Address string `json:\"address\"`
    }
    return func(w http.ResponseWriter, r *http.Request) {
        var payload req
        if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
            http.Error(w, "invalid json", http.StatusBadRequest)
            return
        }
        if payload.Address == "" {
            http.Error(w, "address required", http.StatusBadRequest)
            return
        }
        wallet, err := store.Create(payload.Address)
        if err != nil {
            http.Error(w, err.Error(), http.StatusConflict)
            return
        }
        w.WriteHeader(http.StatusCreated)
        json.NewEncoder(w).Encode(wallet)
    }
}

func transferHandler(store *WalletStore) http.HandlerFunc {
    type req struct {
        To    string  `json:\"to\"`
        Token string  `json:\"token\"`
        Amount float64 `json:\"amount\"`
    }
    return func(w http.ResponseWriter, r *http.Request) {
        vars := mux.Vars(r)
        from := vars["address"]
        var payload req
        if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
            http.Error(w, "invalid json", http.StatusBadRequest)
            return
        }
        if err := store.Transfer(from, payload.To, payload.Token, payload.Amount); err != nil {
            http.Error(w, err.Error(), http.StatusBadRequest)
            return
        }
        w.WriteHeader(http.StatusNoContent)
    }
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
    w.WriteHeader(http.StatusOK)
    w.Write([]byte("OK"))
}

func loggingMiddleware(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        start := time.Now()
        next.ServeHTTP(w, r)
        log.Printf("%s %s %s", r.Method, r.RequestURI, time.Since(start))
    })
}

func corsMiddleware(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        w.Header().Set("Access-Control-Allow-Origin", "*")
        w.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS, PUT, DELETE")
        w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")
        if r.Method == http.MethodOptions {
            w.WriteHeader(http.StatusNoContent)
            return
        }
        next.ServeHTTP(w, r)
    })
}

func main() {
    store := NewWalletStore()
    r := mux.NewRouter()
    r.Use(loggingMiddleware, corsMiddleware)

    r.HandleFunc("/health", healthHandler).Methods("GET")
    r.HandleFunc("/wallet", createWalletHandler(store)).Methods("POST")
    r.HandleFunc("/wallet/{address}", getWalletHandler(store)).Methods("GET")
    r.HandleFunc("/wallet/{address}/transfer", transferHandler(store)).Methods("POST")

    srv := &http.Server{
        Addr:    ":8080",
        Handler: r,
    }

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

    ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
    defer cancel()
    if err := srv.Shutdown(ctx); err != nil {
        log.Fatalf("Server forced to shutdown: %v", err)
    }
    log.Println("Server exiting")
}
