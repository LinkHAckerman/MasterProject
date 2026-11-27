package main

import (
    "strings"
    "testing"
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

    if wallet.Address != strings.ToLower(addr) {
        t.Errorf("Expected wallet address %s, got %s", strings.ToLower(addr), wallet.Address)
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

    tx, err := store.Transfer(TransferRequest{From: from, To: to, Token: token, Amount: amount})
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

    if store.metrics.MempoolSize != 1 {
        t.Errorf("Expected mempool size 1, got %d", store.metrics.MempoolSize)
    }
}

func TestTransferInsufficientBalance(t *testing.T) {
    store := NewWalletStore()
    from := "0x71C7656EC7ab88b098defB751B7401B5f6d8976F"
    to := "0xF39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
    token := "OPUS"
    amount := 20000.0 // exceeds sender's balance

    _, err := store.Transfer(TransferRequest{From: from, To: to, Token: token, Amount: amount})
    if err == nil {
        t.Fatalf("Expected error due to insufficient balance, got nil")
    }
}

func TestTransferUnsupportedToken(t *testing.T) {
    store := NewWalletStore()
    from := "0x71C7656EC7ab88b098defB751B7401B5f6d8976F"
    to := "0xF39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
    token := "XYZ"
    amount := 1.0

    _, err := store.Transfer(TransferRequest{From: from, To: to, Token: token, Amount: amount})
    if err == nil {
        t.Fatalf("Expected error for unsupported token, got nil")
    }
}

func TestGetWalletNonExisting(t *testing.T) {
    store := NewWalletStore()
    addr := "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    _, exists := store.GetWallet(addr)
    if exists {
        t.Errorf("Expected wallet %s to not exist", addr)
    }
}
