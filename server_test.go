package main

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/gorilla/mux"
	"github.com/gorilla/websocket"
)

func TestNewWalletStore(t *testing.T) {
	store := NewWalletStore()

	if len(store.wallets) != 3 {
		t.Errorf("Expected 3 demo wallets, got %d", len(store.wallets))
	}

	if store.metrics.ActiveWallets != 3 {
		t.Errorf("Expected 3 active wallets, got %d", store.metrics.ActiveWallets)
	}
}

func TestGetOrCreateWallet(t *testing.T) {
	store := NewWalletStore()
	addr := "0x1234567890123456789012345678901234567890"

	wallet, err := store.GetOrCreateWallet(addr)
	if err != nil {
		t.Fatalf("GetOrCreateWallet failed: %v", err)
	}

	if wallet.Address != addr {
		t.Errorf("Expected wallet address %s, got %s", addr, wallet.Address)
	}

	if wallet.Balance["OPUS"] != 100.0 {
		t.Errorf("Expected initial OPUS balance 100.0, got %f", wallet.Balance["OPUS"])
	}
}

func TestGetOrCreateWalletInvalidAddress(t *testing.T) {
	store := NewWalletStore()
	addr := "invalid_address"

	_, err := store.GetOrCreateWallet(addr)
	if err == nil {
		t.Error("Expected error for invalid address, got nil")
	}
}

func TestTransfer(t *testing.T) {
	store := NewWalletStore()
	from := "0x71C7656EC7ab88b098defB751B7401B5f6d8976F"
	to := "0xF39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
	token := "OPUS"
	amount := 10.0

	tx, err := store.Transfer(TransferRequest{
		From:   from,
		To:     to,
		Token:  token,
		Amount: amount,
	})

	if err != nil {
		t.Fatalf("Transfer failed: %v", err)
	}

	if tx.Status != StatusPending {
		t.Errorf("Expected transaction status PENDING, got %s", tx.Status)
	}

	if tx.Amount != amount {
		t.Errorf("Expected transaction amount %f, got %f", amount, tx.Amount)
	}

	walletFrom, _ := store.GetWallet(from)
	walletTo, _ := store.GetWallet(to)

	if walletFrom.Balance[token] != 9990.0 {
		t.Errorf("Expected sender balance 9990.0, got %f", walletFrom.Balance[token])
	}

	if walletTo.Balance[token] != 10010.0 {
		t.Errorf("Expected recipient balance 10010.0, got %f", walletTo.Balance[token])
	}
}

func TestTransferInsufficientBalance(t *testing.T) {
	store := NewWalletStore()
	from := "0x71C7656EC7ab88b098defB751B7401B5f6d8976F"
	to := "0xF39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
	token := "OPUS"
	amount := 100000.0

	_, err := store.Transfer(TransferRequest{
		From:   from,
		To:     to,
		Token:  token,
		Amount: amount,
	})

	if err == nil {
		t.Error("Expected error for insufficient balance, got nil")
	}
}

func TestTransferInvalidToken(t *testing.T) {
	store := NewWalletStore()
	from := "0x71C7656EC7ab88b098defB751B7401B5f6d8976F"
	to := "0xF39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
	token := "INVALID"
	amount := 10.0

	_, err := store.Transfer(TransferRequest{
		From:   from,
		To:     to,
		Token:  token,
		Amount: amount,
	})

	if err == nil {
		t.Error("Expected error for invalid token, got nil")
	}
}

func TestRelayTransaction(t *testing.T) {
	store := NewWalletStore()
	from := "0x71C7656EC7ab88b098defB751B7401B5f6d8976F"
	to := "0xF39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
	token := "OPUS"
	amount := 10.0
	fee := 0.1
	nonce := uint64(1)
	signature := "test_signature"

	tx, err := store.RelayTransaction(RelayTxRequest{
		From:      from,
		To:        to,
		Token:     token,
		Amount:    amount,
		Fee:       fee,
		Nonce:     nonce,
		Signature: signature,
	})

	if err != nil {
		t.Fatalf("RelayTransaction failed: %v", err)
	}

	if tx.Status != StatusPending {
		t.Errorf("Expected transaction status PENDING, got %s", tx.Status)
	}

	if tx.Amount != amount {
		t.Errorf("Expected transaction amount %f, got %f", amount, tx.Amount)
	}

	if tx.Fee != fee {
		t.Errorf("Expected transaction fee %f, got %f", fee, tx.Fee)
	}

	if tx.Nonce != nonce {
		t.Errorf("Expected transaction nonce %d, got %d", nonce, tx.Nonce)
	}

	if tx.Signature != signature {
		t.Errorf("Expected transaction signature %s, got %s", signature, tx.Signature)
	}
}

