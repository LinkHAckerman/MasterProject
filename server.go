package main

import (
    "crypto/rand"
    "encoding/hex"
    "encoding/json"
    "fmt"
    "log"
    "math/big"
    "net/http"
    "os"
    "strings"
    "sync"
    "time"

    "github.com/gorilla/mux"
    "github.com/golang-jwt/jwt/v5"
    "golang.org/x/net/context"
)

// =============================
// Types & Data Structures
// =============================

type Wallet struct {
    Address string            `json:"address"`
    // Balances stored as token symbol -> amount (big.Int for precision)
    Balances map[string]*big.Int `json:"balances"`
}

type Transaction struct {
    ID        string    `json:"id"`
    From      string    `json:"from"`
    To        string    `json:"to"`
    Token     string    `json:"token"`
    Amount    string    `json:"amount"` // string representation for JSON safety
    Timestamp int64     `json:"timestamp"`
    Status    string    `json:"status"`
}

type Claims struct {
    Address string `json:"address"`
    jwt.RegisteredClaims
}

// =============================
// In‑memory Store (thread‑safe)
// =============================

var (
    wallets      = make(map[string]*Wallet)
    txStore      = make(map[string]*Transaction)
    storeMutex   sync.RWMutex
    jwtSecret    []byte
    tokenExpiry  = time.Hour * 24
)

// =============================
// Helper Functions
// =============================

func generateAddress() (string, error) {
    // 20‑byte (160‑bit) address like Ethereum
    b := make([]byte, 20)
    _, err := rand.Read(b)
    if err != nil {
        return "", err
    }
    return "0x" + hex.EncodeToString(b), nil
}

func parseAmount(s string) (*big.Int, error) {
    // Accept decimal string, convert to wei‑like integer (assume 18 decimals)
    // For simplicity we treat the string as integer units.
    i := new(big.Int)
    _, ok := i.SetString(s, 10)
    if !ok {
        return nil, fmt.Errorf("invalid amount %s", s)
    }
    if i.Sign() < 0 {
        return nil, fmt.Errorf("amount must be non‑negative")
    }
    return i, nil
}

func jsonResponse(w http.ResponseWriter, status int, payload interface{}) {
    w.Header().Set("Content-Type", "application/json")
    w.WriteHeader(status)
    if payload != nil {
        json.NewEncoder(w).Encode(payload)
    }
}

// =============================
// JWT Middleware
// =============================

func jwtMiddleware(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        authHeader := r.Header.Get("Authorization")
        if authHeader == "" {
            jsonResponse(w, http.StatusUnauthorized, map[string]string{"error": "missing Authorization header"})
            return
        }
        parts := strings.SplitN(authHeader, " ", 2)
        if len(parts) != 2 || strings.ToLower(parts[0]) != "bearer" {
            jsonResponse(w, http.StatusUnauthorized, map[string]string{"error": "invalid Authorization format"})
            return
        }
        tokenStr := parts[1]
        token, err := jwt.ParseWithClaims(tokenStr, &Claims{}, func(token *jwt.Token) (interface{}, error) {
            return jwtSecret, nil
        })
        if err != nil || !token.Valid {
            jsonResponse(w, http.StatusUnauthorized, map[string]string{"error": "invalid token"})
            return
        }
        claims, ok := token.Claims.(*Claims)
        if !ok {
            jsonResponse(w, http.StatusUnauthorized, map[string]string{"error": "invalid token claims"})
            return
        }
        // Attach address to request context
        ctx := context.WithValue(r.Context(), "address", claims.Address)
        next.ServeHTTP(w, r.WithContext(ctx))
    })
}

func getAddressFromContext(r *http.Request) (string, bool) {
    addr, ok := r.Context().Value("address").(string)
    return addr, ok
}

// =============================
// Handlers
// =============================

// POST /wallet/create – creates a new wallet and returns JWT
func createWalletHandler(w http.ResponseWriter, r *http.Request) {
    addr, err := generateAddress()
    if err != nil {
        jsonResponse(w, http.StatusInternalServerError, map[string]string{"error": "failed to generate address"})
        return
    }
    wallet := &Wallet{Address: addr, Balances: make(map[string]*big.Int)}
    // Give some mock ETH for demo purposes
    wallet.Balances["ETH"] = big.NewInt(1e18) // 1 ETH in wei‑like units

    storeMutex.Lock()
    wallets[addr] = wallet
    storeMutex.Unlock()

    // Issue JWT (no password for demo)
    claims := Claims{Address: addr, RegisteredClaims: jwt.RegisteredClaims{ExpiresAt: jwt.NewNumericDate(time.Now().Add(tokenExpiry))}}
    token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
    tokenStr, err := token.SignedString(jwtSecret)
    if err != nil {
        jsonResponse(w, http.StatusInternalServerError, map[string]string{"error": "failed to sign token"})
        return
    }

    jsonResponse(w, http.StatusCreated, map[string]string{"address": addr, "token": tokenStr})
}

