using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json.Serialization;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Extensions.Logging;

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
        Rejected = 3,
        Cancelled = 4,
        Refunded = 5
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
            if (Amount > 1_000_000m) return false; // Max reasonable amount
            if (Fee > 10m) return false; // Fee cap
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
        /// In a real implementation, this would query the current gas price.
        /// </summary>
        public decimal CalculateTotalCost()
        {
            // Base cost is amount + fee
            decimal baseCost = Amount + Fee;
            // Add estimated gas cost (simulated)
            decimal estimatedGasCost = 50.0m;
            return baseCost + estimatedGasCost;
        }

        /// <summary>
        /// Validates transaction against network constraints.
        /// </summary>
        public bool ValidateNetworkConstraints()
        {
            if (Amount > 1_000_000m) return false; // Max reasonable amount
            if (Fee > 10m) return false; // Fee cap
            if (Amount <= 0) return false;
            if (Fee < 0) return false;
            return true;
        }

        /// <summary>
        /// Updates transaction status based on network confirmation.
        /// </summary>
        public void UpdateStatus(TransactionStatus newStatus, string reason = "")
        {
            // reason currently unused but kept for future audit trails
            Status = newStatus;
        }

        /// <summary>
        /// Simulates transaction signing using a private key.
        /// In a production system this would involve ECDSA/secp256k1 signing.
        /// Here we simply hash the payload with the private key as a salt.
        /// </summary>
        public bool Sign(string privateKeyHex)
        {
            if (string.IsNullOrWhiteSpace(privateKeyHex))
                throw new ArgumentException("Private key must be provided", nameof(privateKeyHex));

            // Derive a deterministic signature for demo purposes
            using var sha256 = SHA256.Create();
            var payload = GetRawPayloadBytes();
            var keyBytes = Convert.FromHexString(privateKeyHex);
            var combined = new byte[payload.Length + keyBytes.Length];
            Buffer.BlockCopy(payload, 0, combined, 0, payload.Length);
            Buffer.BlockCopy(keyBytes, 0, combined, payload.Length, keyBytes.Length);
            var sigBytes = sha256.ComputeHash(combined);
            Signature = Convert.ToHexString(sigBytes).ToLowerInvariant();
            return true;
        }
    }

    // ============================================================================
    // Transaction Processor Service
    // ============================================================================
    /// <summary>
    /// Handles high‑throughput ingestion, validation and asynchronous processing of
    /// transactions. It is deliberately lightweight – the heavy cryptographic work
    /// is delegated to the Transaction entity itself.
    /// </summary>
    public sealed class TransactionProcessor : IDisposable
    {
        private readonly ILogger<TransactionProcessor> _logger;
        private readonly ConcurrentQueue<Transaction> _queue = new();
        private readonly SemaphoreSlim _signal = new(0);
        private readonly CancellationTokenSource _cts = new();
        private readonly Task _backgroundTask;
        private readonly int _maxDegreeOfParallelism;

        public TransactionProcessor(ILogger<TransactionProcessor> logger, int maxDegreeOfParallelism = 4)
        {
            _logger = logger ?? throw new ArgumentNullException(nameof(logger));
            _maxDegreeOfParallelism = maxDegreeOfParallelism > 0 ? maxDegreeOfParallelism : 1;
            _backgroundTask = Task.Run(ProcessLoopAsync);
        }

        /// <summary>
        /// Enqueue a transaction for processing. Returns false if the transaction is
        /// malformed or fails basic validation.
        /// </summary>
        public bool Enqueue(Transaction tx)
        {
            if (tx == null) throw new ArgumentNullException(nameof(tx));
            if (!tx.IsValid())
            {
                _logger.LogWarning("Rejected invalid transaction {TxId}", tx.Id);
                return false;
            }
            _queue.Enqueue(tx);
            _signal.Release();
            _logger.LogInformation("Enqueued transaction {TxId}", tx.Id);
            return true;
        }

        private async Task ProcessLoopAsync()
        {
            var token = _cts.Token;
            var workers = new List<Task>();
            for (int i = 0; i < _maxDegreeOfParallelism; i++)
            {
                workers.Add(Task.Run(() => WorkerAsync(token), token));
            }
            await Task.WhenAll(workers);
        }

        private async Task WorkerAsync(CancellationToken token)
        {
            while (!token.IsCancellationRequested)
            {
                await _signal.WaitAsync(token);
                if (token.IsCancellationRequested) break;

                if (_queue.TryDequeue(out var tx))
                {
                    try
                    {
                        await ProcessTransactionAsync(tx, token);
                    }
                    catch (Exception ex)
                    {
                        _logger.LogError(ex, "Error processing transaction {TxId}", tx.Id);
                        tx.UpdateStatus(TransactionStatus.Failed, ex.Message);
                    }
                }
            }
        }

        private async Task ProcessTransactionAsync(Transaction tx, CancellationToken token)
        {
            // Simulate network latency / gas consumption
            await Task.Delay(TimeSpan.FromMilliseconds(100), token);

            // Example: sign with a mock private key derived from sender address
            var mockPrivateKey = DeriveMockPrivateKey(tx.Sender);
            tx.Sign(mockPrivateKey);

            // Re‑validate after signing (signature presence)
            if (string.IsNullOrWhiteSpace(tx.Signature))
            {
                tx.UpdateStatus(TransactionStatus.Rejected, "Missing signature");
                _logger.LogWarning("Transaction {TxId} rejected – signature missing after signing step", tx.Id);
                return;
            }

            // Simulate gas usage calculation
            tx.GasUsed = new Random().Next(21000, 800000);
            tx.FeePaid = tx.Fee; // In a real system this would be fee * gas price

            // Mark as confirmed for demo purposes
            tx.UpdateStatus(TransactionStatus.Confirmed);
            _logger.LogInformation("Transaction {TxId} processed and confirmed. GasUsed={GasUsed}, FeePaid={FeePaid}",
                tx.Id, tx.GasUsed, tx.FeePaid);
        }

        private string DeriveMockPrivateKey(string address)
        {
            // Very naive deterministic mock – DO NOT use in production!
            var hash = SHA256.HashData(Encoding.UTF8.GetBytes(address));
            return Convert.ToHexString(hash).ToLowerInvariant();
        }

        public void Dispose()
        {
            _cts.Cancel();
            _signal.Release(); // unblock any waiting workers
            try
            {
                _backgroundTask.Wait(TimeSpan.FromSeconds(5));
            }
            catch { /* ignore */ }
            _cts.Dispose();
            _signal.Dispose();
        }
    }
}
