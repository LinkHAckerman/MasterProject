package main

import (
    "encoding/json"
    "log"
    "net/http"
    "sync"
    "time"
    "github.com/google/uuid"
)

// Wallet represents a simple token balance map.
type Wallet struct {
    Address string             `json:"address"`
    Balance map[string]float64 `json:"balance"`
}

// Transaction records a relayed transfer.
type Transaction struct {
    ID        string  `json:"id"`
    From      string  `json:"from"`
    To        string  `json:"to"`
    Token     string  `json:"token"`
    Amount    float64 `json:"amount"`
    Timestamp int64   `json:"timestamp"`
    Status    string  `json:"status"`
}

var (
    wallets = make(map[string]*Wallet)
    txPool  = make(map[string]*Transaction)
    mu      sync.RWMutex
)

func initDemoData() {
    w1 := &Wallet{Address: "0xDEMO1", Balance: map[string]float64{"ETH": 10.0, "USDT": 5000.0}}
    w2 := &Wallet{Address: "0xDEMO2", Balance: map[string]float64{"ETH": 2.5, "USDT": 1200.0}}
    mu.Lock()
    wallets[w1.Address] = w1
    wallets[w2.Address] = w2
    mu.Unlock()
}

func main() {
    initDemoData()
    http.HandleFunc("/wallet/balance", walletBalanceHandler)
    http.HandleFunc("/transaction/relay", transactionRelayHandler)
    http.HandleFunc("/transaction/status", transactionStatusHandler)
    srv := &http.Server{Addr: ":8080", ReadHeaderTimeout: 5 * time.Second}
    log.Println("Magnum Opus wallet relay service listening on :8080")
    if err := srv.ListenAndServe(); err != nil {
        log.Fatalf("server failed: %v", err)
    }
}

// walletBalanceHandler returns the balance of a wallet.
// GET /wallet/balance?address=0xDEMO1
func walletBalanceHandler(w http.ResponseWriter, r *http.Request) {
    address := r.URL.Query().Get("address")
    if address == "" {
        http.Error(w, "address query param required", http.StatusBadRequest)
        return
    }
    mu.RLock()
    wallet, ok := wallets[address]
    mu.RUnlock()
    if !ok {
        http.Error(w, "wallet not found", http.StatusNotFound)
        return
    }
    resp, _ := json.Marshal(wallet)
    w.Header().Set("Content-Type", "application/json")
    w.Write(resp)
}

// transactionRelayHandler validates and queues a transaction.
// POST /transaction/relay with JSON body {"from":"0xDEMO1","to":"0xDEMO2","token":"ETH","amount":0.5}
func transactionRelayHandler(w http.ResponseWriter, r *http.Request) {
    if r.Method != http.MethodPost {
        http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
        return
    }
    var req struct {
        From   string  `json:"from"`
        To     string  `json:"to"`
        Token  string  `json:"token"`
        Amount float64 `json:"amount"`
    }
    if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
        http.Error(w, "invalid json", http.StatusBadRequest)
        return
    }
    if req.From == "" || req.To == "" || req.Token == "" || req.Amount <= 0 {
        http.Error(w, "missing or invalid fields", http.StatusBadRequest)
        return
    }
    mu.Lock()
    fromWallet, ok1 := wallets[req.From]
    toWallet, ok2 := wallets[req.To]
    mu.Unlock()
    if !ok1 || !ok2 {
        http.Error(w, "source or destination wallet not found", http.StatusNotFound)
        return
    }
    mu.Lock()
    balance, ok := fromWallet.Balance[req.Token]
    if !ok || balance < req.Amount {
        mu.Unlock()
        http.Error(w, "insufficient balance", http.StatusBadRequest)
        return
    }
    // deduct and credit
    fromWallet.Balance[req.Token] -= req.Amount
    toWallet.Balance[req.Token] += req.Amount
    mu.Unlock()

    tx := &Transaction{
        ID:        uuid.New().String(),
        From:      req.From,
        To:        req.To,
        Token:     req.Token,
        Amount:    req.Amount,
        Timestamp: time.Now().Unix(),
        Status:    "confirmed",
    }
    mu.Lock()
    txPool[tx.ID] = tx
    mu.Unlock()

    resp, _ := json.Marshal(tx)
    w.Header().Set("Content-Type", "application/json")
    w.WriteHeader(http.StatusCreated)
    w.Write(resp)
}

// transactionStatusHandler returns status of a transaction by id.
// GET /transaction/status?id=<txid>
func transactionStatusHandler(w http.ResponseWriter, r *http.Request) {
    id := r.URL.Query().Get("id")
    if id == "" {
        http.Error(w, "id query param required", http.StatusBadRequest)
        return
    }
    mu.RLock()
    tx, ok := txPool[id]
    mu.RUnlock()
    if !ok {
        http.Error(w, "transaction not found", http.StatusNotFound)
        return
    }
    resp, _ := json.Marshal(tx)
    w.Header().Set("Content-Type", "application/json")
    w.Write(resp)
}
