#!/usr/bin/env dotnet
// MAGNUM OPUS // Web3 & DeFi Nexus Engine - Transaction Processing Core
// High-performance transaction engine with validation, fee calculation, and receipt generation.
// Built with .NET 8.0 for maximum performance and cross-platform compatibility.

using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

namespace MagnumOpus.Backend.Core
{
    // ============================================================================
    // Transaction Status Enumeration
    // ============================================================================
    public enum TransactionStatus
    {
        Pending = 0,
        Confirmed = 1,
        Failed = 2,
        Rejected = 3
    }

    // ============================================================================
    // Transaction Entity
    // ============================================================================
    public sealed class Transaction
    {
        [JsonPropertyName("id")]
        public string Id { get; set; } = string.Empty;

        [JsonPropertyName("sender")]
        public string Sender { get; set; } = string.Empty;

        [JsonPropertyName("recipient")]
        public string Recipient { get; set; } = string.Empty;

        [JsonPropertyName("amount")]
        public decimal Amount { get; set; }

        [JsonPropertyName("fee")]
        public decimal Fee { get; set; } = 0.0001m;

        [JsonPropertyName("nonce")]
        public ulong Nonce { get; set; }

        [JsonPropertyName("timestamp")]
        public DateTime Timestamp { get; set; } = DateTime.UtcNow;

        [JsonPropertyName("tokenSymbol")]
        public string TokenSymbol { get; set; } = "MOPUS";

        [JsonPropertyName("payload")]
        public string Payload { get; set; } = string.Empty;

        [JsonPropertyName("signature")]
        public string Signature { get; set; } = string.Empty;

        [JsonPropertyName("status")]
        public TransactionStatus Status { get; set; } = TransactionStatus.Pending;

        [JsonPropertyName("gasUsed")]
        public long GasUsed { get; set; }

        [JsonPropertyName("feePaid")]
        public decimal FeePaid { get; set; }

        [JsonPropertyName("blockIndex")]
        public long BlockIndex { get; set; }

        [JsonPropertyName("receiptId")]
        public string ReceiptId { get; set; } = string.Empty;

        public bool IsValid()
        {
            if (string.IsNullOrWhiteSpace(Sender)) return false;
            if (string.IsNullOrWhiteSpace(Recipient)) return false;
            if (Amount <= 0) return false;
            if (Fee < 0) return false;
            return true;
        }

        public override string ToString()
        {
            return $"{Id}:{Sender} -> {Recipient} | {Amount} {TokenSymbol} | Fee: {Fee} | Status: {Status}";
        }

        public byte[] GetRawPayloadBytes()
        {
            return Encoding.UTF8.GetBytes(ToString());
        }

        public string ComputeHash()
        {
            using var sha256 = SHA256.Create();
            var bytes = GetRawPayloadBytes();
            var hash = sha256.ComputeHash(bytes);
            return Convert.ToHexString(hash).ToLowerInvariant();
        }

        /// <summary>
        /// Calculates the total cost of a transaction including fee and gas.
        /// </summary>
        public decimal CalculateTotalCost()
        {
            return Amount + Fee;
        }

        /// <summary>
        /// Validates transaction against network constraints.
        /// </summary>
        public bool ValidateNetworkConstraints()
        {
            if (Amount > 1_000_000m) return false; // Max reasonable amount
            if (Fee > 10m) return false; // Fee cap
            return true;
        }
    }

    // ============================================================================
    // Transaction Receipt Entity
    // ============================================================================
    public sealed class TransactionReceipt
    {
        [JsonPropertyName("transactionId")]
        public string TransactionId { get; set; } = string.Empty;

        [JsonPropertyName("blockIndex")]
        public long BlockIndex { get; set; }

        [JsonPropertyName("blockHash")]
        public string BlockHash { get; set; } = string.Empty;

        [JsonPropertyName("gasUsed")]
        public long GasUsed { get; set; }

        [JsonPropertyName("feePaid")]
        public decimal FeePaid { get; set; }

        [JsonPropertyName("status")]
        public TransactionStatus Status { get; set; } = TransactionStatus.Confirmed;

        [JsonPropertyName("timestamp")]
        public DateTime Timestamp { get; set; } = DateTime.UtcNow;

