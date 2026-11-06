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
    // Persistence abstraction for transactions and receipts
    // ============================================================================
    public interface ITransactionStore
    {
        Task SaveTransactionAsync(Transaction transaction, CancellationToken ct = default);
        Task SaveReceiptAsync(TransactionReceipt receipt, CancellationToken ct = default);
        Task<Transaction?> GetTransactionAsync(string transactionId, CancellationToken ct = default);
        Task<TransactionReceipt?> GetReceiptAsync(string receiptId, CancellationToken ct = default);
    }

    // ============================================================================
    // In‑memory implementation – useful for tests and demos
    // ============================================================================
    public sealed class InMemoryTransactionStore : ITransactionStore
    {
        private readonly ConcurrentDictionary<string, Transaction> _transactions = new();
        private readonly ConcurrentDictionary<string, TransactionReceipt> _receipts = new();

        public Task SaveTransactionAsync(Transaction transaction, CancellationToken ct = default)
        {
            _transactions[transaction.Id] = transaction;
            return Task.CompletedTask;
        }

        public Task SaveReceiptAsync(TransactionReceipt receipt, CancellationToken ct = default)
        {
            _receipts[receipt.ReceiptId] = receipt;
            return Task.CompletedTask;
        }

        public Task<Transaction?> GetTransactionAsync(string transactionId, CancellationToken ct = default)
        {
            _transactions.TryGetValue(transactionId, out var tx);
            return Task.FromResult<Transaction?>(tx);
        }

        public Task<TransactionReceipt?> GetReceiptAsync(string receiptId, CancellationToken ct = default)
        {
            _receipts.TryGetValue(receiptId, out var rcpt);
            return Task.FromResult<TransactionReceipt?>(rcpt);
        }
    }

    // ============================================================================
    // Core processor – validates, simulates execution, and persists results
    // ============================================================================
    public sealed class TransactionProcessor
    {
        private readonly ILogger<TransactionProcessor> _logger;
        private readonly ITransactionStore _store;
        private long _blockCounter = 0;
        private readonly Random _rng = new();

        public TransactionProcessor(ILogger<TransactionProcessor> logger, ITransactionStore store)
        {
            _logger = logger ?? throw new ArgumentNullException(nameof(logger));
            _store = store ?? throw new ArgumentNullException(nameof(store));
        }

        public async Task<TransactionReceipt> ProcessAsync(Transaction tx, CancellationToken ct = default)
        {
            // Basic validation
            if (!tx.IsValid())
            {
                tx.Status = TransactionStatus.Failed;
                var receipt = CreateFailedReceipt(tx, "Invalid transaction fields");
                await PersistAsync(tx, receipt, ct);
                _logger.LogWarning("Transaction {Id} failed validation: Invalid fields", tx.Id);
                return receipt;
            }

            if (!tx.ValidateNetworkConstraints())
            {
                tx.Status = TransactionStatus.Failed;
                var receipt = CreateFailedReceipt(tx, "Network constraints violation");
                await PersistAsync(tx, receipt, ct);
                _logger.LogWarning("Transaction {Id} failed validation: Network constraints", tx.Id);
                return receipt;
            }

            // Assign identifiers if missing
            if (string.IsNullOrWhiteSpace(tx.Id))
                tx.Id = Guid.NewGuid().ToString();

            // Simulate gas usage and block assignment
            tx.GasUsed = _rng.Next(21000, 500_000);
            tx.FeePaid = tx.Fee; // In a real system fee could be adjusted based on gas price
            tx.BlockIndex = Interlocked.Increment(ref _blockCounter);
            tx.Status = TransactionStatus.Confirmed;
            tx.Timestamp = DateTime.UtcNow;

            // Compute a simple block hash – in reality this would be the hash of the block header
            var blockHash = ComputeBlockHash(tx.BlockIndex, tx.Id);

            var receipt = new TransactionReceipt
            {
                TransactionId = tx.Id,
                BlockIndex = tx.BlockIndex,
                BlockHash = blockHash,
                GasUsed = tx.GasUsed,
                FeePaid = tx.FeePaid,
                Status = TransactionStatus.Confirmed,
                Timestamp = DateTime.UtcNow,
                ExecutionMessage = "Executed successfully",
                ReceiptId = Guid.NewGuid().ToString()
            };

            tx.ReceiptId = receipt.ReceiptId;

            await PersistAsync(tx, receipt, ct);
            _logger.LogInformation("Transaction {Id} processed in block {BlockIndex}", tx.Id, tx.BlockIndex);
            return receipt;
        }

        private static string ComputeBlockHash(long blockIndex, string transactionId)
        {
            using var sha = SHA256.Create();
            var input = Encoding.UTF8.GetBytes($"{blockIndex}:{transactionId}:{DateTime.UtcNow.Ticks}");
            var hash = sha.ComputeHash(input);
            return Convert.ToHexString(hash).ToLowerInvariant();
        }

        private TransactionReceipt CreateFailedReceipt(Transaction tx, string reason)
        {
            return new TransactionReceipt
            {
                TransactionId = tx.Id,
                BlockIndex = 0,
                BlockHash = string.Empty,
                GasUsed = 0,
                FeePaid = tx.Fee,
                Status = TransactionStatus.Failed,
                Timestamp = DateTime.UtcNow,
                ExecutionMessage = reason,
                ReceiptId = Guid.NewGuid().ToString()
            };
        }

        private async Task PersistAsync(Transaction tx, TransactionReceipt receipt, CancellationToken ct)
        {
            await _store.SaveTransactionAsync(tx, ct);
            await _store.SaveReceiptAsync(receipt, ct);
        }
    }

    // ============================================================================
    // Background service that consumes a channel of incoming transactions
    // ============================================================================
    public sealed class TransactionProcessorService
    {
        private readonly TransactionProcessor _processor;
        private readonly Channel<Transaction> _channel;
        private readonly ILogger<TransactionProcessorService> _logger;

        public TransactionProcessorService(TransactionProcessor processor, ILogger<TransactionProcessorService> logger)
        {
            _processor = processor ?? throw new ArgumentNullException(nameof(processor));
            _logger = logger ?? throw new ArgumentNullException(nameof(logger));
            _channel = Channel.CreateUnbounded<Transaction>(new UnboundedChannelOptions
            {
                SingleReader = true,
                SingleWriter = false
            });
        }

        public async Task EnqueueAsync(Transaction tx, CancellationToken ct = default)
        {
            await _channel.Writer.WriteAsync(tx, ct);
        }

        public async Task RunAsync(CancellationToken ct = default)
        {
            _logger.LogInformation("TransactionProcessorService started");
            try
            {
                await foreach (var tx in _channel.Reader.ReadAllAsync(ct))
                {
                    try
                    {
                        await _processor.ProcessAsync(tx, ct);
                    }
                    catch (Exception ex)
                    {
                        _logger.LogError(ex, "Error processing transaction {Id}", tx.Id);
                    }
                }
            }
            catch (OperationCanceledException) when (ct.IsCancellationRequested)
            {
                // Graceful shutdown
            }
            finally
            {
                _logger.LogInformation("TransactionProcessorService stopped");
            }
        }
    }

    // ============================================================================
    // DI registration helpers
    // ============================================================================
    public static class ServiceCollectionExtensions
    {
        public static IServiceCollection AddMagnumOpusCore(this IServiceCollection services)
        {
            services.AddSingleton<ITransactionStore, InMemoryTransactionStore>();
            services.AddSingleton<TransactionProcessor>();
            services.AddSingleton<TransactionProcessorService>();
            return services;
        }
    }
}
