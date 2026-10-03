package main

import (
    "encoding/json"
    "fmt"
    "log"
    "net/http"
    "os"
    "os/signal"
    "syscall"
    "time"
    "github.com/gorilla/mux"
    "github.com/gorilla/websocket"
)

// Wallet represents a blockchain wallet
// with address, balance, and transaction history

// Transaction represents a blockchain transaction

// WebSocket connection pool
var connections = make(map[*websocket.Conn]bool)

// HTTP server with graceful shutdown
func main() {
    // Initialize router
    r := mux.NewRouter()

    // API endpoints
    r.HandleFunc("/api/wallet/{address}", getWalletHandler).Methods("GET")
    r.HandleFunc("/api/transactions", getTransactionsHandler).Methods("GET")
    r.HandleFunc("/api/broadcast", broadcastTransactionHandler).Methods("POST")
    r.HandleFunc("/ws", websocketHandler)

    // Start HTTP server
    srv := &http.Server{
        Handler:      r,
        Addr:         "127.0.0.1:8080",
        WriteTimeout: 15 * time.Second,
        ReadTimeout:  15 * time.Second,
    }

    // Graceful shutdown
    go func() {
        sigchan := make(chan os.Signal, 1)
        signal.Notify(sigchan, syscall.SIGINT, syscall.SIGTERM)
        <-sigchan
        log.Println("Shutting down server...")
        srv.Shutdown(context.Background())
    }()

    log.Println("Server starting on port 8080...")
    log.Fatal(srv.ListenAndServe())
}

// WebSocket handler for real-time updates
func websocketHandler(w http.ResponseWriter, r *http.Request) {
    // Upgrade HTTP connection to WebSocket
    conn, err := websocket.Upgrade(w, r, nil, 1024, 1024)
    if err != nil {
        log.Println(err)
        return
    }

    // Add connection to pool
    connections[conn] = true

    // Handle incoming messages
    go func() {
        defer func() {
            delete(connections, conn)
            conn.Close()
        }()

        for {
            _, msg, err := conn.ReadMessage()
            if err != nil {
                log.Println(err)
                break
            }

            // Broadcast message to all connections
            for c := range connections {
                if c != conn {
                    err := c.WriteMessage(websocket.TextMessage, msg)
                    if err != nil {
                        log.Println(err)
                        c.Close()
                        delete(connections, c)
                    }
                }
            }
        }
    }()
}

// API Handlers
func getWalletHandler(w http.ResponseWriter, r *http.Request) {
    vars := mux.Vars(r)
    address := vars["address"]

    // Mock wallet data
    wallet := Wallet{
        Address:    address,
        Balance:    14.852,
        ChainID:    "0x1",
        Network:   "Ethereum Mainnet",
        Tokens:    []Token{
            {Symbol: "ETH", Balance: 14.852},
            {Symbol: "USDT", Balance: 42500.00},
        },
    }

    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(wallet)
}

func getTransactionsHandler(w http.ResponseWriter, r *http.Request) {
    // Mock transaction data
    transactions := []Transaction{
        {
            Hash:     "0x123...",
            From:     "0x456...",
            To:       "0x789...",
            Value:    1.234,
            GasPrice: 18,
            Status:   "Confirmed",
            Timestamp: time.Now().Unix(),
        },
        // More transactions...
    }

    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(transactions)
}

func broadcastTransactionHandler(w http.ResponseWriter, r *http.Request) {
    var tx Transaction
    err := json.NewDecoder(r.Body).Decode(&tx)
    if err != nil {
        http.Error(w, err.Error(), http.StatusBadRequest)
        return
    }

    // Process transaction (mock)
    tx.Hash = Sha256.ComputeHash(fmt.Sprintf("%v", tx))
    tx.Status = "Pending"
    tx.Timestamp = time.Now().Unix()

    // Broadcast to WebSocket clients
    for conn := range connections {
        err := conn.WriteJSON(tx)
        if err != nil {
            log.Println(err)
            conn.Close()
            delete(connections, conn)
        }
    }

    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(tx)
}