        [JsonPropertyName("executionMessage")]
        public string ExecutionMessage { get; set; } = "Success";

        public bool IsSuccessful()
        {
            return Status == TransactionStatus.Confirmed;
        }
    }

    // ============================================================================
    // Block Entity
    // ============================================================================
    public sealed class Block
    {
        [JsonPropertyName("index")]
        public long Index { get; set; }

        [JsonPropertyName("timestamp")]
        public DateTime Timestamp { get; set; }

        [JsonPropertyName("transactions")]
        public List<Transaction> Transactions { get; set; } = new List<Transaction>();

        [JsonPropertyName("previousHash")]
        public string PreviousHash { get; set; } = string.Empty;

        [JsonPropertyName("merkleRoot")]
        public string MerkleRoot { get; set; } = string.Empty;

        [JsonPropertyName("nonce")]
        public ulong Nonce { get; set; }

        [JsonPropertyName("hash")]
        public string Hash { get; set; } = string.Empty;

        [JsonPropertyName("minerAddress")]
        public string MinerAddress { get; set; } = string.Empty;

        [JsonPropertyName("difficulty")]
        public int Difficulty { get; set; }

        public bool IsValid()
        {
            if (Index <= 0) return false;
            if (PreviousHash == string.Empty) return false;
            return true;
        }
    }

    // ============================================================================
    // Wallet Entity
    // ============================================================================
    public sealed class Wallet
    {
        [JsonPropertyName("address")]
        public string Address { get; set; } = string.Empty;

        [JsonPropertyName("publicKey")]
        public string PublicKey { get; set; } = string.Empty;

        [JsonPropertyName("balance")]
        public decimal Balance { get; set; }

        [JsonPropertyName("tokenBalances")]
        public Dictionary<string, decimal> TokenBalances { get; set; } = new Dictionary<string, decimal>(StringComparer.OrdinalIgnoreCase);

        [JsonPropertyName("nonce")]
        public ulong Nonce { get; set; }

        [JsonPropertyName("createdAt")]
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

        public bool IsActive()
        {
            return !string.IsNullOrEmpty(Address) && Balance > 0;
        }
    }

    // ============================================================================
    // Token Entity
    // ============================================================================
    public sealed class Token
    {
        [JsonPropertyName("symbol")]
        public string Symbol { get; set; } = "MOPUS";

        [JsonPropertyName("name")]
        public string Name { get; set; } = "Magnum Opus Token";

        [JsonPropertyName("decimals")]
        public int Decimals { get; set; } = 18;

        [JsonPropertyName("totalSupply")]
        public decimal TotalSupply { get; set; }

        [JsonPropertyName("currentSupply")]
        public decimal CurrentSupply { get; set; }

        public bool IsValid()
        {
            return TotalSupply > 0 && CurrentSupply >= 0;
        }
    }

    // ============================================================================
    // Transaction Processor Service
    // ============================================================================
    public static class TransactionProcessor
    {
        private static readonly ConcurrentDictionary<string, Transaction> _pendingTransactions = new();
        private static readonly ConcurrentDictionary<string, TransactionReceipt> _completedTransactions = new();

        /// <summary>
        /// Processes a new transaction through the pipeline.
        /// </summary>
        public static async Task<TransactionResult> ProcessTransactionAsync(
            Transaction transaction,
            Wallet senderWallet,
            Token token,
            string? recipientAddress = null)
        {
            if (!transaction.IsValid())
                return new TransactionResult(TransactionStatus.Failed, "Invalid transaction data");

            if (!senderWallet.IsActive())
                return new TransactionResult(TransactionStatus.Failed, "Sender wallet is inactive");

            // Simulate network delay
            await Task.Delay(10);

            // Create receipt
            var receipt = new TransactionReceipt
            {
                TransactionId = transaction.Id,
                BlockIndex = 0, // Would be set by actual blockchain
                BlockHash = "",
                GasUsed = transaction.CalculateTotalCost(),
                FeePaid = transaction.Fee,
                Status = TransactionStatus.Confirmed,
                Timestamp = transaction.Timestamp,
                ExecutionMessage = "Transaction processed successfully"
            };

            // Store receipt
            _completedTransactions[transaction.Id] = receipt;

            return new TransactionResult(transaction.Status, "Transaction processed");
        }

