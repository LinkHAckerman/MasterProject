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

namespace MagnumOpus.Backend.Core
{
    // ============================================================================
    // Transaction Status Enumeration
    // ============================================================================
    public enum TransactionStatus
    {
        Pending = 0,
        Queued = 1,
        Processing = 2,
        Confirmed = 3,
        Failed = 4,
        Rejected = 5,
        Cancelled = 6,
        Refunded = 7
    }

    // ============================================================================
    // Transaction Type Enumeration
    // ============================================================================
    public enum TransactionType
    {
        Transfer = 0,
        ContractCall = 1,
        TokenMint = 2,
        TokenBurn = 3,
        LiquiditySwap = 4,
        StakingDeposit = 5,
        NFTMint = 6
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

        [JsonPropertyName("type")]
        public TransactionType Type { get; set; } = TransactionType.Transfer;

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
        public long BlockIndex { get; set; } = -1;

        [JsonPropertyName("receiptId")]
        public string ReceiptId { get; set; } = string.Empty;

        [JsonPropertyName("failureReason")]
        public string FailureReason { get; set; } = string.Empty;

        public bool IsValid()
        {
            if (string.IsNullOrWhiteSpace(Sender)) return false;
            if (string.IsNullOrWhiteSpace(Recipient)) return false;
            if (Amount <= 0) return false;
            if (Fee < 0) return false;
            if (Amount > 1_000_000m) return false;
            if (Fee > 10m) return false;
            return true;
        }

        public override string ToString()
        {
            return $"{Id}:{Sender} -> {Recipient} | {Amount} {TokenSymbol} | Type: {Type} | Fee: {Fee} | Status: {Status}";
        }

        public byte[] GetRawPayloadBytes()
        {
            return Encoding.UTF8.GetBytes(ToString());
        }

        public string ComputeHash()
        {
            using var sha256 = SHA256.Create();
            var rawString = $"{Id}:{Sender}:{Recipient}:{Amount}:{Fee}:{Nonce}:{TokenSymbol}:{Type}:{Payload}";
            var bytes = Encoding.UTF8.GetBytes(rawString);
            var hash = sha256.ComputeHash(bytes);
            return Convert.ToHexString(hash).ToLowerInvariant();
        }

        public decimal CalculateTotalCost()
        {
            decimal baseCost = Amount + Fee;
            decimal estimatedGasCost = GasUsed > 0 ? (decimal)GasUsed * 0.00001m : 0.0005m;
            return baseCost + estimatedGasCost;
        }

        public bool ValidateNetworkConstraints()
        {
            if (Amount > 1_000_000m) return false;
            if (Fee > 10m) return false;
            if (Amount <= 0) return false;
            if (Fee < 0) return false;
            return true;
        }

        public void UpdateStatus(TransactionStatus newStatus, string reason = "")
        {
            Status = newStatus;
            if (!string.IsNullOrEmpty(reason))
            {
                FailureReason = reason;
            }
        }

        /// <summary>
        /// Simulated signing using a private key string. In a real implementation this would
        /// employ ECDSA or Ed25519 with proper key handling.
        /// </summary>
        public void Sign(string privateKey)
        {
            if (string.IsNullOrEmpty(privateKey))
                throw new ArgumentException("Private key must be provided for signing.");

            // Simple deterministic placeholder: hash of (ComputeHash + privateKey)
            using var sha256 = SHA256.Create();
            var combined = Encoding.UTF8.GetBytes(ComputeHash() + privateKey);
            var sigBytes = sha256.ComputeHash(combined);
            Signature = Convert.ToBase64String(sigBytes);
        }

        /// <summary>
        /// Simulated verification using a public key string. Matches the placeholder Sign method.
        /// </summary>
        public bool VerifySignature(string publicKey)
        {
            if (string.IsNullOrEmpty(publicKey)) return false;
            // Recreate the signature using the publicKey (which in this placeholder is the same as privateKey)
            using var sha256 = SHA256.Create();
            var combined = Encoding.UTF8.GetBytes(ComputeHash() + publicKey);
            var expected = Convert.ToBase64String(sha256.ComputeHash(combined));
            return expected == Signature;
        }
    }

