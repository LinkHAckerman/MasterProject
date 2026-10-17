using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Collections.Immutable;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Threading;
using System.Threading.Tasks;

namespace MagnumOpus.Backend.Core
{
    #region Data Transfer Objects and Entities

    public enum TransactionStatus
    {
        Pending,
        Confirmed,
        Failed,
        Rejected
    }

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

        public override string ToString()
        {
            return $"{Sender}:{Recipient}:{Amount}:{Fee}:{Nonce}:{TokenSymbol}:{Timestamp:O}:{Payload}";
        }

        public byte[] GetRawPayloadBytes()
        {
            return Encoding.UTF8.GetBytes(ToString());
        }
    }

    public sealed class TransactionReceipt
    {
        [JsonPropertyName("transactionId")]
        public string TransactionId { get; set; } = string.Empty;

        [JsonPropertyName("blockIndex")]
        public long BlockIndex { get; set; }

        [JsonPropertyName("blockHash")]
        public string BlockHash { get; set; } = string.Empty;

        [JsonPropertyName("gasUsed")]
        public decimal GasUsed { get; set; }

        [JsonPropertyName("feePaid")]
        public decimal FeePaid { get; set; }

        [JsonPropertyName("status")]
        public TransactionStatus Status { get; set; }

        [JsonPropertyName("timestamp")]
        public DateTime Timestamp { get; set; }

        [JsonPropertyName("executionMessage")]
        public string ExecutionMessage { get; set; } = "Success";
    }

    public sealed class Block
    {
        [JsonPropertyName("index")]
        public long Index { get; set; }

        [JsonPropertyName("timestamp")]
        public DateTime Timestamp { get; set; }

        [JsonPropertyName("transactions")]
        public List<Transaction> Transactions { get; set; } = new List<Transaction>();

        [JsonPropertyName("previousHash")]
        public string PreviousHash { get; set; } = string.Empty;

        [JsonPropertyName("merkleRoot")]
        public string MerkleRoot { get; set; } = string.Empty;

        [JsonPropertyName("nonce")]
        public ulong Nonce { get; set; }

        [JsonPropertyName("hash")]
        public string Hash { get; set; } = string.Empty;

        [JsonPropertyName("minerAddress")]
        public string MinerAddress { get; set; } = string.Empty;

        [JsonPropertyName("difficulty")]
        public int Difficulty { get; set; }
    }

    public sealed class Wallet
    {
        [JsonPropertyName("address")]
        public string Address { get; set; } = string.Empty;

        [JsonPropertyName("publicKey")]
        public string PublicKey { get; set; } = string.Empty;

        [JsonPropertyName("balance")]
        public decimal Balance { get; set; }

        [JsonPropertyName("tokenBalances")]
        public Dictionary<string, decimal> TokenBalances { get; set; } = new Dictionary<string, decimal>(StringComparer.OrdinalIgnoreCase);

        [JsonPropertyName("nonce")]
        public ulong Nonce { get; set; }

        [JsonPropertyName("createdAt")]
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    }

    public sealed class Token
    {
        [JsonPropertyName("symbol")]
        public string Symbol { get; set; } = string.Empty;

        [JsonPropertyName("name")]
        public string Name { get; set; } = string.Empty;

        [JsonPropertyName("decimals")]
        public int Decimals { get; set; } = 18;

        [JsonPropertyName("totalSupply")]
        public decimal TotalSupply { get; set; }

        [JsonPropertyName("owner")]
        public string Owner { get; set; } = string.Empty;
    }

    #endregion

    public sealed class NodeStats
    {
        public long ChainHeight { get; set; }
        public int PendingTransactions { get; set; }
        public int ConfirmedTransactions { get; set; }
        public int FailedTransactions { get; set; }
        public DateTime LastBlockTimestamp { get; set; }
        public int PeerCount { get; set; }
    }

    public class TransactionProcessor
    {
        private readonly ConcurrentQueue<Transaction> _pendingQueue = new();
        private readonly ConcurrentDictionary<string, Transaction> _inFlight = new();
        private readonly ConcurrentDictionary<string, TransactionReceipt> _receipts = new();
        private readonly TimeSpan _processingInterval = TimeSpan.FromSeconds(1);
        private readonly CancellationTokenSource _cts = new();
        private readonly Task _processingTask;
        private readonly object _blockLock = new();
        private Block _currentBlock;
        private readonly List<Block> _chain = new();
        private readonly int _blockCapacity = 10;
        private readonly int _difficulty = 4; // number of leading zeros required

        public TransactionProcessor()
        {
            // Create genesis block
            _currentBlock = new Block
            {
                Index = 0,
                Timestamp = DateTime.UtcNow,
                PreviousHash = new string('0', 64),
                Nonce = 0,
                Difficulty = _difficulty,
                MinerAddress = "MAGNUM-OPUS-GENESIS"
            };
            _currentBlock.Hash = ComputeHash(_currentBlock);
            _chain.Add(_currentBlock);

            _processingTask = Task.Run(ProcessLoopAsync);
        }

        public void EnqueueTransaction(Transaction tx)
        {
            if (ValidateTransaction(tx))
            {
                _pendingQueue.Enqueue(tx);
            }
            else
            {
                tx.Status = TransactionStatus.Rejected;
                var receipt = new TransactionReceipt
                {
                    TransactionId = tx.Id,
                    BlockIndex = -1,
                    BlockHash = string.Empty,
                    GasUsed = 0,
                    FeePaid = tx.Fee,
                    Status = TransactionStatus.Rejected,
                    Timestamp = DateTime.UtcNow,
                    ExecutionMessage = "Validation failed"
                };
                _receipts[tx.Id] = receipt;
            }
        }

        private bool ValidateTransaction(Transaction tx)
        {
            // Basic sanity checks
            if (string.IsNullOrWhiteSpace(tx.Id) ||
                string.IsNullOrWhiteSpace(tx.Sender) ||
                string.IsNullOrWhiteSpace(tx.Recipient) ||
                tx.Amount <= 0 ||
                tx.Fee < 0)
            {
                return false;
            }

            // Nonce must be greater than zero (placeholder logic)
            if (tx.Nonce == 0)
                return false;

            // Signature placeholder – real implementation would verify ECDSA signatures
            if (string.IsNullOrWhiteSpace(tx.Signature))
                return false;

            return true;
        }

        private async Task ProcessLoopAsync()
        {
            while (!_cts.IsCancellationRequested)
            {
                await ProcessPendingAsync();
                await Task.Delay(_processingInterval, _cts.Token);
            }
        }

        private async Task ProcessPendingAsync()
        {
            while (_pendingQueue.TryDequeue(out var tx))
            {
                _inFlight[tx.Id] = tx;
                // Simulate minimal processing latency
                await Task.Yield();

                lock (_blockLock)
                {
                    _currentBlock.Transactions.Add(tx);
                    tx.Status = TransactionStatus.Confirmed;
                    var receipt = new TransactionReceipt
                    {
                        TransactionId = tx.Id,
                        BlockIndex = _currentBlock.Index,
                        BlockHash = _currentBlock.Hash,
                        GasUsed = 21000,
                        FeePaid = tx.Fee,
                        Status = TransactionStatus.Confirmed,
                        Timestamp = DateTime.UtcNow,
                        ExecutionMessage = "Success"
                    };
                    _receipts[tx.Id] = receipt;

                    if (_currentBlock.Transactions.Count >= _blockCapacity)
                    {
                        MineCurrentBlock();
                    }
                }

                _inFlight.TryRemove(tx.Id, out _);
            }
        }

        private void MineCurrentBlock()
        {
            var targetPrefix = new string('0', _difficulty);
            while (true)
            {
                var hash = ComputeHash(_currentBlock);
                if (hash.StartsWith(targetPrefix))
                {
                    _currentBlock.Hash = hash;
                    break;
                }
                _currentBlock.Nonce++;
            }

            // Append mined block to chain
            _chain.Add(_currentBlock);

            // Start a fresh block
            var newBlock = new Block
            {
                Index = _currentBlock.Index + 1,
                Timestamp = DateTime.UtcNow,
                PreviousHash = _currentBlock.Hash,
                Nonce = 0,
                Difficulty = _difficulty,
                MinerAddress = "MAGNUM-OPUS-MINER"
            };
            newBlock.Hash = ComputeHash(newBlock);
            _currentBlock = newBlock;
        }

        private static string ComputeHash(Block block)
        {
            using var sha = SHA256.Create();
            var raw = $"{block.Index}:{block.Timestamp:O}:{block.PreviousHash}:{block.Nonce}:{block.MerkleRoot}:{block.MinerAddress}:{block.Difficulty}";
            var bytes = Encoding.UTF8.GetBytes(raw);
            var hash = sha.ComputeHash(bytes);
            return BitConverter.ToString(hash).Replace("-", "").ToLowerInvariant();
        }

        public TransactionReceipt? GetReceipt(string transactionId)
        {
            _receipts.TryGetValue(transactionId, out var receipt);
            return receipt;
        }

        public IReadOnlyList<Block> GetChain()
        {
            return _chain.AsReadOnly();
        }

        public NodeStats GetNodeStats()
        {
            return new NodeStats
            {
                ChainHeight = _chain.Count - 1,
                PendingTransactions = _pendingQueue.Count,
                ConfirmedTransactions = _receipts.Values.Count(r => r.Status == TransactionStatus.Confirmed),
                FailedTransactions = _receipts.Values.Count(r => r.Status == TransactionStatus.Failed || r.Status == TransactionStatus.Rejected),
                LastBlockTimestamp = _chain[^1].Timestamp,
                PeerCount = 0 // Placeholder – network layer would populate this
            };
        }

        public void Shutdown()
        {
            _cts.Cancel();
            try
            {
                _processingTask.Wait();
            }
            catch (AggregateException) { }
        }
    }
}
