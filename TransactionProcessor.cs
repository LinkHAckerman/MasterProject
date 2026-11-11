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
            if (Amount > 1_000_000m) return false; // Max reasonable amount
            if (Fee > 10m) return false; // Fee cap
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

        public bool Sign(string privateKeyHex)
        {
            if (string.IsNullOrWhiteSpace(privateKeyHex))
                throw new ArgumentException("Private key cannot be null or empty.", nameof(privateKeyHex));

            var hash = ComputeHash();
            using var hmac = new HMACSHA256(Encoding.UTF8.GetBytes(privateKeyHex));
            var sigBytes = hmac.ComputeHash(Encoding.UTF8.GetBytes(hash));
            Signature = Convert.ToHexString(sigBytes).ToLowerInvariant();
            return true;
        }

        public bool VerifySignature(string publicVerificationKey)
        {
            if (string.IsNullOrWhiteSpace(Signature))
                return false;

            var hash = ComputeHash();
            using var hmac = new HMACSHA256(Encoding.UTF8.GetBytes(publicVerificationKey));
            var expectedSigBytes = hmac.ComputeHash(Encoding.UTF8.GetBytes(hash));
            var expectedSig = Convert.ToHexString(expectedSigBytes).ToLowerInvariant();
            return string.Equals(Signature, expectedSig, StringComparison.OrdinalIgnoreCase);
        }
    }

    // ============================================================================
    // Transaction Receipt Entity
    // ============================================================================
    public sealed class TransactionReceipt
    {
        [JsonPropertyName("receiptId")]
        public string ReceiptId { get; set; } = Guid.NewGuid().ToString("N");

        [JsonPropertyName("transactionId")]
        public string TransactionId { get; set; } = string.Empty;

        [JsonPropertyName("blockIndex")]
        public long BlockIndex { get; set; }

        [JsonPropertyName("blockHash")]
        public string BlockHash { get; set; } = string.Empty;

        [JsonPropertyName("status")]
        public TransactionStatus Status { get; set; }

        [JsonPropertyName("gasUsed")]
        public long GasUsed { get; set; }

        [JsonPropertyName("effectiveFee Paid")]
        public decimal EffectiveFeePaid { get; set; }

        [JsonPropertyName("timestamp")]
        public DateTime Timestamp { get; set; } = DateTime.UtcNow;

        [JsonPropertyName("logs")]
        public List<string> Logs { get; set; } = new List<string>();
    }

    // ============================================================================
    // Account State Model
    // ============================================================================
    public sealed class AccountState
    {
        public string Address { get; set; } = string.Empty;
        public ulong Nonce { get; set; }
        public decimal NativeBalance { get; set; }
        public ConcurrentDictionary<string, decimal> TokenBalances { get; } = new ConcurrentDictionary<string, decimal>();
        public DateTime LastUpdated { get; set; } = DateTime.UtcNow;

        public decimal GetBalance(string symbol)
        {
            if (string.Equals(symbol, "MOPUS", StringComparison.OrdinalIgnoreCase))
                return NativeBalance;
            return TokenBalances.TryGetValue(symbol, out var bal) ? bal : 0m;
        }

        public bool TryDebit(string symbol, decimal amount)
        {
            if (amount <= 0) return false;
            if (string.Equals(symbol, "MOPUS", StringComparison.OrdinalIgnoreCase))
            {
                if (NativeBalance < amount) return false;
                NativeBalance -= amount;
                LastUpdated = DateTime.UtcNow;
                return true;
            }
            else
            {
                return TokenBalances.AddOrUpdate(symbol, 0m, (key, oldVal) =>
                {
                    if (oldVal < amount) return oldVal;
                    LastUpdated = DateTime.UtcNow;
                    return oldVal - amount;
                }) >= 0m;
            }
        }

        public void Credit(string symbol, decimal amount)
        {
            if (amount <= 0) return;
            if (string.Equals(symbol, "MOPUS", StringComparison.OrdinalIgnoreCase))
            {
                NativeBalance += amount;
            }
            else
            {
                TokenBalances.AddOrUpdate(symbol, amount, (key, oldVal) => oldVal + amount);
            }
            LastUpdated = DateTime.UtcNow;
        }
    }

    // ============================================================================
    // Cryptographic Merkle Tree Helper
    // ============================================================================
    public static class MerkleTree
    {
        public static string ComputeMerkleRoot(IReadOnlyList<string> hashes)
        {
            if (hashes == null || hashes.Count == 0)
                return Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes("EMPTY_TREE"))).ToLowerInvariant();

            List<string> currentLevel = hashes.ToList();
            while (currentLevel.Count > 1)
            {
                if (currentLevel.Count % 2 != 0)
                {
                    currentLevel.Add(currentLevel[^1]);
                }

                List<string> nextLevel = new List<string>();
                for (int i = 0; i < currentLevel.Count; i += 2)
                {
                    var concatenated = currentLevel[i] + currentLevel[i + 1];
                    var hash = SHA256.HashData(Encoding.UTF8.GetBytes(concatenated));
                    nextLevel.Add(Convert.ToHexString(hash).ToLowerInvariant());
                }
                currentLevel = nextLevel;
            }

            return currentLevel[0];
        }
    }

    // ============================================================================
    // Block Entity
    // ============================================================================
    public sealed class Block
    {
        public long Index { get; set; }
        public string PreviousHash { get; set; } = string.Empty;
        public string MerkleRoot { get; set; } = string.Empty;
        public DateTime Timestamp { get; set; } = DateTime.UtcNow;
        public ulong Nonce { get; set; }
        public string Miner { get; set; } = string.Empty;
        public List<Transaction> Transactions { get; set; } = new List<Transaction>();
        public string Hash { get; set; } = string.Empty;

        public string ComputeBlockHash()
        {
            using var sha256 = SHA256.Create();
            var header = $"{Index}:{PreviousHash}:{MerkleRoot}:{Timestamp:O}:{Nonce}:{Miner}";
            var bytes = sha256.ComputeHash(Encoding.UTF8.GetBytes(header));
            return Convert.ToHexString(bytes).ToLowerInvariant();
        }

        public void FinalizeBlock()
        {
            var txHashes = Transactions.Select(t => t.ComputeHash()).ToList();
            MerkleRoot = MerkleTree.ComputeMerkleRoot(txHashes);
            Hash = ComputeBlockHash();
        }
    }

    // ============================================================================
    // Interfaces
    // ============================================================================
    public interface IAccountStateStore
    {
        AccountState GetOrCreateAccount(string address);
        bool TryGetAccount(string address, out AccountState account);
        void UpdateAccount(AccountState account);
    }

    public interface ITransactionPool
    {
        bool TryEnqueue(Transaction tx);
        List<Transaction> GetTopFeeTransactions(int maxCount);
        bool Remove(string txId);
        int Count { get; }
        bool Contains(string txId);
    }

    public interface ITransactionValidator
    {
        (bool IsValid, string ErrorMessage) Validate(Transaction tx, AccountState senderState);
    }

    // ============================================================================
    // InMemory Account State Store
    // ============================================================================
    public sealed class InMemoryAccountStateStore : IAccountStateStore
    {
        private readonly ConcurrentDictionary<string, AccountState> _accounts = new(StringComparer.OrdinalIgnoreCase);

        public AccountState GetOrCreateAccount(string address)
        {
            return _accounts.GetOrAdd(address, addr => new AccountState
            {
                Address = addr,
                NativeBalance = 1000m, // Mock initial balance for testing/demo
                Nonce = 0
            });
        }

        public bool TryGetAccount(string address, out AccountState account)
        {
            return _accounts.TryGetValue(address, out account!);
        }

        public void UpdateAccount(AccountState account)
        {
            _accounts[account.Address] = account;
        }
    }

    // ============================================================================
    // Priority Transaction Mempool
    // ============================================================================
    public sealed class PriorityMempool : ITransactionPool
    {
        private readonly ConcurrentDictionary<string, Transaction> _mempool = new();
        private readonly object _lock = new();
        private readonly int _maxCapacity;

        public PriorityMempool(int maxCapacity = 10_000)
        {
            _maxCapacity = maxCapacity;
        }

        public int Count => _mempool.Count;

        public bool Contains(string txId) => _mempool.ContainsKey(txId);

        public bool TryEnqueue(Transaction tx)
        {
            if (tx == null || string.IsNullOrWhiteSpace(tx.Id))
                return false;

            lock (_lock)
            {
                if (_mempool.Count >= _maxCapacity)
                {
                    // Evict lowest fee transaction if current transaction pays higher fee
                    var lowest = _mempool.Values.OrderBy(t => t.Fee).FirstOrDefault();
                    if (lowest != null && tx.Fee > lowest.Fee)
                    {
                        _mempool.TryRemove(lowest.Id, out _);
                    }
                    else
                    {
                        return false;
                    }
                }

                tx.Status = TransactionStatus.Queued;
                return _mempool.TryAdd(tx.Id, tx);
            }
        }

        public List<Transaction> GetTopFeeTransactions(int maxCount)
        {
            lock (_lock)
            {
                return _mempool.Values
                    .OrderByDescending(t => t.Fee)
                    .ThenBy(t => t.Timestamp)
                    .Take(maxCount)
                    .ToList();
            }
        }

        public bool Remove(string txId)
        {
            return _mempool.TryRemove(txId, out _);
        }
    }

    // ============================================================================
    // Standard Transaction Validator
    // ============================================================================
    public sealed class TransactionValidator : ITransactionValidator
    {
        public (bool IsValid, string ErrorMessage) Validate(Transaction tx, AccountState senderState)
        {
            if (tx == null)
                return (false, "Transaction object is null.");

            if (!tx.IsValid())
                return (false, "Basic transaction rules validation failed.");

            if (!tx.ValidateNetworkConstraints())
                return (false, "Transaction violated network caps (amount/fee limits).");

            if (senderState == null)
                return (false, "Sender account state not found.");

            if (tx.Nonce != senderState.Nonce + 1)
                return (false, $"Invalid nonce. Expected {senderState.Nonce + 1}, got {tx.Nonce}.");

            decimal totalRequired = tx.CalculateTotalCost();
            decimal senderBalance = senderState.GetBalance(tx.TokenSymbol);

            if (senderBalance < totalRequired)
                return (false, $"Insufficient balance for {tx.TokenSymbol}. Required: {totalRequired}, Available: {senderBalance}.");

            return (true, string.Empty);
        }
    }

    // ============================================================================
    // Main Core Engine: TransactionProcessor
    // ============================================================================
    public sealed class TransactionProcessor
    {
        private readonly IAccountStateStore _stateStore;
        private readonly ITransactionPool _mempool;
        private readonly ITransactionValidator _validator;
        private readonly ILogger<TransactionProcessor>? _logger;

        private long _totalProcessedCount;
        private long _totalFailedCount;
        private decimal _totalVolumeExecuted;

        public TransactionProcessor(
            IAccountStateStore stateStore,
            ITransactionPool mempool,
            ITransactionValidator validator,
            ILogger<TransactionProcessor>? logger = null)
        {
            _stateStore = stateStore ?? throw new ArgumentNullException(nameof(stateStore));
            _mempool = mempool ?? throw new ArgumentNullException(nameof(mempool));
            _validator = validator ?? throw new ArgumentNullException(nameof(validator));
            _logger = logger;
        }

        public long TotalProcessedCount => Interlocked.Read(ref _totalProcessedCount);
        public long TotalFailedCount => Interlocked.Read(ref _totalFailedCount);
        public decimal TotalVolumeExecuted => _totalVolumeExecuted;

        public Task<bool> SubmitTransactionAsync(Transaction tx)
        {
            if (tx == null)
                throw new ArgumentNullException(nameof(tx));

            if (string.IsNullOrWhiteSpace(tx.Id))
                tx.Id = Guid.NewGuid().ToString("N");

            var senderAccount = _stateStore.GetOrCreateAccount(tx.Sender);
            var validation = _validator.Validate(tx, senderAccount);

            if (!validation.IsValid)
            {
                tx.UpdateStatus(TransactionStatus.Rejected, validation.ErrorMessage);
                _logger?.LogWarning("Transaction {TxId} rejected: {Reason}", tx.Id, validation.ErrorMessage);
                Interlocked.Increment(ref _totalFailedCount);
                return Task.FromResult(false);
            }

            bool enqueued = _mempool.TryEnqueue(tx);
            if (enqueued)
            {
                _logger?.LogInformation("Transaction {TxId} enqueued in mempool. Sender: {Sender}, Amount: {Amount}", tx.Id, tx.Sender, tx.Amount);
            }
            else
            {
                tx.UpdateStatus(TransactionStatus.Rejected, "Mempool at full capacity or duplicate transaction ID.");
                Interlocked.Increment(ref _totalFailedCount);
            }

            return Task.FromResult(enqueued);
        }

        public Task<Block> ProcessBlockAsync(long blockIndex, string minerAddress, int maxTxCount = 50)
        {
            var candidateTxs = _mempool.GetTopFeeTransactions(maxTxCount);
            var block = new Block
            {
                Index = blockIndex,
                Miner = minerAddress,
                Timestamp = DateTime.UtcNow,
                PreviousHash = blockIndex > 0 ? "0xPREV_BLOCK_HASH_SIMULATED" : "0x0000000000000000000000000000000000000000000000000000000000000000"
            };

            foreach (var tx in candidateTxs)
            {
                var receipt = ExecuteSingleTransaction(tx, blockIndex);
                if (receipt.Status == TransactionStatus.Confirmed)
                {
                    block.Transactions.Add(tx);
                }
                _mempool.Remove(tx.Id);
            }

            // Distribute mining reward to miner
            var minerAccount = _stateStore.GetOrCreateAccount(minerAddress);
            minerAccount.Credit("MOPUS", 2.5m);

            block.FinalizeBlock();
            _logger?.LogInformation("Block {BlockIndex} produced with {TxCount} transactions. BlockHash: {BlockHash}", block.Index, block.Transactions.Count, block.Hash);

            return Task.FromResult(block);
        }

        private TransactionReceipt ExecuteSingleTransaction(Transaction tx, long blockIndex)
        {
            tx.Status = TransactionStatus.Processing;
            var receipt = new TransactionReceipt
            {
                TransactionId = tx.Id,
                BlockIndex = blockIndex,
                Timestamp = DateTime.UtcNow
            };

            var sender = _stateStore.GetOrCreateAccount(tx.Sender);
            var recipient = _stateStore.GetOrCreateAccount(tx.Recipient);

            decimal totalCost = tx.CalculateTotalCost();

            if (!sender.TryDebit(tx.TokenSymbol, tx.Amount + tx.Fee))
            {
                tx.UpdateStatus(TransactionStatus.Failed, "Insufficient balance during execution context.");
                receipt.Status = TransactionStatus.Failed;
                receipt.Logs.Add("Execution failed: balance debit failure.");
                Interlocked.Increment(ref _totalFailedCount);
                return receipt;
            }

            recipient.Credit(tx.TokenSymbol, tx.Amount);
            sender.Nonce += 1;

            tx.GasUsed = 21000;
            tx.FeePaid = tx.Fee;
            tx.BlockIndex = blockIndex;
            tx.ReceiptId = receipt.ReceiptId;
            tx.UpdateStatus(TransactionStatus.Confirmed);

            receipt.Status = TransactionStatus.Confirmed;
            receipt.GasUsed = tx.GasUsed;
            receipt.EffectiveFeePaid = tx.FeePaid;
            receipt.BlockHash = "0xBLOCK_HASH_PENDING";
            receipt.Logs.Add($"Transferred {tx.Amount} {tx.TokenSymbol} from {tx.Sender} to {tx.Recipient}");

            Interlocked.Increment(ref _totalProcessedCount);
            _totalVolumeExecuted += tx.Amount;

            _logger?.LogDebug("Executed tx {TxId}: {Sender} -> {Recipient} ({Amount} {Symbol})", tx.Id, tx.Sender, tx.Recipient, tx.Amount, tx.TokenSymbol);
            return receipt;
        }
    }
}