    // ============================================================================
    // TransactionProcessor  handles queuing, validation and async processing of
    // Transaction objects. Utilises System.Threading.Channels for highthroughput
    // backpressure aware pipelines.
    // ============================================================================
    public class TransactionProcessor : IAsyncDisposable
    {
        private readonly Channel<Transaction> _channel;
        private readonly ILogger<TransactionProcessor> _logger;
        private readonly CancellationTokenSource _cts = new();
        private readonly Task _backgroundTask;
        private readonly TimeSpan _processingDelay = TimeSpan.FromMilliseconds(150); // simulate work

        /// <summary>
        /// Event raised after a transaction has been processed (either confirmed or failed).
        /// </summary>
        public event Func<Transaction, Task>? TransactionProcessed;

        public TransactionProcessor(ILogger<TransactionProcessor> logger, int boundedCapacity = 10_000)
        {
            _logger = logger ?? throw new ArgumentNullException(nameof(logger));
            var options = new BoundedChannelOptions(boundedCapacity)
            {
                FullMode = BoundedChannelFullMode.Wait,
                SingleReader = true,
                SingleWriter = false
            };
            _channel = Channel.CreateBounded<Transaction>(options);
            _backgroundTask = Task.Run(ProcessLoopAsync);
        }

        /// <summary>
        /// Enqueue a transaction for processing. The method returns immediately; the
        /// transaction will be processed asynchronously.
        /// </summary>
        public async ValueTask EnqueueAsync(Transaction tx)
        {
            if (tx == null) throw new ArgumentNullException(nameof(tx));
            tx.UpdateStatus(TransactionStatus.Queued);
            await _channel.Writer.WriteAsync(tx, _cts.Token);
            _logger.LogInformation("Transaction {Id} queued for processing.", tx.Id);
        }

        private async Task ProcessLoopAsync()
        {
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
                        _logger.LogError(ex, "Error processing transaction {Id}", tx.Id);
                        tx.UpdateStatus(TransactionStatus.Failed, ex.Message);
                        await NotifyTransactionProcessedAsync(tx);
                    }
                }
            }
            catch (OperationCanceledException)
            {
                _logger.LogInformation("Transaction processing loop cancelled.");
            }
            catch (Exception ex)
            {
                _logger.LogCritical(ex, "Unexpected error in transaction processing loop.");
            }
        }

        private async Task ProcessTransactionAsync(Transaction tx)
        {
            tx.UpdateStatus(TransactionStatus.Processing);
            _logger.LogInformation("Processing transaction {Id}", tx.Id);

            // Simulate processing delay
            await Task.Delay(_processingDelay, _cts.Token);

            // Validate transaction
            if (!tx.IsValid())
            {
                tx.UpdateStatus(TransactionStatus.Rejected, "Invalid transaction data.");
                await NotifyTransactionProcessedAsync(tx);
                return;
            }

            // Validate network constraints
            if (!tx.ValidateNetworkConstraints())
            {
                tx.UpdateStatus(TransactionStatus.Rejected, "Transaction exceeds network constraints.");
                await NotifyTransactionProcessedAsync(tx);
                return;
            }

            // Simulate successful processing
            tx.UpdateStatus(TransactionStatus.Confirmed);
            tx.ReceiptId = Guid.NewGuid().ToString();
            tx.FeePaid = tx.Fee;
            tx.GasUsed = 21000; // Simulated gas used

            _logger.LogInformation("Transaction {Id} processed successfully.", tx.Id);
            await NotifyTransactionProcessedAsync(tx);
        }

        private async Task NotifyTransactionProcessedAsync(Transaction tx)
        {
            if (TransactionProcessed != null)
            {
                await TransactionProcessed(tx);
            }
        }

        public async ValueTask DisposeAsync()
        {
            _cts.Cancel();
            await _backgroundTask;
            _channel.Writer.Complete();
            _cts.Dispose();
        }
    }
}