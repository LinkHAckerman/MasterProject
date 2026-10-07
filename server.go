package main

import (
    "crypto/sha256"
    "encoding/json"
    "fmt"
    "log"
    "net/http"
    "regexp"
    "strings"
    "sync"
)

type BalanceResponse struct {
    Address  string  `json:"address"`
    Balance  float64 `json:"balance"`
    Currency string  `json:"currency"`
}

type TxRequest struct {
    From     string  `json:"from"`
    To       string  `json:"to"`
    Amount   float64 `json:"amount"`
    Currency string  `json:"currency"`
}

type TxResponse struct {
    TxHash  string `json:"txHash"`
    Status  string `json:"status"`
    Message string `json:"message,omitempty"`
}

var (
    balances = map[string]float64{
        "0x1111111111111111111111111111111111111111": 1000.0,
    }
    mu sync.RWMutex
    ethAddressRegex = regexp.MustCompile(`^0x[0-9a-fA-F]{40}$`)
)

func main() {
    http.HandleFunc("/healthz", healthHandler)
    http.HandleFunc("/wallet/", walletHandler)
    http.HandleFunc("/transaction", transactionHandler)

    log.Println("Server starting on :8080")
    if err := http.ListenAndServe(":8080", nil); err != nil {
        log.Fatalf("Server failed: %v", err)
    }
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
    w.WriteHeader(http.StatusOK)
    w.Write([]byte("{\"status\":\"ok\"}"))
}

func walletHandler(w http.ResponseWriter, r *http.Request) {
    // Expected path: /wallet/{address}/balance
    parts := splitPath(r.URL.Path)
    if len(parts) != 3 || parts[2] != "balance" {
        http.Error(w, "invalid endpoint", http.StatusBadRequest)
        return
    }
    address := parts[1]
    if !ethAddressRegex.MatchString(address) {
        http.Error(w, "invalid address format", http.StatusBadRequest)
        return
    }

    mu.RLock()
    bal, ok := balances[address]
    mu.RUnlock()
    if !ok {
        bal = 0.0
    }

    resp := BalanceResponse{
        Address:  address,
        Balance:  bal,
        Currency: "ETH",
    }
    writeJSON(w, resp)
}

func transactionHandler(w http.ResponseWriter, r *http.Request) {
    if r.Method != http.MethodPost {
        http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
        return
    }
    var tx TxRequest
    if err := json.NewDecoder(r.Body).Decode(&tx); err != nil {
        http.Error(w, "invalid json", http.StatusBadRequest)
        return
    }
    if !ethAddressRegex.MatchString(tx.From) || !ethAddressRegex.MatchString(tx.To) {
        http.Error(w, "invalid address", http.StatusBadRequest)
        return
    }
    if tx.Amount <= 0 {
        http.Error(w, "amount must be positive", http.StatusBadRequest)
        return
    }

    // Simple atomic balance transfer
    mu.Lock()
    defer mu.Unlock()
    fromBal, ok := balances[tx.From]
    if !ok || fromBal < tx.Amount {
        resp := TxResponse{
            TxHash:  "",
            Status:  "failed",
            Message: "insufficient funds",
        }
        writeJSON(w, resp)
        return
    }
    balances[tx.From] = fromBal - tx.Amount
    balances[tx.To] = balances[tx.To] + tx.Amount

    // Mock tx hash
    txHash := mockTxHash(tx)

    resp := TxResponse{
        TxHash: txHash,
        Status: "success",
    }
    writeJSON(w, resp)
}

// helper functions

func splitPath(p string) []string {
    // remove leading and trailing slashes then split
    if len(p) == 0 {
        return []string{}
    }
    if p[0] == '/' {
        p = p[1:]
    }
    if len(p) > 0 && p[len(p)-1] == '/' {
        p = p[:len(p)-1]
    }
    if p == "" {
        return []string{}
    }
    return strings.Split(p, "/")
}

func writeJSON(w http.ResponseWriter, v interface{}) {
    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(v)
}

func mockTxHash(tx TxRequest) string {
    // deterministic mock hash using simple concatenation and sha256 from std lib
    data := tx.From + tx.To + fmt.Sprintf("%f", tx.Amount) + tx.Currency
    sum := sha256.Sum256([]byte(data))
    return "0x" + fmt.Sprintf("%x", sum[:])
}
