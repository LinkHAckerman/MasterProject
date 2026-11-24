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
    // Transaction objects. Utilises System.Threading.Channels for high-throughput
    // back-pressure aware pipelines.
    // ============================================================================
    public class TransactionProcessor : IAsyncDisposable
    {
        private readonly Channel<Transaction> _channel;
        private readonly ILogger<TransactionProcessor> _logger;
        private readonly CancellationTokenSource _cts = new();
        private readonly Task _backgroundTask;
        private readonly TimeSpan _processingDelay = TimeSpan.FromMilliseconds(150); // simulate work
        private readonly ConcurrentDictionary<string, Transaction> _processedTransactions = new();
        private bool _disposed = false;

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
            _logger.LogInformation("TransactionProcessor started with capacity {Capacity}.", boundedCapacity);
        }

        /// <summary>
        /// Enqueue a transaction for processing. The method returns immediately; the
        /// transaction will be processed asynchronously.
        /// </summary>
        public async ValueTask EnqueueAsync(Transaction tx)
        {
            if (tx == null) throw new ArgumentNullException(nameof(tx));
            if (_disposed) throw new ObjectDisposedException(nameof(TransactionProcessor));
            
            tx.UpdateStatus(TransactionStatus.Queued);
            await _channel.Writer.WriteAsync(tx, _cts.Token);
            _logger.LogInformation("Transaction {Id} queued for processing.", tx.Id);
        }

        /// <summary>
        /// Try to enqueue a transaction without blocking. Returns false if the channel is full.
        /// </summary>
        public bool TryEnqueue(Transaction tx)
        {
            if (tx == null) throw new ArgumentNullException(nameof(tx));
            if (_disposed) return false;

            tx.UpdateStatus(TransactionStatus.Queued);
            var result = _channel.Writer.TryWrite(tx);
            if (result)
            {
                _logger.LogInformation("Transaction {Id} queued for processing.", tx.Id);
            }
            else
            {
                _logger.LogWarning("Failed to queue transaction {Id}: channel full.", tx.Id);
            }
            return result;
        }

        /// <summary>
        /// Get a previously processed transaction by ID.
        /// </summary>
        public bool TryGetProcessedTransaction(string id, out Transaction? tx)
        {
            return _processedTransactions.TryGetValue(id, out tx);
        }

        /// <summary>
        /// Get count of currently queued transactions.
        /// </summary>
        public int QueuedCount => _channel.Reader.Count;

        /// <summary>
        /// Get count of processed transactions in memory.
        /// </summary>
        public int ProcessedCount => _processedTransactions.Count;

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
            // Mark as processing
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

            // Simulated signature verification
            if (!tx.VerifySignature(tx.Sender))
            {
                tx.UpdateStatus(TransactionStatus.Rejected, "Signature verification failed");
                await NotifyTransactionProcessedAsync(tx);
                return;
            }

            // Simulate gas usage based on transaction type
            tx.GasUsed = tx.Type switch
            {
                TransactionType.Transfer => 21000,
                TransactionType.ContractCall => 50000,
                TransactionType.TokenMint => 80000,
                TransactionType.TokenBurn => 60000,
                TransactionType.LiquiditySwap => 120000,
                TransactionType.StakingDeposit => 45000,
                TransactionType.NFTMint => 95000,
                _ => 21000
            };

            // Calculate fee paid based on gas used
            tx.FeePaid = (decimal)tx.GasUsed * 0.00001m;

            // Simulate block inclusion
            tx.BlockIndex = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
            tx.ReceiptId = GenerateReceiptId(tx);

            // Mark as confirmed
            tx.UpdateStatus(TransactionStatus.Confirmed);
            _logger.LogInformation("Transaction {Id} confirmed. Gas used: {GasUsed}, Fee paid: {FeePaid}, Block: {BlockIndex}",
                tx.Id, tx.GasUsed, tx.FeePaid, tx.BlockIndex);

            await NotifyTransactionProcessedAsync(tx);
        }

        private string GenerateReceiptId(Transaction tx)
        {
            using var sha256 = SHA256.Create();
            var receiptData = $"{tx.Id}:{tx.BlockIndex}:{tx.GasUsed}:{tx.FeePaid}:{DateTime.UtcNow.Ticks}";
            var bytes = Encoding.UTF8.GetBytes(receiptData);
            var hash = sha256.ComputeHash(bytes);
            return "0x" + Convert.ToHexString(hash).ToLowerInvariant()[..64];
        }

        private async Task NotifyTransactionProcessedAsync(Transaction tx)
        {
            // Store processed transaction for lookup
            _processedTransactions.TryAdd(tx.Id, tx);

            // Raise event if subscribers exist
            if (TransactionProcessed != null)
            {
                var tasks = TransactionProcessed.GetInvocationList()
                    .Cast<Func<Transaction, Task>>()
                    .Select(handler => SafeInvokeHandler(handler, tx));
                await Task.WhenAll(tasks);
            }
        }

        private async Task SafeInvokeHandler(Func<Transaction, Task> handler, Transaction tx)
        {
            try
            {
                await handler(tx);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error in TransactionProcessed event handler for transaction {Id}", tx.Id);
            }
        }

        /// <summary>
        /// Gracefully shuts down the processor, waiting for queued transactions to complete.
        /// </summary>
        public async ValueTask DisposeAsync()
        {
            if (_disposed) return;
            _disposed = true;

            _logger.LogInformation("Shutting down TransactionProcessor...");

            // Stop accepting new transactions
            _channel.Writer.TryComplete();

            // Signal cancellation
            _cts.Cancel();

            // Wait for background task to complete
            try
            {
                await _backgroundTask;
            }
            catch (OperationCanceledException)
            {
                // Expected
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error during TransactionProcessor shutdown.");
            }

            _cts.Dispose();
            _logger.LogInformation("TransactionProcessor stopped. Processed {Count} transactions.", _processedTransactions.Count);
        }
    }
}