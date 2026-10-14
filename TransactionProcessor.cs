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

    public sealed class NodeStats
    {
        public long ChainHeight { get; set; }
        public int PendingTransactions { get; set; }
        public long ProcessedTransactions { get; set; }
        public DateTime LastBlockTimestamp { get; set; }
    }

    #endregion

    /// <summary>
    /// Core transaction processor that validates, batches, mines and records transactions.
    /// It runs a background loop that creates blocks of a configurable size and difficulty.
    /// </summary>
    public sealed class TransactionProcessor : IDisposable
    {
        private readonly ConcurrentQueue<Transaction> _pendingQueue = new();
        private readonly List<Block> _chain = new();
        private readonly ConcurrentDictionary<string, TransactionReceipt> _receipts = new();
        private readonly object _chainLock = new();
        private readonly CancellationTokenSource _cts = new();
        private readonly Task _processingTask;

        private readonly int _blockCapacity;
        private readonly int _miningDifficulty;
        private readonly string _minerAddress = "MAGNUM-OPUS-MINER";

        public TransactionProcessor(int blockCapacity = 5, int miningDifficulty = 3)
        {
            _blockCapacity = blockCapacity;
            _miningDifficulty = miningDifficulty;
            InitializeGenesisBlock();
            _processingTask = Task.Run(ProcessLoopAsync);
        }

        private void InitializeGenesisBlock()
        {
            var genesis = new Block
            {
                Index = 0,
                Timestamp = DateTime.UtcNow,
                PreviousHash = new string('0', 64),
                Transactions = new List<Transaction>(),
                Nonce = 0,
                Difficulty = _miningDifficulty,
                MinerAddress = _minerAddress,
                MerkleRoot = new string('0', 64)
            };
            genesis.Hash = ComputeHash(genesis);
            lock (_chainLock) { _chain.Add(genesis); }
        }

        /// <summary>
        /// Enqueue a new transaction for processing. Throws if validation fails.
        /// </summary>
        public void EnqueueTransaction(Transaction tx)
        {
            if (tx == null) throw new ArgumentNullException(nameof(tx));
            if (!ValidateTransaction(tx))
                throw new ArgumentException("Transaction validation failed.");

            // Assign a unique Id if missing
            if (string.IsNullOrWhiteSpace(tx.Id))
                tx.Id = Guid.NewGuid().ToString();

            _pendingQueue.Enqueue(tx);
        }

        private bool ValidateTransaction(Transaction tx)
        {
            // Basic sanity checks – real implementation would verify signatures, nonce, balances, etc.
            if (string.IsNullOrWhiteSpace(tx.Sender) || string.IsNullOrWhiteSpace(tx.Recipient))
                return false;
            if (tx.Amount <= 0) return false;
            if (string.IsNullOrWhiteSpace(tx.Signature)) return false;
            // Placeholder for cryptographic signature verification
            return true;
        }

        private async Task ProcessLoopAsync()
        {
            var batch = new List<Transaction>();
            while (!_cts.IsCancellationRequested)
            {
                while (batch.Count < _blockCapacity && _pendingQueue.TryDequeue(out var tx))
                {
                    tx.Status = TransactionStatus.Pending;
                    batch.Add(tx);
                }

                if (batch.Count > 0)
                {
                    var block = CreateBlock(batch);
                    await MineBlockAsync(block);
                    lock (_chainLock) { _chain.Add(block); }
                    foreach (var tx in batch)
                    {
                        tx.Status = TransactionStatus.Confirmed;
                        var receipt = GenerateReceipt(tx, block);
                        _receipts[tx.Id] = receipt;
                    }
                    batch.Clear();
                }
                await Task.Delay(500, _cts.Token).ConfigureAwait(false);
            }
        }

        private Block CreateBlock(IReadOnlyList<Transaction> transactions)
        {
            Block previous;
            lock (_chainLock) { previous = _chain[^1]; }

            var block = new Block
            {
                Index = previous.Index + 1,
                Timestamp = DateTime.UtcNow,
                PreviousHash = previous.Hash,
                Transactions = new List<Transaction>(transactions),
                Nonce = 0,
                Difficulty = _miningDifficulty,
                MinerAddress = _minerAddress,
                MerkleRoot = ComputeMerkleRoot(transactions)
            };
            return block;
        }

        private async Task MineBlockAsync(Block block)
        {
            var target = new string('0', block.Difficulty);
            while (true)
            {
                block.Nonce++;
                block.Hash = ComputeHash(block);
                if (block.Hash.StartsWith(target)) break;
                // Yield to keep the thread responsive
                await Task.Yield();
            }
        }

        private string ComputeHash(Block block)
        {
            using var sha = SHA256.Create();
            var raw = $"{block.Index}{block.Timestamp:O}{block.PreviousHash}{block.MerkleRoot}{block.Nonce}{block.MinerAddress}{block.Difficulty}";
            var bytes = sha.ComputeHash(Encoding.UTF8.GetBytes(raw));
            return Convert.ToHexString(bytes).ToLowerInvariant();
        }

        private string ComputeMerkleRoot(IReadOnlyList<Transaction> transactions)
        {
            if (transactions == null || transactions.Count == 0)
                return new string('0', 64);

            List<string> hashes = transactions.Select(t => ComputeTxHash(t)).ToList();
            while (hashes.Count > 1)
            {
                var next = new List<string>();
                for (int i = 0; i < hashes.Count; i += 2)
                {
                    var left = hashes[i];
                    var right = (i + 1 < hashes.Count) ? hashes[i + 1] : left;
                    next.Add(CombineHashes(left, right));
                }
                hashes = next;
            }
            return hashes[0];
        }

        private string ComputeTxHash(Transaction tx)
        {
            using var sha = SHA256.Create();
            var bytes = sha.ComputeHash(tx.GetRawPayloadBytes());
            return Convert.ToHexString(bytes).ToLowerInvariant();
        }

        private string CombineHashes(string left, string right)
        {
            using var sha = SHA256.Create();
            var combined = Encoding.UTF8.GetBytes(left + right);
            var bytes = sha.ComputeHash(combined);
            return Convert.ToHexString(bytes).ToLowerInvariant();
        }

        private TransactionReceipt GenerateReceipt(Transaction tx, Block block)
        {
            return new TransactionReceipt
            {
                TransactionId = tx.Id,
                BlockIndex = block.Index,
                BlockHash = block.Hash,
                GasUsed = 0, // placeholder – real gas calculation would be here
                FeePaid = tx.Fee,
                Status = tx.Status,
                Timestamp = DateTime.UtcNow,
                ExecutionMessage = "Transaction confirmed and included in block."
            };
        }

        /// <summary>
        /// Retrieve a receipt for a given transaction id. Returns null if not found.
        /// </summary>
        public TransactionReceipt? GetReceipt(string transactionId)
        {
            if (string.IsNullOrWhiteSpace(transactionId)) return null;
            _receipts.TryGetValue(transactionId, out var receipt);
            return receipt;
        }

        /// <summary>
        /// Returns a thread‑safe snapshot of the current blockchain.
        /// </summary>
        public IReadOnlyList<Block> GetChain()
        {
            lock (_chainLock) { return _chain.AsReadOnly(); }
        }

        /// <summary>
        /// Gracefully stops the background processing loop.
        /// </summary>
        public void Shutdown()
        {
            _cts.Cancel();
            try { _processingTask.Wait(); } catch { /* ignored */ }
        }

        public void Dispose()
        {
            Shutdown();
            _cts.Dispose();
        }
    }
}
