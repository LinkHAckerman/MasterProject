package main

import (
    "context"
    "fmt"
    "log"
    "math/rand"
    "net/http"
    "os"
    "os/signal"
    "strings"
    "syscall"
    "time"

    "github.com/gin-gonic/gin"
    "github.com/gin-gonic/gin/binding"
    "github.com/go-playground/validator/v10"
    "github.com/jackc/pgx/v5/pgxpool"
)

type Server struct {
    router *gin.Engine
    db     *pgxpool.Pool
}

type Wallet struct {
    ID        int64   `json:"id"`
    Address   string  `json:"address"`
    Balance   float64 `json:"balance"`
    Currency  string  `json:"currency"`
    UpdatedAt string  `json:"updated_at"`
}

type TransactionRequest struct {
    FromAddress string  `json:"from_address" binding:"required,eth_addr"`
    ToAddress   string  `json:"to_address" binding:"required,eth_addr"`
    Amount      float64 `json:"amount" binding:"required,gt=0"`
    Currency    string  `json:"currency" binding:"required,oneof=ETH USDT"`
    GasPrice    uint64  `json:"gas_price,omitempty"`
}

func main() {
    // Load configuration from environment variables
    dsn := os.Getenv("DATABASE_URL")
    if dsn == "" {
        dsn = "postgres://postgres:password@localhost:5432/magnum_opus?sslmode=disable"
    }

    ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
    defer cancel()
    dbpool, err := pgxpool.New(ctx, dsn)
    if err != nil {
        log.Fatalf("Unable to connect to database: %v", err)
    }
    defer dbpool.Close()

    s := &Server{
        router: gin.New(),
        db:     dbpool,
    }

    s.setupMiddleware()
    s.setupRoutes()

    srv := &http.Server{
        Addr:    ":8080",
        Handler: s.router,
    }

    go func() {
        log.Println("🚀 Server listening on :8080")
        if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
            log.Fatalf("listen: %s", err)
        }
    }()

    // Graceful shutdown handling
    quit := make(chan os.Signal, 1)
    signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
    <-quit
    log.Println("Shutting down server...")

    ctxShut, cancelShut := context.WithTimeout(context.Background(), 10*time.Second)
    defer cancelShut()
    if err := srv.Shutdown(ctxShut); err != nil {
        log.Fatalf("Server forced to shutdown: %v", err)
    }
    log.Println("Server exiting")
}

func (s *Server) setupMiddleware() {
    s.router.Use(gin.Logger())
    s.router.Use(gin.Recovery())
    // Register custom validator for Ethereum address format
    if v, ok := binding.Validator.Engine().(*validator.Validate); ok {
        v.RegisterValidation("eth_addr", func(fl validator.FieldLevel) bool {
            addr := fl.Field().String()
            return len(addr) == 42 && strings.HasPrefix(addr, "0x")
        })
    }
}

func (s *Server) setupRoutes() {
    api := s.router.Group("/api/v1")
    {
        api.GET("/health", s.healthHandler)
        api.GET("/wallet/:address", s.getWalletHandler)
        api.POST("/tx/relay", s.relayTransactionHandler)
    }
}

// healthHandler returns a simple health check response.
func (s *Server) healthHandler(c *gin.Context) {
    c.JSON(http.StatusOK, gin.H{"status": "ok", "timestamp": time.Now().UTC()})
}

// getWalletHandler fetches wallet information by Ethereum address.
func (s *Server) getWalletHandler(c *gin.Context) {
    address := c.Param("address")
    if len(address) != 42 || !strings.HasPrefix(address, "0x") {
        c.JSON(http.StatusBadRequest, gin.H{"error": "invalid ethereum address"})
        return
    }

    var w Wallet
    err := s.db.QueryRow(context.Background(),
        `SELECT id, address, balance, currency, updated_at FROM wallets WHERE address=$1`,
        address).Scan(&w.ID, &w.Address, &w.Balance, &w.Currency, &w.UpdatedAt)
    if err != nil {
        c.JSON(http.StatusNotFound, gin.H{"error": "wallet not found"})
        return
    }
    c.JSON(http.StatusOK, w)
}

// relayTransactionHandler validates, processes, and records a simple token transfer.
func (s *Server) relayTransactionHandler(c *gin.Context) {
    var req TransactionRequest
    if err := c.ShouldBindJSON(&req); err != nil {
        c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
        return
    }

    // Verify sender balance
    var senderBalance float64
    err := s.db.QueryRow(context.Background(),
        `SELECT balance FROM wallets WHERE address=$1 AND currency=$2`,
        req.FromAddress, req.Currency).Scan(&senderBalance)
    if err != nil {
        c.JSON(http.StatusNotFound, gin.H{"error": "sender wallet not found"})
        return
    }
    if senderBalance < req.Amount {
        c.JSON(http.StatusBadRequest, gin.H{"error": "insufficient funds"})
        return
    }

    // Simulate a transaction hash (in production replace with real signing & broadcasting)
    txHash := fmt.Sprintf("0x%064x", rand.Uint64())

    // Begin atomic DB transaction
    tx, err := s.db.Begin(context.Background())
    if err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to start db transaction"})
        return
    }
    defer tx.Rollback(context.Background())

    // Debit sender
    _, err = tx.Exec(context.Background(),
        `UPDATE wallets SET balance = balance - $1 WHERE address=$2 AND currency=$3`,
        req.Amount, req.FromAddress, req.Currency)
    if err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to debit sender"})
        return
    }

    // Credit receiver (upsert)
    _, err = tx.Exec(context.Background(),
        `INSERT INTO wallets (address, balance, currency, updated_at)
         VALUES ($1, $2, $3, NOW())
         ON CONFLICT (address, currency) DO UPDATE SET balance = wallets.balance + EXCLUDED.balance, updated_at = NOW()`,
        req.ToAddress, req.Amount, req.Currency)
    if err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to credit receiver"})
        return
    }

    // Record transaction metadata
    _, err = tx.Exec(context.Background(),
        `INSERT INTO transactions (hash, from_address, to_address, amount, currency, status, created_at)
         VALUES ($1, $2, $3, $4, $5, $6, NOW())`,
        txHash, req.FromAddress, req.ToAddress, req.Amount, req.Currency, "confirmed")
    if err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to record transaction"})
        return
    }

    if err = tx.Commit(context.Background()); err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to commit transaction"})
        return
    }

    c.JSON(http.StatusOK, gin.H{"tx_hash": txHash, "status": "submitted"})
}
