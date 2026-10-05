package main

import (
    "context"
    "crypto/sha256"
    "encoding/hex"
    "encoding/json"
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

type WalletStore struct {
    mu sync.RWMutex
    balances map[string]map[string]float64 // address -> currency -> balance
}

func NewWalletStore() *WalletStore {
    return &WalletStore{
        balances: make(map[string]map[string]float64),
    }
}

func (ws *WalletStore) GetBalance(address, currency string) float64 {
    ws.mu.RLock()
    defer ws.mu.RUnlock()
    if curMap, ok := ws.balances[address]; ok {
        if bal, ok := curMap[currency]; ok {
            return bal
        }
    }
    return 0
}

func (ws *WalletStore) AdjustBalance(address, currency string, delta float64) {
    ws.mu.Lock()
    defer ws.mu.Unlock()
    if _, ok := ws.balances[address]; !ok {
        ws.balances[address] = make(map[string]float64)
    }
    ws.balances[address][currency] += delta
}

type BalanceResponse struct {
    Address  string  `json:"address"`
    Currency string  `json:"currency"`
    Balance  float64 `json:"balance"`
}

type TxRelayRequest struct {
    From     string  `json:"from"`
    To       string  `json:"to"`
    Currency string  `json:"currency"`
    Amount   float64 `json:"amount"`
    Nonce    uint64  `json:"nonce"`
}

type TxRelayResponse struct {
    TxHash string `json:"txHash"`
    Status string `json:"status"`
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(map[string]string{"status":"ok"})
}

func balanceHandler(store *WalletStore) http.HandlerFunc {
    return func(w http.ResponseWriter, r *http.Request) {
        vars := mux.Vars(r)
        address := vars["address"]
        currency := r.URL.Query().Get("currency")
        if currency == "" {
            currency = "ETH"
        }
        bal := store.GetBalance(address, currency)
        resp := BalanceResponse{Address: address, Currency: currency, Balance: bal}
        w.Header().Set("Content-Type", "application/json")
        json.NewEncoder(w).Encode(resp)
    }
}

func txRelayHandler(store *WalletStore) http.HandlerFunc {
    return func(w http.ResponseWriter, r *http.Request) {
        var req TxRelayRequest
        if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
            http.Error(w, "invalid JSON", http.StatusBadRequest)
            return
        }
        if req.From == "" || req.To == "" || req.Amount <= 0 {
            http.Error(w, "missing fields or non‑positive amount", http.StatusBadRequest)
            return
        }
        if store.GetBalance(req.From, req.Currency) < req.Amount {
            http.Error(w, "insufficient funds", http.StatusBadRequest)
            return
        }
        store.AdjustBalance(req.From, req.Currency, -req.Amount)
        store.AdjustBalance(req.To, req.Currency, req.Amount)
        hashInput := req.From + req.To + req.Currency + strconv.FormatFloat(req.Amount, 'f', 8, 64) + strconv.FormatUint(req.Nonce, 10)
        h := sha256.Sum256([]byte(hashInput))
        txHash := "0x" + hex.EncodeToString(h[:])
        resp := TxRelayResponse{TxHash: txHash, Status: "submitted"}
        w.Header().Set("Content-Type", "application/json")
        json.NewEncoder(w).Encode(resp)
    }
}

func main() {
    port := os.Getenv("PORT")
    if port == "" {
        port = "8080"
    }
    store := NewWalletStore()
    store.AdjustBalance("0xDEMOADDRESS", "ETH", 100.0)
    r := mux.NewRouter()
    r.HandleFunc("/health", healthHandler).Methods("GET")
    r.HandleFunc("/wallet/{address}/balance", balanceHandler(store)).Methods("GET")
    r.HandleFunc("/tx/relay", txRelayHandler(store)).Methods("POST")
    srv := &http.Server{Addr: ":" + port, Handler: r}
    go func() {
        if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
            log.Fatalf("listen: %s\n", err)
        }
    }()
    log.Printf("Server running on port %s", port)
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
