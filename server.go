package main

import (
    "crypto/sha256"
    "encoding/hex"
    "encoding/json"
    "log"
    "net/http"
    "strconv"
    "strings"
    "sync"
    "time"
)

type Transaction struct {
    ID        string  `json:"id"`
    From      string  `json:"from"`
    To        string  `json:"to"`
    Amount    float64 `json:"amount"`
    Timestamp int64   `json:"timestamp"`
    Hash      string  `json:"hash"`
}

type Store struct {
    mu   sync.RWMutex
    data map[string]Transaction
}

func NewStore() *Store {
    return &Store{
        data: make(map[string]Transaction),
    }
}

func (s *Store) Add(tx Transaction) {
    s.mu.Lock()
    defer s.mu.Unlock()
    s.data[tx.ID] = tx
}

func (s *Store) Get(id string) (Transaction, bool) {
    s.mu.RLock()
    defer s.mu.RUnlock()
    tx, ok := s.data[id]
    return tx, ok
}

func (s *Store) List() []Transaction {
    s.mu.RLock()
    defer s.mu.RUnlock()
    txs := make([]Transaction, 0, len(s.data))
    for _, tx := range s.data {
        txs = append(txs, tx)
    }
    return txs
}

func computeHash(tx Transaction) string {
    h := sha256.New()
    h.Write([]byte(tx.ID))
    h.Write([]byte(tx.From))
    h.Write([]byte(tx.To))
    amtBytes := []byte(strconv.FormatFloat(tx.Amount, 'f', 8, 64))
    h.Write(amtBytes)
    h.Write([]byte(strconv.FormatInt(tx.Timestamp, 10)))
    return "0x" + hex.EncodeToString(h.Sum(nil))
}

// Handlers

func submitTxHandler(store *Store) http.HandlerFunc {
    return func(w http.ResponseWriter, r *http.Request) {
        if r.Method != http.MethodPost {
            http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
            return
        }
        var payload struct {
            From   string  `json:"from"`
            To     string  `json:"to"`
            Amount float64 `json:"amount"`
        }
        if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
            http.Error(w, "invalid json payload", http.StatusBadRequest)
            return
        }
        if payload.From == "" || payload.To == "" || payload.Amount <= 0 {
            http.Error(w, "missing or invalid fields", http.StatusBadRequest)
            return
        }
        tx := Transaction{
            ID:        strconv.FormatInt(time.Now().UnixNano(), 10),
            From:      payload.From,
            To:        payload.To,
            Amount:    payload.Amount,
            Timestamp: time.Now().Unix(),
        }
        tx.Hash = computeHash(tx)
        store.Add(tx)

        w.Header().Set("Content-Type", "application/json")
        json.NewEncoder(w).Encode(tx)
    }
}

func getTxHandler(store *Store) http.HandlerFunc {
    return func(w http.ResponseWriter, r *http.Request) {
        parts := strings.Split(strings.Trim(r.URL.Path, "/"), "/")
        if len(parts) != 2 {
            http.Error(w, "invalid path", http.StatusBadRequest)
            return
        }
        id := parts[1]
        tx, ok := store.Get(id)
        if !ok {
            http.Error(w, "transaction not found", http.StatusNotFound)
            return
        }
        w.Header().Set("Content-Type", "application/json")
        json.NewEncoder(w).Encode(tx)
    }
}

func listTxHandler(store *Store) http.HandlerFunc {
    return func(w http.ResponseWriter, r *http.Request) {
        txs := store.List()
        w.Header().Set("Content-Type", "application/json")
        json.NewEncoder(w).Encode(txs)
    }
}

// CORS middleware
func cors(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        w.Header().Set("Access-Control-Allow-Origin", "*")
        w.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        w.Header().Set("Access-Control-Allow-Headers", "Content-Type")
        if r.Method == http.MethodOptions {
            w.WriteHeader(http.StatusOK)
            return
        }
        next.ServeHTTP(w, r)
    })
}

func main() {
    store := NewStore()
    mux := http.NewServeMux()
    mux.HandleFunc("/tx", func(w http.ResponseWriter, r *http.Request) {
        if r.Method == http.MethodPost {
            submitTxHandler(store)(w, r)
            return
        }
        if r.Method == http.MethodGet {
            listTxHandler(store)(w, r)
            return
        }
        http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
    })
    mux.HandleFunc("/tx/", getTxHandler(store))

    handler := cors(mux)

    srv := &http.Server{
        Addr:    ":8080",
        Handler: handler,
    }

    log.Println("Magnum Opus wallet relay service listening on http://localhost:8080")
    if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
        log.Fatalf("server error: %v", err)
    }
}