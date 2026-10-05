package main

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
)

type Wallet struct {
	Address  string             `json:"address"`
	Balances map[string]float64 `json:"balances"`
}

type Transaction struct {
	From      string  `json:"from"`
	To        string  `json:"to"`
	Token     string  `json:"token"`
	Amount    float64 `json:"amount"`
	Timestamp int64   `json:"timestamp"`
	TxHash    string  `json:"txHash"`
}

var (
	wallets = make(map[string]*Wallet)
	mu      sync.RWMutex
)

func main() {
	r := gin.New()
	r.Use(gin.Logger())
	r.Use(gin.Recovery())

	r.GET("/health", healthHandler)
	r.POST("/wallet/create", createWalletHandler)
	r.GET("/wallet/:address", getWalletHandler)
	r.POST("/wallet/:address/transfer", transferHandler)

	if err := r.Run(":8080"); err != nil {
		log.Fatalf("Failed to start server: %v", err)
	}
}

// healthHandler returns a simple health status.
func healthHandler(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"status": "ok"})
}

// createWalletHandler creates a new wallet with a zeroed balance map.
func createWalletHandler(c *gin.Context) {
	var req struct {
		Address string `json:"address"`
	}
	if err := c.ShouldBindJSON(&req); err != nil || req.Address == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid address"})
		return
	}

	mu.Lock()
	defer mu.Unlock()
	if _, exists := wallets[req.Address]; exists {
		c.JSON(http.StatusConflict, gin.H{"error": "wallet already exists"})
		return
	}

	wallets[req.Address] = &Wallet{
		Address:  req.Address,
		Balances: map[string]float64{},
	}

	c.JSON(http.StatusCreated, wallets[req.Address])
}

// getWalletHandler returns the balances of the requested wallet.
func getWalletHandler(c *gin.Context) {
	address := c.Param("address")
	mu.RLock()
	wallet, exists := wallets[address]
	mu.RUnlock()
	if !exists {
		c.JSON(http.StatusNotFound, gin.H{"error": "wallet not found"})
		return
	}
	c.JSON(http.StatusOK, wallet)
}

// transferHandler moves tokens from one wallet to another and returns a transaction receipt.
func transferHandler(c *gin.Context) {
	fromAddr := c.Param("address")
	var req struct {
		To     string  `json:"to"`
		Token  string  `json:"token"`
		Amount float64 `json:"amount"`
	}
	if err := c.ShouldBindJSON(&req); err != nil || req.To == "" || req.Token == "" || req.Amount <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid request payload"})
		return
	}

	mu.Lock()
	defer mu.Unlock()
	fromWallet, ok := wallets[fromAddr]
	if !ok {
		c.JSON(http.StatusNotFound, gin.H{"error": "source wallet not found"})
		return
	}
	toWallet, ok := wallets[req.To]
	if !ok {
		c.JSON(http.StatusNotFound, gin.H{"error": "destination wallet not found"})
		return
	}

	if fromWallet.Balances[req.Token] < req.Amount {
		c.JSON(http.StatusBadRequest, gin.H{"error": "insufficient balance"})
		return
	}

	// Perform transfer
	fromWallet.Balances[req.Token] -= req.Amount
	toWallet.Balances[req.Token] += req.Amount

	// Build transaction receipt
	tx := Transaction{
		From:      fromAddr,
		To:        req.To,
		Token:     req.Token,
		Amount:    req.Amount,
		Timestamp: time.Now().Unix(),
	}
	tx.TxHash = computeTxHash(tx)

	c.JSON(http.StatusOK, tx)
}

// computeTxHash creates a deterministic hash for a transaction.
func computeTxHash(tx Transaction) string {
	data := tx.From + tx.To + tx.Token + fmt.Sprintf("%f", tx.Amount) + fmt.Sprintf("%d", tx.Timestamp)
	hash := sha256.Sum256([]byte(data))
	return "0x" + hex.EncodeToString(hash[:])
}
