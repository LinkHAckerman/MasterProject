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
    // TransactionProcessor – handles queuing, validation and async processing of
    // Transaction objects. Utilises System.Threading.Channels for high‑throughput
    // back‑pressure aware pipelines.
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
                        await RaiseProcessedEventAsync(tx);
                    }
                }
            }
            catch (OperationCanceledException)
            {
                // Expected during shutdown – just exit gracefully.
                _logger.LogInformation("Transaction processing loop cancelled.");
            }
            catch (Exception ex)
            {
                _logger.LogCritical(ex, "Unexpected error in processing loop.");
            }
        }

        private async Task ProcessTransactionAsync(Transaction tx)
        {
            // Mark as processing
            tx.UpdateStatus(TransactionStatus.Processing);
            _logger.LogDebug("Processing transaction {Id}", tx.Id);

            // Basic validation
            if (!tx.IsValid())
            {
                tx.UpdateStatus(TransactionStatus.Rejected, "Invalid transaction fields");
                await RaiseProcessedEventAsync(tx);
                return;
            }

            // Simulated signature verification – in a real system we would retrieve the public key.
            // Here we assume the public key is the same as the sender identifier for demo purposes.
            if (!tx.VerifySignature(tx.Sender))
            {
                tx.UpdateStatus(TransactionStatus.Rejected, "Signature verification failed");
                await RaiseProcessedEventAsync(tx);
                return;
            }

            // Simulate work (e.g., state transition, gas calculation)
            await Task.Delay(_processingDelay, _cts.Token);

            // Simulated gas usage based on transaction type
            tx.GasUsed = tx.Type switch
            {
                TransactionType.Transfer => 21000,
                TransactionType.ContractCall => 50000,
                TransactionType.TokenMint => 80000,
                TransactionType.TokenBurn => 60000,
                TransactionType.LiquiditySwap => 120000,
                TransactionType.StakingDeposit => 90000,
                TransactionType.NFTMint => 150000,
                _ => 30000
            };

            // Record fee paid (could be different from requested fee after gas calculation)
            tx.FeePaid = tx.Fee + (decimal)tx.GasUsed * 0.00001m;

            // Mark as confirmed
            tx.UpdateStatus(TransactionStatus.Confirmed);
            _logger.LogInformation("Transaction {Id} confirmed. GasUsed={GasUsed}, FeePaid={FeePaid}",
                tx.Id, tx.GasUsed, tx.FeePaid);

            await RaiseProcessedEventAsync(tx);
        }

        private async Task RaiseProcessedEventAsync(Transaction tx)
        {
            if (TransactionProcessed != null)
            {
                var handlers = TransactionProcessed.GetInvocationList()
                    .Cast<Func<Transaction, Task>>();
                var tasks = handlers.Select(h => SafeInvokeHandlerAsync(h, tx));
                await Task.WhenAll(tasks);
            }
        }

        private static async Task SafeInvokeHandlerAsync(Func<Transaction, Task> handler, Transaction tx)
        {
            try
            {
                await handler(tx);
            }
            catch
            {
                // Swallow exceptions from user‑provided handlers to avoid crashing the processor.
            }
        }

        /// <summary>
        /// Initiates a graceful shutdown, completing any in‑flight work.
        /// </summary>
        public async ValueTask DisposeAsync()
        {
            // Signal cancellation
            _cts.Cancel();
            // Complete the writer side so the reader finishes once the queue drains.
            _channel.Writer.Complete();
            try
            {
                await _backgroundTask.ConfigureAwait(false);
            }
            catch (OperationCanceledException)
            {
                // Expected – ignore.
            }
            finally
            {
                _cts.Dispose();
            }
        }
    }
}
