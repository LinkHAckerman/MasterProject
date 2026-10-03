package main

import (
    "encoding/json"
    "fmt"
    "log"
    "net/http"
    "os"
    "time"
    "github.com/gorilla/mux"
    "github.com/gorilla/websocket"
)

// WebSocket upgrader
var upgrader = websocket.Upgrader{
    ReadBufferSize:  1024,
    WriteBufferSize: 1024,
    CheckOrigin: func(r *http.Request) bool {
        return true
    },
}

// Client represents a WebSocket client
var clients = make(map[*websocket.Conn]bool)
var broadcast = make(chan Message)

// Message represents a WebSocket message

type Message struct {
    Type    string      `json:"type"`
    Payload json.RawMessage `json:"payload"`
}

// WalletService represents the wallet service

type WalletService struct {
    Address string  `json:"address"`
    Balance float64 `json:"balance"`
}

// Transaction represents a blockchain transaction

type Transaction struct {
    From     string  `json:"from"`
    To       string  `json:"to"`
    Value    float64 `json:"value"`
    GasPrice float64 `json:"gasPrice"`
    GasLimit uint64  `json:"gasLimit"`
    Nonce    uint64  `json:"nonce"`
    Data     string  `json:"data"`
}

// GasPrice represents the current gas prices

type GasPrice struct {
    Slow     float64 `json:"slow"`
    Standard float64 `json:"standard"`
    Fast     float64 `json:"fast"`
}

// MarketData represents the current market data

type MarketData struct {
    Pair      string  `json:"pair"`
    Price     float64 `json:"price"`
    Change24h float64 `json:"change24h"`
    Volume24h float64 `json:"volume24h"`
    High24h   float64 `json:"high24h"`
    Low24h    float64 `json:"low24h"`
}

// OrderBook represents the current order book

type OrderBook struct {
    Bids []Order `json:"bids"`
    Asks []Order `json:"asks"`
}

// Order represents an order in the order book

type Order struct {
    Price  float64 `json:"price"`
    Amount float64 `json:"amount"`
}

// handleConnections handles WebSocket connections

func handleConnections(w http.ResponseWriter, r *http.Request) {
    ws, err := upgrader.Upgrade(w, r, nil)
    if err != nil {
        log.Fatal(err)
    }
    defer ws.Close()

    clients[ws] = true

    for {
        var msg Message
        err := ws.ReadJSON(&msg)
        if err != nil {
            log.Printf("error: %v", err)
            delete(clients, ws)
            break
        }

        broadcast <- msg
    }
}

// handleMessages handles WebSocket messages

func handleMessages() {
    for {
        msg := <-broadcast
        for client := range clients {
            err := client.WriteJSON(msg)
            if err != nil {
                log.Printf("error: %v", err)
                client.Close()
                delete(clients, client)
            }
        }
    }
}

// getWalletBalance handles the wallet balance request

func getWalletBalance(w http.ResponseWriter, r *http.Request) {
    vars := mux.Vars(r)
    address := vars["address"]

    // Simulate fetching wallet balance
    wallet := WalletService{
        Address: address,
        Balance: 14.852,
    }

    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(wallet)
}

// sendTransaction handles the transaction request

func sendTransaction(w http.ResponseWriter, r *http.Request) {
    var tx Transaction
    err := json.NewDecoder(r.Body).Decode(&tx)
    if err != nil {
        http.Error(w, err.Error(), http.StatusBadRequest)
        return
    }

    // Simulate sending transaction
    log.Printf("Transaction sent: %+v", tx)

    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(tx)
}

// getGasPrice handles the gas price request

func getGasPrice(w http.ResponseWriter, r *http.Request) {
    // Simulate fetching gas price
    gasPrice := GasPrice{
        Slow:     12,
        Standard: 18,
        Fast:     24,
    }

    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(gasPrice)
}

// getMarketData handles the market data request

func getMarketData(w http.ResponseWriter, r *http.Request) {
    vars := mux.Vars(r)
    pair := vars["pair"]

    // Simulate fetching market data
    marketData := MarketData{
        Pair:      pair,
        Price:     3450.75,
        Change24h: 4.82,
        Volume24h: 1284509000,
        High24h:   3520.00,
        Low24h:    3310.50,
    }

    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(marketData)
}

// getOrderBook handles the order book request

func getOrderBook(w http.ResponseWriter, r *http.Request) {
    vars := mux.Vars(r)
    pair := vars["pair"]

    // Simulate fetching order book
    orderBook := OrderBook{
        Bids: []Order{
            {Price: 3450.75, Amount: 0.5},
            {Price: 3450.00, Amount: 1.2},
            {Price: 3449.50, Amount: 0.8},
        },
        Asks: []Order{
            {Price: 3451.00, Amount: 0.7},
            {Price: 3451.50, Amount: 1.0},
            {Price: 3452.00, Amount: 0.3},
        },
    }

    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(orderBook)
}

// main is the entry point of the application

func main() {
    // Initialize router
    router := mux.NewRouter()

    // WebSocket endpoint
    router.HandleFunc("/ws", handleConnections)

    // API endpoints
    router.HandleFunc("/api/wallet/{address}/balance", getWalletBalance).Methods("GET")
    router.HandleFunc("/api/transaction", sendTransaction).Methods("POST")
    router.HandleFunc("/api/gas-price", getGasPrice).Methods("GET")
    router.HandleFunc("/api/market-data/{pair}", getMarketData).Methods("GET")
    router.HandleFunc("/api/order-book/{pair}", getOrderBook).Methods("GET")

    // Start WebSocket message handler
    go handleMessages()

    // Start server
    port := os.Getenv("PORT")
    if port == "" {
        port = "8080"
    }

    srv := &http.Server{
        Handler:      router,
        Addr:         "0.0.0.0:" + port,
        WriteTimeout: 15 * time.Second,
        ReadTimeout:  15 * time.Second,
    }

    log.Printf("Server starting on port %s", port)
    log.Fatal(srv.ListenAndServe())
}