        /// <summary>
        /// Validates a transaction against network constraints.
        /// </summary>
        public static bool ValidateTransaction(Transaction transaction)
        {
            if (!transaction.IsValid()) return false;
            if (!transaction.ValidateNetworkConstraints()) return false;
            return true;
        }

        /// <summary>
        /// Calculates gas usage based on transaction complexity.
        /// </summary>
        public static long EstimateGasUsage(Transaction transaction)
        {
            // Base gas rate (simulated)
            const decimal baseGasRate = 21_000m;
            
            // Adjust based on transaction complexity
            decimal complexityMultiplier = 1.0;
            if (transaction.Amount > 1000m) complexityMultiplier = 1.5m;
            if (transaction.Payload.Length > 100) complexityMultiplier = 2.0m;
            
            return (long)(baseGasRate * complexityMultiplier);
        }

        /// <summary>
        /// Generates a transaction signature using HMAC-SHA256.
        /// </summary>
        public static string GenerateSignature(
            string data,
            string secretKey)
        {
            using var hmac = HMAC.Managed();
            hmac.Key = Encoding.UTF8.GetBytes(secretKey);
            return Convert.ToBase64String(hmac.ComputeHash(Encoding.UTF8.GetBytes(data)));
        }

        /// <summary>
        /// Creates a new transaction with proper structure.
        /// </summary>
        public static Transaction CreateTransaction(
            string sender,
            string recipient,
            decimal amount,
            string tokenSymbol,
            string payload,
            string signature)
        {
            var transaction = new Transaction
            {
                Id = Guid.NewGuid().ToString(),
                Sender = sender,
                Recipient = recipient,
                Amount = amount,
                TokenSymbol = tokenSymbol,
                Payload = payload,
                Signature = signature,
                Status = TransactionStatus.Pending,
                Nonce = 0
            };
            return transaction;
        }
    }

    // ============================================================================
    // Transaction Result Type
    // ============================================================================
    public sealed class TransactionResult
    {
        public TransactionStatus Status { get; set; }
        public string Message { get; set; } = string.Empty;
        public bool IsSuccessful { get; set; }

        public static TransactionResult Success(TransactionStatus status, string message)
        {
            return new TransactionResult { Status = status, Message = message };
        }

        public static TransactionResult Failure(string error)
        {
            return new TransactionResult { Status = TransactionStatus.Failed, Message = error };
        }
    }
}

// ============================================================================
// Example Usage and Testing
// ============================================================================

public class TransactionDemo
{
    public static void Main()
    {
        // Create a sample token
        var token = new Token
        {
            Symbol = "MOPUS",
            Name = "Magnum Opus Token",
            Decimals = 18,
            TotalSupply = 1000000000m
        };

        // Create a sender wallet
        var senderWallet = new Wallet
        {
            Address = "0x1234567890abcdef1234567890abcdef12345678",
            PublicKey = "0xdeadbeef1234567890abcdef1234567890",
            Balance = 1000.0m,
            Nonce = 0
        };

        // Create a recipient wallet
        var recipientWallet = new Wallet
        {
            Address = "0xabcdef1234567890abcdef1234567890abcdef12",
            PublicKey = "0xabcdef1234567890abcdef1234567890abcdef1",
            Balance = 500.0m
        };

        // Create a transaction
        var transaction = TransactionProcessor.CreateTransaction(
            sender: "0x1234567890abcdef1234567890abcdef12345678",
            recipient: "0xabcdef1234567890abcdef1234567890abcdef12",
            amount: 50.0m,
            tokenSymbol: "MOPUS",
            payload: "{"orderId": 123, "type": "trade"}",
            signature: "sample-signature-here"
        );

        // Process the transaction
        var result = await TransactionProcessor.ProcessTransactionAsync(
            transaction,
            senderWallet,
            token
        );

        Console.WriteLine($"Transaction ID: {result.TransactionId}");
        Console.WriteLine($"Status: {result.Status}");
        Console.WriteLine($"Message: {result.Message}");
    }
}
