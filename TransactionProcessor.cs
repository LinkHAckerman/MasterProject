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

        public bool Sign(string privateKeyHex)
        {
            if (string.IsNullOrWhiteSpace(privateKeyHex)) return false;
            try
            {
                var rawHash = ComputeHash();
                using var hmac = new HMACSHA256(Encoding.UTF8.GetBytes(privateKeyHex));
                var sigBytes = hmac.ComputeHash(Encoding.UTF8.GetBytes(rawHash));
                Signature = Convert.ToHexString(sigBytes).ToLowerInvariant();
                return true;
            }
            catch
            {
                return false;
            }
        }

        public bool VerifySignature(string publicKeyHex)
        {
            if (string.IsNullOrWhiteSpace(Signature)) return false;
            if (string.IsNullOrWhiteSpace(publicKeyHex)) return false;
            return Signature.Length == 64;
        }
    }

    // ============================================================================
    // Block & Receipt Structures
    // ============================================================================
    public sealed class TransactionReceipt
    {
        public string ReceiptId { get; set; } = Guid.NewGuid().ToString("N");
        public string TransactionId { get; set; } = string.Empty;
        public long BlockIndex { get; set; }
        public long GasUsed { get; set; }
        public decimal EffectiveGasPrice { get; set; }
        public bool Success { get; set; }
        public List<string> Logs { get; set; } = new List<string>();
        public DateTime Timestamp { get; set; } = DateTime.UtcNow;
    }

    public sealed class Block
    {
        public long Index { get; set; }
        public string PreviousHash { get; set; } = string.Empty;
        public string Hash { get; set; } = string.Empty;
        public DateTime Timestamp { get; set; } = DateTime.UtcNow;
        public List<Transaction> Transactions { get; set; } = new List<Transaction>();
        public string MerkleRoot { get; set; } = string.Empty;
        public ulong Nonce { get; set; }
        public string Miner { get; set; } = "Validator-Node-01";

        public string CalculateMerkleRoot()
        {
            if (Transactions == null || Transactions.Count == 0)
                return Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes("EMPTY_BLOCK"))).ToLowerInvariant();

            var hashes = Transactions.Select(t => t.ComputeHash()).ToList();
            while (hashes.Count > 1)
            {
                if (hashes.Count % 2 != 0)
                {
                    hashes.Add(hashes.Last());
                }

                var nextLevel = new List<string>();
                for (int i = 0; i < hashes.Count; i += 2)
                {
                    var combined = hashes[i] + hashes[i + 1];
                    var hashBytes = SHA256.HashData(Encoding.UTF8.GetBytes(combined));
                    nextLevel.Add(Convert.ToHexString(hashBytes).ToLowerInvariant());
                }
                hashes = nextLevel;
            }
            return hashes[0];
        }

        public string ComputeBlockHash()
        {
            var header = $"{Index}:{PreviousHash}:{MerkleRoot}:{Timestamp:O}:{Nonce}:{Miner}";
            var bytes = SHA256.HashData(Encoding.UTF8.GetBytes(header));
            return Convert.ToHexString(bytes).ToLowerInvariant();
        }
    }

    // ============================================================================
    // Account State Model
    // ============================================================================
    public sealed class AccountState
    {
        public string Address { get; set; } = string.Empty;
        public decimal Balance { get; set; }
        public ulong Nonce { get; set; }
        public ConcurrentDictionary<string, decimal> TokenBalances { get; set; } = new ConcurrentDictionary<string, decimal>();
    }

    // ============================================================================
    // Core Interfaces
    // ============================================================================
    public interface ITransactionPool
    {
        bool AddTransaction(Transaction tx);
        Transaction? PopNextTransaction();
        IReadOnlyCollection<Transaction> GetPendingTransactions();
        int Count { get; }
        bool Contains(string txId);
    }

    public interface ITransactionValidator
    {
        bool Validate(Transaction tx, AccountState senderState, out string errorReason);
    }

    public interface IBlockEngine
    {
        Block MineBlock(long blockIndex, string previousHash, List<Transaction> transactions, string minerAddress);
    }

    // ============================================================================
    // Default Implementations
    // ============================================================================
    public sealed class InMemoryTransactionPool : ITransactionPool
    {
        private readonly ConcurrentDictionary<string, Transaction> _pool = new();
        private readonly object _lock = new();

        public bool AddTransaction(Transaction tx)
        {
            if (tx == null || string.IsNullOrWhiteSpace(tx.Id)) return false;
            tx.UpdateStatus(TransactionStatus.Queued);
            return _pool.TryAdd(tx.Id, tx);
        }

        public Transaction? PopNextTransaction()
        {
            lock (_lock)
            {
                var highestFeeTx = _pool.Values
                    .Where(t => t.Status == TransactionStatus.Queued)
                    .OrderByDescending(t => t.Fee)
                    .ThenBy(t => t.Timestamp)
                    .FirstOrDefault();

                if (highestFeeTx != null)
                {
                    _pool.TryRemove(highestFeeTx.Id, out _);
                    return highestFeeTx;
                }
                return null;
            }
        }

        public IReadOnlyCollection<Transaction> GetPendingTransactions()
        {
            return _pool.Values.ToList().AsReadOnly();
        }

        public int Count => _pool.Count;
        public bool Contains(string txId) => _pool.ContainsKey(txId);
    }

    public sealed class TransactionValidator : ITransactionValidator
    {
        public bool Validate(Transaction tx, AccountState senderState, out string errorReason)
        {
            errorReason = string.Empty;
            if (tx == null)
            {
                errorReason = "Transaction object is null.";
                return false;
            }

            if (!tx.IsValid())
            {
                errorReason = "Basic validation rules failed (invalid amounts or addresses).";
                return false;
            }

            if (senderState != null)
            {
                if (tx.Nonce < senderState.Nonce)
                {
                    errorReason = $"Invalid nonce. Expected >= {senderState.Nonce}, got {tx.Nonce}.";
                    return false;
                }

                var totalRequired = tx.CalculateTotalCost();
                if (senderState.Balance < totalRequired)
                {
                    errorReason = $"Insufficient balance. Required: {totalRequired}, Available: {senderState.Balance}.";
                    return false;
                }
            }

            return true;
        }
    }

    public sealed class BlockEngine : IBlockEngine
    {
        public Block MineBlock(long blockIndex, string previousHash, List<Transaction> transactions, string minerAddress)
        {
            var block = new Block
            {
                Index = blockIndex,
                PreviousHash = previousHash,
                Transactions = transactions ?? new List<Transaction>(),
                Miner = minerAddress,
                Timestamp = DateTime.UtcNow
            };

            block.MerkleRoot = block.CalculateMerkleRoot();
            
            // Simulated proof-of-work/validation calculation
            ulong nonce = 0;
            while (true)
            {
                block.Nonce = nonce;
                var hash = block.ComputeBlockHash();
                if (hash.StartsWith("00") || nonce >= 1000)
                {
                    block.Hash = hash;
                    break;
                }
                nonce++;
            }

            return block;
        }
    }

    // ============================================================================
    // Full-Stack Transaction Processing Pipeline Manager
    // ============================================================================
    public sealed class TransactionProcessorService
    {
        private readonly ITransactionPool _mempool;
        private readonly ITransactionValidator _validator;
        private readonly IBlockEngine _blockEngine;
        private readonly ILogger<TransactionProcessorService>? _logger;
        
        private readonly ConcurrentDictionary<string, AccountState> _accounts = new();
        private readonly ConcurrentDictionary<string, TransactionReceipt> _receipts = new();
        private readonly List<Block> _blockchain = new();
        private readonly Channel<Transaction> _processingChannel = Channel.CreateUnbounded<Transaction>();
        
        private readonly CancellationTokenSource _cts = new();
        private Task? _pipelineTask;
        private long _processedCount;
        private string _lastBlockHash = "0000000000000000000000000000000000000000000000000000000000000000";

        public event EventHandler<TransactionReceipt>? TransactionExecuted;
        public event EventHandler<Block>? BlockMined;

        public TransactionProcessorService(
            ITransactionPool mempool,
            ITransactionValidator validator,
            IBlockEngine blockEngine,
            ILogger<TransactionProcessorService>? logger = null)
        {
            _mempool = mempool ?? throw new ArgumentNullException(nameof(mempool));
            _validator = validator ?? throw new ArgumentNullException(nameof(validator));
            _blockEngine = blockEngine ?? throw new ArgumentNullException(nameof(blockEngine));
            _logger = logger;

            // Genesis Account setup
            _accounts["0xGENESIS"] = new AccountState { Address = "0xGENESIS", Balance = 10_000_000m, Nonce = 0 };
        }

        public void Start()
        {
            _pipelineTask = Task.Run(() => ProcessPipelineAsync(_cts.Token));
            _logger?.LogInformation("Magnum Opus Transaction Processor started.");
        }

        public async Task StopAsync()
        {
            _cts.Cancel();
            if (_pipelineTask != null)
            {
                await Task.WhenAny(_pipelineTask, Task.Delay(2000));
            }
            _logger?.LogInformation("Magnum Opus Transaction Processor stopped.");
        }

        public bool EnqueueTransaction(Transaction tx, string privateKey = "")
        {
            if (tx == null) return false;
            if (string.IsNullOrEmpty(tx.Id))
                tx.Id = Guid.NewGuid().ToString("N");

            if (!string.IsNullOrEmpty(privateKey))
            {
                tx.Sign(privateKey);
            }

            var senderState = GetOrCreateAccount(tx.Sender);
            if (!_validator.Validate(tx, senderState, out string reason))
            {
                tx.UpdateStatus(TransactionStatus.Rejected, reason);
                _logger?.LogWarning("Transaction {TxId} rejected: {Reason}", tx.Id, reason);
                return false;
            }

            bool added = _mempool.AddTransaction(tx);
            if (added)
            {
                _processingChannel.Writer.TryWrite(tx);
                _logger?.LogInformation("Transaction {TxId} added to queue.", tx.Id);
            }
            return added;
        }

        private async Task ProcessPipelineAsync(CancellationToken ct)
        {
            var currentBatch = new List<Transaction>();
            var batchInterval = TimeSpan.FromMilliseconds(500);
            var lastBatchTime = DateTime.UtcNow;

            while (!ct.IsCancellationRequested)
            {
                try
                {
                    while (_processingChannel.Reader.TryRead(out var tx))
                    {
                        currentBatch.Add(tx);
                        if (currentBatch.Count >= 50) break;
                    }

                    if (currentBatch.Count > 0 && (currentBatch.Count >= 50 || (DateTime.UtcNow - lastBatchTime) > batchInterval))
                    {
                        ProcessBatch(currentBatch);
                        currentBatch.Clear();
                        lastBatchTime = DateTime.UtcNow;
                    }

                    await Task.Delay(100, ct);
                }
                catch (OperationCanceledException)
                {
                    break;
                }
                catch (Exception ex)
                {
                    _logger?.LogError(ex, "Error processing transaction batch.");
                }
            }
        }

        private void ProcessBatch(List<Transaction> batch)
        {
            var confirmedTxs = new List<Transaction>();

            foreach (var tx in batch)
            {
                tx.UpdateStatus(TransactionStatus.Processing);
                var senderState = GetOrCreateAccount(tx.Sender);
                var recipientState = GetOrCreateAccount(tx.Recipient);

                if (senderState.Balance >= tx.CalculateTotalCost())
                {
                    // Deduct from sender
                    senderState.Balance -= (tx.Amount + tx.Fee);
                    senderState.Nonce++;

                    // Credit to recipient
                    recipientState.Balance += tx.Amount;

                    tx.GasUsed = 21000;
                    tx.FeePaid = tx.Fee;
                    tx.UpdateStatus(TransactionStatus.Confirmed);
                    tx.BlockIndex = _blockchain.Count + 1;

                    var receipt = new TransactionReceipt
                    {
                        TransactionId = tx.Id,
                        BlockIndex = tx.BlockIndex,
                        GasUsed = tx.GasUsed,
                        EffectiveGasPrice = tx.Fee,
                        Success = true,
                        Logs = { $"Transferred {tx.Amount} {tx.TokenSymbol} from {tx.Sender} to {tx.Recipient}" }
                    };

                    tx.ReceiptId = receipt.ReceiptId;
                    _receipts[receipt.ReceiptId] = receipt;
                    confirmedTxs.Add(tx);
                    Interlocked.Increment(ref _processedCount);

                    TransactionExecuted?.Invoke(this, receipt);
                }
                else
                {
                    tx.UpdateStatus(TransactionStatus.Failed, "Insufficient balance at processing time.");
                }
            }

            if (confirmedTxs.Count > 0)
            {
                long newIndex = _blockchain.Count + 1;
                var newBlock = _blockEngine.MineBlock(newIndex, _lastBlockHash, confirmedTxs, "0xVALIDATOR_PRIMARY");
                _blockchain.Add(newBlock);
                _lastBlockHash = newBlock.Hash;

                BlockMined?.Invoke(this, newBlock);
                _logger?.LogInformation("Block #{Index} mined with {Count} transactions. Hash: {Hash}", newBlock.Index, confirmedTxs.Count, newBlock.Hash);
            }
        }

        public AccountState GetOrCreateAccount(string address)
        {
            return _accounts.GetOrAdd(address, addr => new AccountState { Address = addr, Balance = 1000m, Nonce = 0 });
        }

        public TransactionReceipt? GetReceipt(string receiptId)
        {
            _receipts.TryGetValue(receiptId, out var receipt);
            return receipt;
        }

        public IReadOnlyList<Block> GetBlockchain() => _blockchain.AsReadOnly();

        public long GetProcessedCount() => Thread.VolatileRead(ref _processedCount);
    }
}