// GET /wallet/{address} – returns wallet balances (auth optional, but if auth present must match address)
func getWalletHandler(w http.ResponseWriter, r *http.Request) {
    vars := mux.Vars(r)
    addr := vars["address"]

    // If request is authenticated, ensure the caller is requesting its own wallet
    if authAddr, ok := getAddressFromContext(r); ok && authAddr != addr {
        jsonResponse(w, http.StatusForbidden, map[string]string{"error": "cannot access other wallets"})
        return
    }

    storeMutex.RLock()
    wallet, exists := wallets[addr]
    storeMutex.RUnlock()
    if !exists {
        jsonResponse(w, http.StatusNotFound, map[string]string{"error": "wallet not found"})
        return
    }
    // Convert balances to string for JSON safety
    balOut := make(map[string]string)
    for token, amount := range wallet.Balances {
        balOut[token] = amount.String()
    }
    jsonResponse(w, http.StatusOK, map[string]interface{}{ "address": wallet.Address, "balances": balOut })
}

// POST /transaction – submit a transaction (requires auth)
func submitTransactionHandler(w http.ResponseWriter, r *http.Request) {
    // Ensure caller is authenticated
    fromAddr, ok := getAddressFromContext(r)
    if !ok {
        jsonResponse(w, http.StatusUnauthorized, map[string]string{"error": "authentication required"})
        return
    }
    var req struct {
        To    string `json:"to"`
        Token string `json:"token"`
        Amount string `json:"amount"`
    }
    if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
        jsonResponse(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON payload"})
        return
    }
    if req.To == "" || req.Token == "" || req.Amount == "" {
        jsonResponse(w, http.StatusBadRequest, map[string]string{"error": "missing fields"})
        return
    }
    amount, err := parseAmount(req.Amount)
    if err != nil {
        jsonResponse(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
        return
    }

    // Basic validation & balance check
    storeMutex.Lock()
    defer storeMutex.Unlock()
    fromWallet, ok := wallets[fromAddr]
    if !ok {
        jsonResponse(w, http.StatusNotFound, map[string]string{"error": "sender wallet not found"})
        return
    }
    toWallet, ok := wallets[req.To]
    if !ok {
        jsonResponse(w, http.StatusNotFound, map[string]string{"error": "recipient wallet not found"})
        return
    }
    bal, ok := fromWallet.Balances[req.Token]
    if !ok || bal.Cmp(amount) < 0 {
        jsonResponse(w, http.StatusBadRequest, map[string]string{"error": "insufficient balance"})
        return
    }
    // Perform transfer atomically
    bal.Sub(bal, amount)
    if _, exists := toWallet.Balances[req.Token]; !exists {
        toWallet.Balances[req.Token] = big.NewInt(0)
    }
    toWallet.Balances[req.Token].Add(toWallet.Balances[req.Token], amount)

    // Create transaction record
    txIDBytes := make([]byte, 16)
    rand.Read(txIDBytes)
    txID := hex.EncodeToString(txIDBytes)
    tx := &Transaction{
        ID:        txID,
        From:      fromAddr,
        To:        req.To,
        Token:     req.Token,
        Amount:    amount.String(),
        Timestamp: time.Now().Unix(),
        Status:    "confirmed",
    }
    txStore[txID] = tx

    jsonResponse(w, http.StatusCreated, tx)
}

// GET /transaction/{id} – fetch transaction status (auth optional)
func getTransactionHandler(w http.ResponseWriter, r *http.Request) {
    vars := mux.Vars(r)
    txID := vars["id"]
    storeMutex.RLock()
    tx, exists := txStore[txID]
    storeMutex.RUnlock()
    if !exists {
        jsonResponse(w, http.StatusNotFound, map[string]string{"error": "transaction not found"})
        return
    }
    jsonResponse(w, http.StatusOK, tx)
}

// GET /health – simple health check
func healthHandler(w http.ResponseWriter, r *http.Request) {
    jsonResponse(w, http.StatusOK, map[string]string{"status": "ok"})
}

// =============================
// Router Setup
// =============================

func newRouter() *mux.Router {
    r := mux.NewRouter()
    // Public endpoints
    r.HandleFunc("/health", healthHandler).Methods("GET")
    r.HandleFunc("/wallet/create", createWalletHandler).Methods("POST")
    r.HandleFunc("/wallet/{address}", getWalletHandler).Methods("GET")
    r.HandleFunc("/transaction/{id}", getTransactionHandler).Methods("GET")

    // Protected endpoints – require JWT
    protected := r.PathPrefix("/api").Subrouter()
    protected.Use(jwtMiddleware)
    protected.HandleFunc("/transaction", submitTransactionHandler).Methods("POST")

    return r
}

// =============================
// Main Entry Point
// =============================

func main() {
    // Load JWT secret – in production use a secure secret manager
    secret := os.Getenv("MAGNUM_JWT_SECRET")
    if secret == "" {
        // Fallback for local dev – NOT for production
        secret = "dev-secret-key-please-change"
    }
    jwtSecret = []byte(secret)

    port := os.Getenv("MAGNUM_PORT")
    if port == "" {
        port = "8080"
    }

    router := newRouter()
    srv := &http.Server{
        Addr:    ":" + port,
        Handler: router,
        // Good defaults for timeouts to mitigate Slowloris attacks
        ReadTimeout:  15 * time.Second,
        WriteTimeout: 15 * time.Second,
        IdleTimeout:  60 * time.Second,
    }

    log.Printf("🚀 Magnum Opus Go microservice listening on %s", srv.Addr)
    if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
        log.Fatalf("Server error: %v", err)
    }
}
