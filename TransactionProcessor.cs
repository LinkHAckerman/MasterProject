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
    // Core Transaction Processor Service
    // ============================================================================
    public sealed class TransactionProcessor : IDisposable
    {
        private readonly ConcurrentDictionary<string, Transaction> _inFlight;
        private readonly ConcurrentQueue<Transaction> _queue;
        private readonly CancellationTokenSource _cts;
        private readonly Task _processingTask;
        private readonly SemaphoreSlim _signal;
        private bool _disposed;

        public TransactionProcessor()
        {
            _inFlight = new ConcurrentDictionary<string, Transaction>();
            _queue = new ConcurrentQueue<Transaction>();
            _cts = new CancellationTokenSource();
            _signal = new SemaphoreSlim(0);
            _processingTask = Task.Run(ProcessLoopAsync);
        }

        /// <summary>
        /// Enqueue a transaction for asynchronous processing.
        /// Returns the generated transaction Id.
        /// </summary>
        public string EnqueueTransaction(Transaction tx)
        {
            if (tx == null) throw new ArgumentNullException(nameof(tx));
            if (string.IsNullOrWhiteSpace(tx.Id))
                tx.Id = Guid.NewGuid().ToString("N");

            // Basic validation before entering the queue
            if (!tx.IsValid())
                throw new InvalidOperationException("Transaction failed basic validation.");

            if (!tx.ValidateNetworkConstraints())
                throw new InvalidOperationException("Transaction violates network constraints.");

            // Store in in‑flight dictionary for quick lookup / deduplication
            if (!_inFlight.TryAdd(tx.Id, tx))
                throw new InvalidOperationException($"Transaction with Id {tx.Id} is already being processed.");

            _queue.Enqueue(tx);
            _signal.Release();
            return tx.Id;
        }

        /// <summary>
        /// Retrieves the current status of a transaction by Id.
        /// </summary>
        public TransactionStatus? GetStatus(string transactionId)
        {
            if (string.IsNullOrWhiteSpace(transactionId)) return null;
            if (_inFlight.TryGetValue(transactionId, out var tx))
                return tx.Status;
            return null; // Unknown transaction
        }

        private async Task ProcessLoopAsync()
        {
            var token = _cts.Token;
            while (!token.IsCancellationRequested)
            {
                try
                {
                    await _signal.WaitAsync(token);
                }
                catch (OperationCanceledException)
                {
                    break;
                }

                while (_queue.TryDequeue(out var tx))
                {
                    try
                    {
                        await ProcessTransactionAsync(tx, token);
                    }
                    catch (Exception ex)
                    {
                        // Log and mark as failed
                        Console.Error.WriteLine($"[TransactionProcessor] Error processing {tx.Id}: {ex.Message}");
                        tx.Status = TransactionStatus.Failed;
                        // Generate a minimal receipt for failure
                        var receipt = new TransactionReceipt
                        {
                            TransactionId = tx.Id,
                            BlockIndex = -1,
                            BlockHash = string.Empty,
                            GasUsed = 0,
                            FeePaid = tx.Fee,
                            Status = TransactionStatus.Failed,
                            Timestamp = DateTime.UtcNow,
                            ExecutionMessage = $"Processing failed: {ex.Message}",
                            ReceiptId = GenerateReceiptId()
                        };
                        tx.ReceiptId = receipt.ReceiptId;
                        // In a real system we would persist the receipt here.
                    }
                    finally
                    {
                        // Remove from in‑flight regardless of outcome
                        _inFlight.TryRemove(tx.Id, out _);
                    }
                }
            }
        }

        private async Task ProcessTransactionAsync(Transaction tx, CancellationToken token)
        {
            // Simulate async work such as signature verification, gas estimation, etc.
            await Task.Yield(); // placeholder for real async I/O

            // 1. Verify signature (placeholder – in production use ECDSA/EdDSA verification)
            if (!VerifySignature(tx))
            {
                tx.Status = TransactionStatus.Rejected;
                throw new InvalidOperationException("Invalid signature.");
            }

            // 2. Compute gas usage (simple deterministic mock)
            tx.GasUsed = EstimateGas(tx);
            tx.FeePaid = tx.Fee; // In a real engine fee could be adjusted based on gas price

            // 3. Apply transaction effects (mock – just mark as confirmed)
            tx.Status = TransactionStatus.Confirmed;
            tx.BlockIndex = GetNextBlockIndex();
            tx.ReceiptId = GenerateReceiptId();

            // 4. Create receipt
            var receipt = new TransactionReceipt
            {
                TransactionId = tx.Id,
                BlockIndex = tx.BlockIndex,
                BlockHash = ComputeBlockHash(tx.BlockIndex),
                GasUsed = tx.GasUsed,
                FeePaid = tx.FeePaid,
                Status = tx.Status,
                Timestamp = DateTime.UtcNow,
                ExecutionMessage = "Transaction processed successfully.",
                ReceiptId = tx.ReceiptId
            };

            // In a real implementation we would persist the receipt to a database or ledger.
            // For demonstration we simply output to console.
            Console.WriteLine($"[TransactionProcessor] Receipt generated: {JsonSerializer.Serialize(receipt)}");
        }

        private bool VerifySignature(Transaction tx)
        {
            // Placeholder verification – in production replace with proper cryptographic checks.
            // Here we simply ensure the Signature field is a non‑empty hex string of length 64.
            if (string.IsNullOrWhiteSpace(tx.Signature)) return false;
            return System.Text.RegularExpressions.Regex.IsMatch(tx.Signature, "^[0-9a-fA-F]{64}$");
        }

        private long EstimateGas(Transaction tx)
        {
            // Very naive gas estimation: base 21000 + 10 per token transferred.
            return 21000 + (long)(10 * tx.Amount);
        }

        private static long _blockCounter = 0;
        private long GetNextBlockIndex()
        {
            return Interlocked.Increment(ref _blockCounter);
        }

        private string ComputeBlockHash(long blockIndex)
        {
            // Simple deterministic hash for demo purposes.
            using var sha256 = SHA256.Create();
            var bytes = Encoding.UTF8.GetBytes($"block-{blockIndex}");
            var hash = sha256.ComputeHash(bytes);
            return Convert.ToHexString(hash).ToLowerInvariant();
        }

        private string GenerateReceiptId()
        {
            return Guid.NewGuid().ToString("N");
        }

        public void Dispose()
        {
            if (_disposed) return;
            _cts.Cancel();
            _signal.Release(); // Unblock the processing loop if waiting
            try
            {
                _processingTask.Wait();
            }
            catch (AggregateException ae) when (ae.InnerExceptions.All(e => e is OperationCanceledException))
            {
                // Expected cancellation, ignore.
            }
            _cts.Dispose();
            _signal.Dispose();
            _disposed = true;
        }
    }
}
