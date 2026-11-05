using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
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
        public string ExecutionMessage { get; set; } = string.Empty;

        [JsonPropertyName("receiptId")]
        public string ReceiptId { get; set; } = string.Empty;
    }

    // ============================================================================
    // Repository Abstraction for Persistence (In‑Memory for demo)
    // ============================================================================
    public interface ITransactionRepository
    {
        Task AddAsync(Transaction tx);
        Task<Transaction?> GetAsync(string id);
        Task UpdateAsync(Transaction tx);
        Task AddReceiptAsync(TransactionReceipt receipt);
        Task<TransactionReceipt?> GetReceiptAsync(string receiptId);
    }

    public sealed class InMemoryTransactionRepository : ITransactionRepository
    {
        private readonly ConcurrentDictionary<string, Transaction> _transactions = new();
        private readonly ConcurrentDictionary<string, TransactionReceipt> _receipts = new();

        public Task AddAsync(Transaction tx)
        {
            _transactions[tx.Id] = tx;
            return Task.CompletedTask;
        }

        public Task<Transaction?> GetAsync(string id)
        {
            _transactions.TryGetValue(id, out var tx);
            return Task.FromResult<Transaction?>(tx);
        }

        public Task UpdateAsync(Transaction tx)
        {
            _transactions[tx.Id] = tx;
            return Task.CompletedTask;
        }

        public Task AddReceiptAsync(TransactionReceipt receipt)
        {
            _receipts[receipt.ReceiptId] = receipt;
            return Task.CompletedTask;
        }

        public Task<TransactionReceipt?> GetReceiptAsync(string receiptId)
        {
            _receipts.TryGetValue(receiptId, out var receipt);
            return Task.FromResult<TransactionReceipt?>(receipt);
        }
    }

    // ============================================================================
    // Core Transaction Processor
    // ============================================================================
    public sealed class TransactionProcessor : IDisposable
    {
        private readonly ITransactionRepository _repository;
        private readonly ConcurrentQueue<string> _pendingQueue = new();
        private readonly CancellationTokenSource _cts = new();
        private readonly Task _processingTask;
        private readonly TimeSpan _processingDelay = TimeSpan.FromMilliseconds(250);

        /// <summary>
        /// Fires when a transaction has been fully processed and a receipt is generated.
        /// </summary>
        public event Action<TransactionReceipt>? ReceiptGenerated;

        public TransactionProcessor(ITransactionRepository repository)
        {
            _repository = repository ?? throw new ArgumentNullException(nameof(repository));
            _processingTask = Task.Run(ProcessLoopAsync);
        }

        /// <summary>
        /// Enqueue a transaction for asynchronous processing.
        /// </summary>
        public async Task EnqueueAsync(Transaction tx)
        {
            if (tx == null) throw new ArgumentNullException(nameof(tx));

            // Assign a deterministic Id if missing
            if (string.IsNullOrWhiteSpace(tx.Id))
                tx.Id = Guid.NewGuid().ToString("N");

            // Basic validation before accepting
            if (!tx.IsValid() || !tx.ValidateNetworkConstraints())
            {
                tx.Status = TransactionStatus.Rejected;
                await _repository.AddAsync(tx);
                return;
            }

            tx.Status = TransactionStatus.Pending;
            await _repository.AddAsync(tx);
            _pendingQueue.Enqueue(tx.Id);
        }

        private async Task ProcessLoopAsync()
        {
            while (!_cts.IsCancellationRequested)
            {
                if (_pendingQueue.TryDequeue(out var txId))
                {
                    var tx = await _repository.GetAsync(txId);
                    if (tx == null) continue; // Should never happen

                    try
                    {
                        // Simulate work (hashing, gas calculation, etc.)
                        await Task.Delay(_processingDelay, _cts.Token);
                        tx.GasUsed = new Random().Next(21000, 50000);
                        tx.FeePaid = tx.Fee;
                        tx.BlockIndex = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
                        tx.Status = TransactionStatus.Confirmed;
                        tx.ReceiptId = Guid.NewGuid().ToString("N");
                        await _repository.UpdateAsync(tx);

                        var receipt = tx.CreateReceipt();
                        await _repository.AddReceiptAsync(receipt);
                        ReceiptGenerated?.Invoke(receipt);
                    }
                    catch (Exception ex)
                    {
                        tx.Status = TransactionStatus.Failed;
                        await _repository.UpdateAsync(tx);
                        var receipt = new TransactionReceipt
                        {
                            TransactionId = tx.Id,
                            BlockIndex = tx.BlockIndex,
                            BlockHash = string.Empty,
                            GasUsed = tx.GasUsed,
                            FeePaid = tx.FeePaid,
                            Status = TransactionStatus.Failed,
                            Timestamp = DateTime.UtcNow,
                            ExecutionMessage = $"Processing failed: {ex.Message}",
                            ReceiptId = Guid.NewGuid().ToString("N")
                        };
                        await _repository.AddReceiptAsync(receipt);
                        ReceiptGenerated?.Invoke(receipt);
                    }
                }
                else
                {
                    // No pending work – back‑off a little
                    await Task.Delay(100, _cts.Token);
                }
            }
        }

        public void Dispose()
        {
            _cts.Cancel();
            try
            {
                _processingTask.Wait();
            }
            catch (AggregateException) { }
            _cts.Dispose();
        }
    }

    // ============================================================================
    // Extension helpers for Transaction
    // ============================================================================
    public static class TransactionExtensions
    {
        public static TransactionReceipt CreateReceipt(this Transaction tx)
        {
            return new TransactionReceipt
            {
                TransactionId = tx.Id,
                BlockIndex = tx.BlockIndex,
                BlockHash = tx.ComputeHash(),
                GasUsed = tx.GasUsed,
                FeePaid = tx.FeePaid,
                Status = tx.Status,
                Timestamp = DateTime.UtcNow,
                ExecutionMessage = $"Transaction {tx.Id} processed successfully.",
                ReceiptId = tx.ReceiptId
            };
        }
    }
}
