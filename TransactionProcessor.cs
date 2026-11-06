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
    // Repository Abstraction
    // ============================================================================
    public interface ITransactionRepository
    {
        Task AddAsync(Transaction tx, CancellationToken ct = default);
        Task<Transaction?> GetByIdAsync(string id, CancellationToken ct = default);
        Task UpdateStatusAsync(string id, TransactionStatus newStatus, CancellationToken ct = default);
        Task<IReadOnlyCollection<Transaction>> GetPendingAsync(CancellationToken ct = default);
    }

    // ============================================================================
    // In-Memory Repository Implementation (for testing / mock)
    // ============================================================================
    public sealed class InMemoryTransactionRepository : ITransactionRepository
    {
        private readonly ConcurrentDictionary<string, Transaction> _store = new();

        public Task AddAsync(Transaction tx, CancellationToken ct = default)
        {
            _store[tx.Id] = tx;
            return Task.CompletedTask;
        }

        public Task<Transaction?> GetByIdAsync(string id, CancellationToken ct = default)
        {
            _store.TryGetValue(id, out var tx);
            return Task.FromResult<Transaction?>(tx);
        }

        public Task UpdateStatusAsync(string id, TransactionStatus newStatus, CancellationToken ct = default)
        {
            if (_store.TryGetValue(id, out var tx))
            {
                tx.Status = newStatus;
            }
            return Task.CompletedTask;
        }

        public Task<IReadOnlyCollection<Transaction>> GetPendingAsync(CancellationToken ct = default)
        {
            var pending = _store.Values.Where(t => t.Status == TransactionStatus.Pending).ToList();
            return Task.FromResult<IReadOnlyCollection<Transaction>>(pending);
        }
    }

    // ============================================================================
    // Transaction Processor Service
    // ============================================================================
    public sealed class TransactionProcessor
    {
        private readonly ITransactionRepository _repository;
        private readonly ILogger<TransactionProcessor> _logger;
        private readonly TimeSpan _networkDelay = TimeSpan.FromMilliseconds(250);

        public TransactionProcessor(ITransactionRepository repository, ILogger<TransactionProcessor> logger)
        {
            _repository = repository ?? throw new ArgumentNullException(nameof(repository));
            _logger = logger ?? throw new ArgumentNullException(nameof(logger));
        }

        /// <summary>
        /// Validates, stores and asynchronously confirms a transaction.
        /// </summary>
        public async Task<TransactionReceipt> ProcessTransactionAsync(Transaction tx, CancellationToken ct = default)
        {
            if (tx == null) throw new ArgumentNullException(nameof(tx));

            _logger.LogInformation("Processing transaction {TxId}", tx.Id);

            // Basic validation
            if (!tx.IsValid())
            {
                tx.Status = TransactionStatus.Rejected;
                await _repository.AddAsync(tx, ct);
                _logger.LogWarning("Transaction {TxId} rejected: basic validation failed", tx.Id);
                return CreateReceipt(tx, "Basic validation failed", TransactionStatus.Rejected);
            }

            if (!tx.ValidateNetworkConstraints())
            {
                tx.Status = TransactionStatus.Rejected;
                await _repository.AddAsync(tx, ct);
                _logger.LogWarning("Transaction {TxId} rejected: network constraints", tx.Id);
                return CreateReceipt(tx, "Network constraints violation", TransactionStatus.Rejected);
            }

            if (!SignatureVerifier.Verify(tx.Signature, tx.GetRawPayloadBytes(), tx.Sender))
            {
                tx.Status = TransactionStatus.Rejected;
                await _repository.AddAsync(tx, ct);
                _logger.LogWarning("Transaction {TxId} rejected: invalid signature", tx.Id);
                return CreateReceipt(tx, "Invalid signature", TransactionStatus.Rejected);
            }

            // Store as pending
            tx.Status = TransactionStatus.Pending;
            await _repository.AddAsync(tx, ct);

            // Simulate network propagation / mining delay
            await Task.Delay(_networkDelay, ct);

            // Confirm transaction (in a real system this would involve consensus)
            tx.Status = TransactionStatus.Confirmed;
            tx.GasUsed = EstimateGas(tx);
            tx.FeePaid = tx.Fee; // Simplified
            await _repository.UpdateStatusAsync(tx.Id, TransactionStatus.Confirmed, ct);

            _logger.LogInformation("Transaction {TxId} confirmed", tx.Id);
            return CreateReceipt(tx, "Transaction confirmed", TransactionStatus.Confirmed);
        }

        private long EstimateGas(Transaction tx)
        {
            // Very naive gas estimation: 21000 base + 10 per token transferred
            return 21000 + (long)(10 * tx.Amount);
        }

        private TransactionReceipt CreateReceipt(Transaction tx, string message, TransactionStatus status)
        {
            return new TransactionReceipt
            {
                TransactionId = tx.Id,
                BlockIndex = tx.BlockIndex,
                BlockHash = tx.ComputeHash(),
                GasUsed = tx.GasUsed,
                FeePaid = tx.FeePaid,
                Status = status,
                Timestamp = DateTime.UtcNow,
                ExecutionMessage = message,
                ReceiptId = Guid.NewGuid().ToString()
            };
        }
    }

    // ============================================================================
    // Simple Signature Verification Stub (replace with real crypto in production)
    // ============================================================================
    internal static class SignatureVerifier
    {
        public static bool Verify(string signatureBase64, byte[] payload, string publicKey)
        {
            // In a real implementation you would decode the publicKey (e.g., PEM or raw bytes)
            // and use ECDSA or Ed25519 verification. Here we perform a deterministic placeholder
            // that treats the signature as the SHA256 hash of the payload.
            if (string.IsNullOrWhiteSpace(signatureBase64)) return false;
            try
            {
                var expectedHash = Convert.ToBase64String(SHA256.Create().ComputeHash(payload));
                return expectedHash == signatureBase64;
            }
            catch
            {
                return false;
            }
        }
    }

    // ============================================================================
    // Extension helpers for JSON serialization (useful for logging / API responses)
    // ============================================================================
    public static class TransactionExtensions
    {
        private static readonly JsonSerializerOptions _options = new JsonSerializerOptions
        {
            WriteIndented = false,
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase
        };

        public static string ToJson(this Transaction tx) => JsonSerializer.Serialize(tx, _options);
        public static string ToJson(this TransactionReceipt receipt) => JsonSerializer.Serialize(receipt, _options);
    }
}
