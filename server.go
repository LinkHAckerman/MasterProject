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
)

type Transaction struct {
    From    string `json:"from"`
    To      string `json:"to"`
    Value   string `json:"value"` // in wei as hex string
    Data    string `json:"data,omitempty"`
    Nonce   uint64 `json:"nonce,omitempty"`
    Gas     uint64 `json:"gas,omitempty"`
    GasPrice string `json:"gasPrice,omitempty"`
}

type Wallet struct {
    Address string `json:"address"`
    Balance string `json:"balance"` // in wei
    Nonce   uint64 `json:"nonce"`
}

type Server struct {
    mu      sync.RWMutex
    wallets map[string]*Wallet
    txPool  []Transaction
}

func NewServer() *Server {
    return &Server{
        wallets: make(map[string]*Wallet),
        txPool:  make([]Transaction, 0),
    }
}

// health handler
func (s *Server) healthHandler(w http.ResponseWriter, r *http.Request) {
    w.WriteHeader(http.StatusOK)
    w.Write([]byte(`{"status":"ok"}`))
}

// get wallet info
func (s *Server) walletHandler(w http.ResponseWriter, r *http.Request) {
    address := r.URL.Path[len("/wallet/"):]
    s.mu.RLock()
    wallet, ok := s.wallets[address]
    s.mu.RUnlock()
    if !ok {
        http.Error(w, "wallet not found", http.StatusNotFound)
        return
    }
    json.NewEncoder(w).Encode(wallet)
}

// relay transaction
func (s *Server) relayHandler(w http.ResponseWriter, r *http.Request) {
    var tx Transaction
    if err := json.NewDecoder(r.Body).Decode(&tx); err != nil {
        http.Error(w, "invalid json", http.StatusBadRequest)
        return
    }
    // basic validation
    if tx.From == "" || tx.To == "" || tx.Value == "" {
        http.Error(w, "missing required fields", http.StatusBadRequest)
        return
    }
    s.mu.Lock()
    s.txPool = append(s.txPool, tx)
    s.mu.Unlock()
    w.WriteHeader(http.StatusAccepted)
    w.Write([]byte(`{"status":"queued"}`))
}

// list pending txs
func (s *Server) pendingTxHandler(w http.ResponseWriter, r *http.Request) {
    s.mu.RLock()
    defer s.mu.RUnlock()
    json.NewEncoder(w).Encode(s.txPool)
}

// start background worker to simulate processing
func (s *Server) startProcessor(ctx context.Context) {
    ticker := time.NewTicker(2 * time.Second)
    defer ticker.Stop()
    for {
        select {
        case <-ctx.Done():
            log.Println("processor stopped")
            return
        case <-ticker.C:
            s.processBatch()
        }
    }
}

func (s *Server) processBatch() {
    s.mu.Lock()
    batch := s.txPool
    s.txPool = nil
    s.mu.Unlock()
    if len(batch) == 0 {
        return
    }
    log.Printf("processing %d transactions\n", len(batch))
    // Simulate state changes
    s.mu.Lock()
    for _, tx := range batch {
        fromW, ok := s.wallets[tx.From]
        if !ok {
            fromW = &Wallet{Address: tx.From, Balance: "0", Nonce: 0}
            s.wallets[tx.From] = fromW
        }
        toW, ok := s.wallets[tx.To]
        if !ok {
            toW = &Wallet{Address: tx.To, Balance: "0", Nonce: 0}
            s.wallets[tx.To] = toW
        }
        // For demo, just increment nonce, ignore balances
        fromW.Nonce++
        toW.Nonce++
    }
    s.mu.Unlock()
}

func main() {
    srv := NewServer()
    // seed a demo wallet
    srv.wallets["0xDEMO"] = &Wallet{Address: "0xDEMO", Balance: "1000000000000000000", Nonce: 0}
    mux := http.NewServeMux()
    mux.HandleFunc("/health", srv.healthHandler)
    mux.HandleFunc("/wallet/", srv.walletHandler) // expects /wallet/{address}
    mux.HandleFunc("/relay", srv.relayHandler)
    mux.HandleFunc("/pending", srv.pendingTxHandler)

    httpServer := &http.Server{
        Addr:    ":8080",
        Handler: mux,
    }

    // graceful shutdown
    stop := make(chan os.Signal, 1)
    signal.Notify(stop, os.Interrupt, syscall.SIGTERM)

    ctx, cancel := context.WithCancel(context.Background())
    go srv.startProcessor(ctx)

    go func() {
        log.Println("Server listening on :8080")
        if err := httpServer.ListenAndServe(); err != nil && err != http.ErrServerClosed {
            log.Fatalf("listen error: %v", err)
        }
    }()

    <-stop
    log.Println("Shutting down server...")
    cancel()
    ctxShutdown, _ := context.WithTimeout(context.Background(), 5*time.Second)
    if err := httpServer.Shutdown(ctxShutdown); err != nil {
        log.Fatalf("Shutdown error: %v", err)
    }
    log.Println("Server gracefully stopped")
}
