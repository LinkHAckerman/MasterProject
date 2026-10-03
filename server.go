package main

import (
    "context"
    "encoding/json"
    "log"
    "net/http"
    "os"
    "os/signal"
    "sync"
    "syscall"
    "time"

    "github.com/google/uuid"
    "github.com/gorilla/mux"
    "golang.org/x/time/rate"
)

type Transaction struct {
    ID        string    `json:"id"`
    From      string    `json:"from"`
    To        string    `json:"to"`
    Amount    string    `json:"amount"`
    Token     string    `json:"token"`
    ChainID   string    `json:"chainId"`
    Timestamp time.Time `json:"timestamp"`
    Status    string    `json:"status"`
}

type TransactionRequest struct {
    From    string `json:"from"`
    To      string `json:"to"`
    Amount  string `json:"amount"`
    Token   string `json:"token"`
    ChainID string `json:"chainId"`
}

type TransactionResponse struct {
    ID     string `json:"id"`
    Status string `json:"status"`
}

type Store struct {
    sync.RWMutex
    txs map[string]Transaction
}

var (
    store   = Store{txs: make(map[string]Transaction)}
    limiter = rate.NewLimiter(rate.Every(100*time.Millisecond), 5) // 5 req/s burst
)

func main() {
    r := mux.NewRouter()
    r.Use(corsMiddleware)
    r.Use(rateLimitMiddleware)

    r.HandleFunc("/health", healthHandler).Methods("GET")
    r.HandleFunc("/relay", relayHandler).Methods("POST")
    r.HandleFunc("/tx/{id}", txStatusHandler).Methods("GET")

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

func healthHandler(w http.ResponseWriter, r *http.Request) {
    w.WriteHeader(http.StatusOK)
    w.Write([]byte(`{"status":"ok"}`))
}

func relayHandler(w http.ResponseWriter, r *http.Request) {
    var req TransactionRequest
    if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
        http.Error(w, "invalid JSON", http.StatusBadRequest)
        return
    }
    if !validateTxRequest(req) {
        http.Error(w, "missing required fields", http.StatusBadRequest)
        return
    }

    tx := Transaction{
        ID:        uuid.New().String(),
        From:      req.From,
        To:        req.To,
        Amount:    req.Amount,
        Token:     req.Token,
        ChainID:   req.ChainID,
        Timestamp: time.Now().UTC(),
        Status:    "pending",
    }

    store.Lock()
    store.txs[tx.ID] = tx
    store.Unlock()

    // Simulate async processing
    go processTransaction(tx.ID)

    resp := TransactionResponse{ID: tx.ID, Status: tx.Status}
    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(resp)
}

func txStatusHandler(w http.ResponseWriter, r *http.Request) {
    vars := mux.Vars(r)
    id := vars["id"]

    store.RLock()
    tx, ok := store.txs[id]
    store.RUnlock()
    if !ok {
        http.Error(w, "transaction not found", http.StatusNotFound)
        return
    }
    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(tx)
}

func validateTxRequest(req TransactionRequest) bool {
    return req.From != "" && req.To != "" && req.Amount != "" && req.Token != "" && req.ChainID != ""
}

// Mock processing: after a short delay mark as confirmed
func processTransaction(id string) {
    time.Sleep(2 * time.Second)
    store.Lock()
    tx, ok := store.txs[id]
    if ok {
        tx.Status = "confirmed"
        store.txs[id] = tx
    }
    store.Unlock()
}

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

func rateLimitMiddleware(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        if !limiter.Allow() {
            http.Error(w, "rate limit exceeded", http.StatusTooManyRequests)
            return
        }
        next.ServeHTTP(w, r)
    })
}