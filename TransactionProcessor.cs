using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Threading;
using System.Threading.Channels;
using System.Threading.Tasks;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.DependencyInjection;

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
        public string ExecutionMessage { get; set; } = string.Empty;

        [JsonPropertyName("receiptId")]
        public string ReceiptId { get; set; } = string.Empty;
    }

    // ============================================================================
    // Simple In-Memory Ledger (Thread‑Safe)
    // ============================================================================
    public static class Ledger
    {
        // Balance per address (could be wallet address, public key, etc.)
        private static readonly ConcurrentDictionary<string, decimal> _balances = new();

        public static decimal GetBalance(string address)
        {
            if (string.IsNullOrWhiteSpace(address)) throw new ArgumentException("address cannot be null or empty", nameof(address));
            return _balances.GetOrAdd(address, 0m);
        }

        public static void AdjustBalance(string address, decimal delta)
        {
            if (string.IsNullOrWhiteSpace(address)) throw new ArgumentException("address cannot be null or empty", nameof(address));
            _balances.AddOrUpdate(address, delta, (key, old) => old + delta);
        }
    }

    // ============================================================================
    // Transaction Processor Service
    // ============================================================================
    public sealed class TransactionProcessor : IAsyncDisposable
    {
        private readonly Channel<Transaction> _channel;
        private readonly ILogger<TransactionProcessor> _logger;
        private readonly CancellationTokenSource _cts = new();
        private readonly Task _backgroundTask;

        public TransactionProcessor(ILogger<TransactionProcessor> logger, int capacity = 1000)
        {
            _logger = logger ?? throw new ArgumentNullException(nameof(logger));
            var options = new BoundedChannelOptions(capacity)
            {
                FullMode = BoundedChannelFullMode.Wait,
                SingleReader = true,
                SingleWriter = false
            };
            _channel = Channel.CreateBounded<Transaction>(options);
            _backgroundTask = Task.Run(ProcessLoopAsync);
        }

        /// <summary>
        /// Enqueue a transaction for asynchronous processing.
        /// </summary>
        public async ValueTask EnqueueAsync(Transaction tx)
        {
            if (tx == null) throw new ArgumentNullException(nameof(tx));
            await _channel.Writer.WriteAsync(tx, _cts.Token);
            _logger.LogInformation("Transaction {TxId} enqueued", tx.Id);
        }

        private async Task ProcessLoopAsync()
        {
            _logger.LogInformation("TransactionProcessor background loop started");
            try
            {
                await foreach (var tx in _channel.Reader.ReadAllAsync(_cts.Token))
                {
                    try
                    {
                        await ProcessTransactionAsync(tx);
                    }
                    catch (Exception ex)
                    {
                        _logger.LogError(ex, "Failed to process transaction {TxId}", tx.Id);
                    }
                }
            }
            catch (OperationCanceledException)
            {
                // Expected during shutdown
            }
            finally
            {
                _logger.LogInformation("TransactionProcessor background loop stopped");
            }
        }

        private async Task ProcessTransactionAsync(Transaction tx)
        {
            // Basic validation
            if (!tx.IsValid())
            {
                tx.Status = TransactionStatus.Rejected;
                _logger.LogWarning("Transaction {TxId} rejected: basic validation failed", tx.Id);
                return;
            }

            if (!tx.ValidateNetworkConstraints())
            {
                tx.Status = TransactionStatus.Rejected;
                _logger.LogWarning("Transaction {TxId} rejected: network constraints violated", tx.Id);
                return;
            }

            if (!SignatureVerifier.VerifySignature(tx))
            {
                tx.Status = TransactionStatus.Rejected;
                _logger.LogWarning("Transaction {TxId} rejected: signature verification failed", tx.Id);
                return;
            }

            // Simulate gas consumption & fee deduction
            tx.GasUsed = EstimateGas(tx);
            tx.FeePaid = tx.Fee; // In a real system fee could be dynamic based on gas

            // Apply balances atomically
            ApplyTransaction(tx);

            tx.Status = TransactionStatus.Confirmed;
            _logger.LogInformation("Transaction {TxId} confirmed. Sender: {Sender}, Recipient: {Recipient}, Amount: {Amount}",
                tx.Id, tx.Sender, tx.Recipient, tx.Amount);

            // In a real system we would persist a receipt and broadcast events.
            await Task.CompletedTask; // placeholder for async persistence
        }

        private static long EstimateGas(Transaction tx)
        {
            // Very naive gas model: 10 units per transaction + 1 per token transferred
            return 10 + (long)Math.Ceiling(tx.Amount);
        }

        private static void ApplyTransaction(Transaction tx)
        {
            // Debit sender (including fee)
            Ledger.AdjustBalance(tx.Sender, -(tx.Amount + tx.FeePaid));
            // Credit recipient
            Ledger.AdjustBalance(tx.Recipient, tx.Amount);
        }

        public async ValueTask DisposeAsync()
        {
            _cts.Cancel();
            _channel.Writer.Complete();
            try
            {
                await _backgroundTask;
            }
            catch (Exception ex) when (ex is OperationCanceledException)
            {
                // ignore
            }
            _cts.Dispose();
        }
    }

    // ============================================================================
    // Simple Signature Verification Helper (placeholder implementation)
    // ============================================================================
    public static class SignatureVerifier
    {
        /// <summary>
        /// Verifies that the transaction's signature matches the hash of its payload.
        /// In a production system this would involve ECDSA/secp256k1 verification against the sender's public key.
        /// Here we simply compare the stored signature with the SHA‑256 hash for demonstration purposes.
        /// </summary>
        public static bool VerifySignature(Transaction tx)
        {
            if (string.IsNullOrWhiteSpace(tx.Signature)) return false;
            var expected = tx.ComputeHash();
            return string.Equals(expected, tx.Signature, StringComparison.OrdinalIgnoreCase);
        }
    }
}