func TestRelayTransactionInvalidNonce(t *testing.T) {
	store := NewWalletStore()
	from := "0x71C7656EC7ab88b098defB751B7401B5f6d8976F"
	to := "0xF39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
	token := "OPUS"
	amount := 10.0
	fee := 0.1
	nonce := uint64(100)
	signature := "test_signature"

	_, err := store.RelayTransaction(RelayTxRequest{
		From:      from,
		To:        to,
		Token:     token,
		Amount:    amount,
		Fee:       fee,
		Nonce:     nonce,
		Signature: signature,
	})

	if err == nil {
		t.Error("Expected error for invalid nonce, got nil")
	}
}

func TestGetWallet(t *testing.T) {
	store := NewWalletStore()
	addr := "0x71C7656EC7ab88b098defB751B7401B5f6d8976F"

	wallet, exists := store.GetWallet(addr)
	if !exists {
		t.Error("Expected wallet to exist, got false")
	}

	if wallet.Address != addr {
		t.Errorf("Expected wallet address %s, got %s", addr, wallet.Address)
	}
}

func TestGetWalletNonExistent(t *testing.T) {
	store := NewWalletStore()
	addr := "0x1234567890123456789012345678901234567890"

	_, exists := store.GetWallet(addr)
	if exists {
		t.Error("Expected wallet to not exist, got true")
	}
}

func TestGetMetrics(t *testing.T) {
	store := NewWalletStore()

	metrics := store.GetMetrics()

	if metrics.ActiveWallets != 3 {
		t.Errorf("Expected 3 active wallets, got %d", metrics.ActiveWallets)
	}
}

func TestGetTransactionHistory(t *testing.T) {
	store := NewWalletStore()
	addr := "0x71C7656EC7ab88b098defB751B7401B5f6d8976F"

	history := store.GetTransactionHistory(addr)

	if len(history) != 0 {
		t.Errorf("Expected 0 transactions, got %d", len(history))
	}
}

func TestGetTransactionHistoryNonExistentWallet(t *testing.T) {
	store := NewWalletStore()
	addr := "0x1234567890123456789012345678901234567890"

	history := store.GetTransactionHistory(addr)

	if len(history) != 0 {
		t.Errorf("Expected 0 transactions, got %d", len(history))
	}
}

func TestGetMempool(t *testing.T) {
	store := NewWalletStore()

	mempool := store.GetMempool()

	if len(mempool) != 0 {
		t.Errorf("Expected 0 transactions in mempool, got %d", len(mempool))
	}
}

func TestGetBlocks(t *testing.T) {
	store := NewWalletStore()

	blocks := store.GetBlocks()

	if len(blocks) != 0 {
		t.Errorf("Expected 0 blocks, got %d", len(blocks))
	}
}

func TestGetBlock(t *testing.T) {
	store := NewWalletStore()
	blockNumber := uint64(1000000)

	block, exists := store.GetBlock(blockNumber)

	if !exists {
		t.Error("Expected block to exist, got false")
	}

	if block.BlockNumber != blockNumber {
		t.Errorf("Expected block number %d, got %d", blockNumber, block.BlockNumber)
	}
}

func TestGetBlockNonExistent(t *testing.T) {
	store := NewWalletStore()
	blockNumber := uint64(999999)

	_, exists := store.GetBlock(blockNumber)

	if exists {
		t.Error("Expected block to not exist, got true")
	}
}

func TestGetTransaction(t *testing.T) {
	store := NewWalletStore()
	from := "0x71C7656EC7ab88b098defB751B7401B5f6d8976F"
	to := "0xF39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
	token := "OPUS"
	amount := 10.0

	tx, _ := store.Transfer(TransferRequest{
		From:   from,
		To:     to,
		Token:  token,
		Amount: amount,
	})

	retrievedTx, exists := store.GetTransaction(tx.TxHash)

	if !exists {
		t.Error("Expected transaction to exist, got false")
	}

	if retrievedTx.TxHash != tx.TxHash {
		t.Errorf("Expected transaction hash %s, got %s", tx.TxHash, retrievedTx.TxHash)
	}
}

func TestGetTransactionNonExistent(t *testing.T) {
	store := NewWalletStore()
	txHash := "0x1234567890123456789012345678901234567890"

	_, exists := store.GetTransaction(txHash)

	if exists {
		t.Error("Expected transaction to not exist, got true")
	}
}
