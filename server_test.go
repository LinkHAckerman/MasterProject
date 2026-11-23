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

func TestRelayTransaction(t *testing.T) {
	store := NewWalletStore()
	from := "0x71C7656EC7ab88b098defB751B7401B5f6d8976F"
	to := "0xF39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
	token := "OPUS"
	amount := 10.0
	fee := 0.001
	nonce := uint64(5)
	signature := "0x1234567890abcdef"

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

	if tx.Status != StatusRelayed {
		t.Errorf("Expected transaction status RELAYED, got %s", tx.Status)
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

func TestGetWallet(t *testing.T) {
	store := NewWalletStore()
	addr := "0x71C7656EC7ab88b098defB751B7401B5f6d8976F"

	wallet, exists := store.GetWallet(addr)

	if !exists {
		t.Errorf("Expected wallet to exist")
	}

	if wallet.Address != addr {
		t.Errorf("Expected wallet address %s, got %s", addr, wallet.Address)
	}
}

func TestGetTransactionHistory(t *testing.T) {
	store := NewWalletStore()
	addr := "0x71C7656EC7ab88b098defB751B7401B5f6d8976F"

	history := store.GetTransactionHistory(addr)

	if len(history) != 0 {
		t.Errorf("Expected empty transaction history, got %d transactions", len(history))
	}
}

func TestGetMetrics(t *testing.T) {
	store := NewWalletStore()

	metrics := store.GetMetrics()

	if metrics.ActiveWallets != 3 {
		t.Errorf("Expected 3 active wallets, got %d", metrics.ActiveWallets)
	}
}

func TestCreateWalletHandler(t *testing.T) {
	store := NewWalletStore()
	r := mux.NewRouter()
	r.HandleFunc("/wallets", store.CreateWalletHandler).Methods("POST")

	addr := "0x1234567890123456789012345678901234567890"
	payload := map[string]string{"address": addr}
	body, _ := json.Marshal(payload)

	req, _ := http.NewRequest("POST", "/wallets", bytes.NewBuffer(body))
	req.Header.Set("Content-Type", "application/json")

	rr := httptest.NewRecorder()
	handler := http.HandlerFunc(store.CreateWalletHandler)
	handler.ServeHTTP(rr, req)

	if rr.Code != http.StatusOK {
		t.Errorf("Expected status code %d, got %d", http.StatusOK, rr.Code)
	}

	var response APIResponse
	json.Unmarshal(rr.Body.Bytes(), &response)

	if !response.Success {
		t.Errorf("Expected success response")
	}

	wallet, ok := response.Data.(map[string]interface{})
	if !ok {
		t.Fatalf("Expected wallet data in response")
	}

	if wallet["address"] != addr {
		t.Errorf("Expected wallet address %s, got %s", addr, wallet["address"])
	}
}

func TestTransferHandler(t *testing.T) {
	store := NewWalletStore()
	r := mux.NewRouter()
	r.HandleFunc("/transfers", store.TransferHandler).Methods("POST")

	from := "0x71C7656EC7ab88b098defB751B7401B5f6d8976F"
	to := "0xF39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
	token := "OPUS"
	amount := 10.0

	payload := map[string]interface{}{
		"from":   from,
		"to":     to,
		"token":  token,
		"amount": amount,
	}
	body, _ := json.Marshal(payload)

	req, _ := http.NewRequest("POST", "/transfers", bytes.NewBuffer(body))
	req.Header.Set("Content-Type", "application/json")

	rr := httptest.NewRecorder()
	handler := http.HandlerFunc(store.TransferHandler)
	handler.ServeHTTP(rr, req)

	if rr.Code != http.StatusOK {
		t.Errorf("Expected status code %d, got %d", http.StatusOK, rr.Code)
	}

	var response APIResponse
	json.Unmarshal(rr.Body.Bytes(), &response)

	if !response.Success {
		t.Errorf("Expected success response")
	}

	tx, ok := response.Data.(map[string]interface{})
	if !ok {
		t.Fatalf("Expected transaction data in response")
	}

	if tx["status"] != string(StatusPending) {
		t.Errorf("Expected transaction status PENDING, got %s", tx["status"])
	}

	if tx["amount"] != amount {
		t.Errorf("Expected transaction amount %f, got %f", amount, tx["amount"])
	}
}

func TestRelayTransactionHandler(t *testing.T) {
	store := NewWalletStore()
	r := mux.NewRouter()
	r.HandleFunc("/relay", store.RelayTransactionHandler).Methods("POST")

	from := "0x71C7656EC7ab88b098defB751B7401B5f6d8976F"
	to := "0xF39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
	token := "OPUS"
	amount := 10.0
	fee := 0.001
	nonce := uint64(5)
	signature := "0x1234567890abcdef"

	payload := map[string]interface{}{
		"from":      from,
		"to":        to,
		"token":     token,
		"amount":    amount,
		"fee":       fee,
		"nonce":     nonce,
		"signature": signature,
	}
	body, _ := json.Marshal(payload)

	req, _ := http.NewRequest("POST", "/relay", bytes.NewBuffer(body))
	req.Header.Set("Content-Type", "application/json")

	rr := httptest.NewRecorder()
	handler := http.HandlerFunc(store.RelayTransactionHandler)
	handler.ServeHTTP(rr, req)

	if rr.Code != http.StatusOK {
		t.Errorf("Expected status code %d, got %d", http.StatusOK, rr.Code)
	}

	var response APIResponse
	json.Unmarshal(rr.Body.Bytes(), &response)

	if !response.Success {
		t.Errorf("Expected success response")
	}

	tx, ok := response.Data.(map[string]interface{})
	if !ok {
		t.Fatalf("Expected transaction data in response")
	}

	if tx["status"] != string(StatusRelayed) {
		t.Errorf("Expected transaction status RELAYED, got %s", tx["status"])
	}

	if tx["amount"] != amount {
		t.Errorf("Expected transaction amount %f, got %f", amount, tx["amount"])
	}

	if tx["fee"] != fee {
		t.Errorf("Expected transaction fee %f, got %f", fee, tx["fee"])
	}

	if tx["nonce"] != float64(nonce) {
		t.Errorf("Expected transaction nonce %d, got %f", nonce, tx["nonce"])
	}

	if tx["signature"] != signature {
		t.Errorf("Expected transaction signature %s, got %s", signature, tx["signature"])
	}
}

func TestGetWalletHandler(t *testing.T) {
	store := NewWalletStore()
	r := mux.NewRouter()
	r.HandleFunc("/wallets/{address}", store.GetWalletHandler).Methods("GET")

	addr := "0x71C7656EC7ab88b098defB751B7401B5f6d8976F"

	req, _ := http.NewRequest("GET", "/wallets/"+addr, nil)

	rr := httptest.NewRecorder()
	handler := http.HandlerFunc(store.GetWalletHandler)
	handler.ServeHTTP(rr, req)

	if rr.Code != http.StatusOK {
		t.Errorf("Expected status code %d, got %d", http.StatusOK, rr.Code)
	}

	var response APIResponse
	json.Unmarshal(rr.Body.Bytes(), &response)

	if !response.Success {
		t.Errorf("Expected success response")
	}

	wallet, ok := response.Data.(map[string]interface{})
	if !ok {
		t.Fatalf("Expected wallet data in response")
	}

	if wallet["address"] != addr {
		t.Errorf("Expected wallet address %s, got %s", addr, wallet["address"])
	}
}

func TestGetTransactionHistoryHandler(t *testing.T) {
	store := NewWalletStore()
	r := mux.NewRouter()
	r.HandleFunc("/wallets/{address}/history", store.GetTransactionHistoryHandler).Methods("GET")

	addr := "0x71C7656EC7ab88b098defB751B7401B5f6d8976F"

	req, _ := http.NewRequest("GET", "/wallets/"+addr+"/history", nil)

	rr := httptest.NewRecorder()
	handler := http.HandlerFunc(store.GetTransactionHistoryHandler)
	handler.ServeHTTP(rr, req)

	if rr.Code != http.StatusOK {
		t.Errorf("Expected status code %d, got %d", http.StatusOK, rr.Code)
	}

	var response APIResponse
	json.Unmarshal(rr.Body.Bytes(), &response)

	if !response.Success {
		t.Errorf("Expected success response")
	}

	history, ok := response.Data.([]interface{})
	if !ok {
		t.Fatalf("Expected transaction history data in response")
	}

	if len(history) != 0 {
		t.Errorf("Expected empty transaction history, got %d transactions", len(history))
	}
}

func TestGetMetricsHandler(t *testing.T) {
	store := NewWalletStore()
	r := mux.NewRouter()
	r.HandleFunc("/metrics", store.GetMetricsHandler).Methods("GET")

	req, _ := http.NewRequest("GET", "/metrics", nil)

	rr := httptest.NewRecorder()
	handler := http.HandlerFunc(store.GetMetricsHandler)
	handler.ServeHTTP(rr, req)

	if rr.Code != http.StatusOK {
		t.Errorf("Expected status code %d, got %d", http.StatusOK, rr.Code)
	}

	var response APIResponse
	json.Unmarshal(rr.Body.Bytes(), &response)

	if !response.Success {
		t.Errorf("Expected success response")
	}

	metrics, ok := response.Data.(map[string]interface{})
	if !ok {
		t.Fatalf("Expected metrics data in response")
	}

	if metrics["active_wallets"] != float64(3) {
		t.Errorf("Expected 3 active wallets, got %f", metrics["active_wallets"])
	}
}

func TestWebSocketHandler(t *testing.T) {
	store := NewWalletStore()
	r := mux.NewRouter()
	r.HandleFunc("/ws", store.WebSocketHandler)

	server := httptest.NewServer(r)
	defer server.Close()

	url := "ws" + strings.TrimPrefix(server.URL, "http") + "/ws"

	ws, _, err := websocket.DefaultDialer.Dial(url, nil)
	if err != nil {
		t.Fatalf("Failed to connect to WebSocket: %v", err)
	}
	defer ws.Close()

	done := make(chan struct{})
	ticker := time.NewTicker(time.Second)
	defer ticker.Stop()

	go func() {
		defer close(done)
		for {
			_, message, err := ws.ReadMessage()
			if err != nil {
				return
			}

			var msg WebSocketMessage
			if err := json.Unmarshal(message, &msg); err != nil {
				continue
			}

			if msg.Type == "metrics" {
				metrics, ok := msg.Payload.(map[string]interface{})
				if !ok {
					continue
				}

				if metrics["active_wallets"] != float64(3) {
					t.Errorf("Expected 3 active wallets, got %f", metrics["active_wallets"])
				}
			}
		}
	}()

	for {
		select {
		case <-done:
			return
		case t := <-ticker.C:
			err := ws.WriteMessage(websocket.TextMessage, []byte(t.String()))
			if err != nil {
				return
			}
		}
	}
}