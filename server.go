package main

import (
	"context"
	"crypto/sha256"
	"fmt"
	"net/http"
	"os"
	"os/signal"
	"time"

	"github.com/dgrijalva/jwt-go"
	"github.com/gin-gonic/gin"
)

// JWT secret (in production use env vars or secret manager)
var jwtSecret = []byte("SuperSecretKey123!")

// Simple in‑memory mock wallet store
type walletInfo struct {
	Address string  `json:"address"`
	Balance float64 `json:"balance"`
}

var mockWallets = map[string]walletInfo{
	"0x1111111111111111111111111111111111111111": {Address: "0x1111111111111111111111111111111111111111", Balance: 12.34},
	"0x2222222222222222222222222222222222222222": {Address: "0x2222222222222222222222222222222222222222", Balance: 56.78},
}

// JWT claims structure
type Claims struct {
	User string `json:"user"`
	jwt.StandardClaims
}

// Middleware to protect routes
func authMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		tokenString := c.GetHeader("Authorization")
		if tokenString == "" {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "missing token"})
			return
		}
		// Expect format "Bearer <token>"
		if len(tokenString) > 7 && tokenString[:7] == "Bearer " {
			tokenString = tokenString[7:]
		}
		claims := &Claims{}
		token, err := jwt.ParseWithClaims(tokenString, claims, func(token *jwt.Token) (interface{}, error) {
			return jwtSecret, nil
		})
		if err != nil || !token.Valid {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "invalid token"})
			return
		}
		c.Set("user", claims.User)
		c.Next()
	}
}

// Handler: Get wallet balance
func getBalanceHandler(c *gin.Context) {
	address := c.Param("address")
	// Basic address validation – must start with 0x and be 42 chars long
	if len(address) != 42 || address[:2] != "0x" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid address format"})
		return
	}
	wallet, ok := mockWallets[address]
	if !ok {
		c.JSON(http.StatusNotFound, gin.H{"error": "wallet not found"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"address": wallet.Address, "balance": wallet.Balance})
}

// Handler: Relay a transaction (mock implementation)
func relayTxHandler(c *gin.Context) {
	var payload struct {
		From   string  `json:"from"`
		To     string  `json:"to"`
		Amount float64 `json:"amount"`
	}
	if err := c.ShouldBindJSON(&payload); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid payload"})
		return
	}
	// Very light validation
	if payload.Amount <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "amount must be positive"})
		return
	}
	// Simulate transaction hash generation using a simple timestamp hash
	hash := generateMockTxHash(payload.From, payload.To, payload.Amount)
	c.JSON(http.StatusOK, gin.H{"txHash": hash, "status": "submitted"})
}

func generateMockTxHash(from, to string, amount float64) string {
	stamp := time.Now().UnixNano()
	raw := from + to + fmt.Sprintf("%f", amount) + fmt.Sprintf("%d", stamp)
	h := sha256.Sum256([]byte(raw))
	return "0x" + fmt.Sprintf("%x", h[:])
}

func main() {
	router := gin.Default()

	// Public endpoint to obtain a demo JWT (in real world use proper auth)
	router.POST("/login", func(c *gin.Context) {
		var login struct {
			User string `json:"user"`
			Pass string `json:"pass"`
		}
		if err := c.ShouldBindJSON(&login); err != nil || login.User == "" {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid login payload"})
			return
		}
		// Issue token valid for 1 hour
		exp := time.Now().Add(time.Hour)
		claims := Claims{User: login.User, StandardClaims: jwt.StandardClaims{ExpiresAt: exp.Unix()}}
		token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
		tokenString, _ := token.SignedString(jwtSecret)
		c.JSON(http.StatusOK, gin.H{"token": tokenString})
	})

	api := router.Group("/api")
	api.Use(authMiddleware())
	api.GET("/wallet/:address/balance", getBalanceHandler)
	api.POST("/tx/relay", relayTxHandler)

	// Graceful shutdown handling
	srv := &http.Server{
		Addr:    ":8080",
		Handler: router,
	}

	go func() {
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			panic("server error: " + err.Error())
		}
	}()

	// Wait for interrupt signal
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, os.Interrupt)
	<-quit
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := srv.Shutdown(ctx); err != nil {
		panic("server forced to shutdown: " + err.Error())
	}
}
