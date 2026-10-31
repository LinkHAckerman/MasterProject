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

        public string ComputeHash()
        {
            using var sha256 = SHA256.Create();
            var bytes = GetRawPayloadBytes();
            var hash = sha256.ComputeHash(bytes);
            return Convert.ToHexString(hash).ToLowerInvariant();
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
    }

    #endregion

    #region Crypto Utilities

    internal static class CryptoUtils
    {
        /// <summary>
        /// Placeholder for ECDSA signature verification. In a production system this would
        /// verify the transaction's signature against the sender's public key.
        /// </summary>
        public static bool VerifySignature(Transaction tx)
        {
            // TODO: integrate real cryptographic verification (e.g., Secp256k1).
            // For now we assume all signatures are valid if the field is non‑empty.
            return !string.IsNullOrWhiteSpace(tx.Signature);
        }
    }

    #endregion

    #region Transaction Pool

    /// <summary>
    /// Thread‑safe in‑memory pool of pending transactions.
    /// </summary>
    internal sealed class TransactionPool
    {
        private readonly ConcurrentDictionary<string, Transaction> _pending = new();

        public bool TryAdd(Transaction tx)
        {
            return _pending.TryAdd(tx.Id, tx);
        }

        public bool TryRemove(string txId, out Transaction? tx)
        {
            return _pending.TryRemove(txId, out tx);
        }

        public IReadOnlyCollection<Transaction> Snapshot()
        {
            return _pending.Values.ToList().AsReadOnly();
        }

        public int Count => _pending.Count;
    }

    #endregion

    #region Block Builder & Miner

    internal sealed class BlockBuilder
    {
        private readonly Block _block;
        private readonly int _difficulty;
        private readonly string _minerAddress;

        public BlockBuilder(long index, string previousHash, IEnumerable<Transaction> transactions, string minerAddress, int difficulty)
        {
            _block = new Block
            {
                Index = index,
                Timestamp = DateTime.UtcNow,
                PreviousHash = previousHash,
                Transactions = transactions.ToList(),
                MinerAddress = minerAddress,
                Difficulty = difficulty
            };
            _difficulty = difficulty;
            _minerAddress = minerAddress;
        }

        private static string ComputeBlockHeaderHash(Block block)
        {
            using var sha256 = SHA256.Create();
            var header = $"{block.Index}{block.Timestamp:O}{block.PreviousHash}{block.MerkleRoot}{block.Nonce}{block.MinerAddress}{block.Difficulty}";
            var hash = sha256.ComputeHash(Encoding.UTF8.GetBytes(header));
            return Convert.ToHexString(hash).ToLowerInvariant();
        }

        private static string ComputeMerkleRoot(IEnumerable<Transaction> transactions)
        {
            // Simple binary Merkle implementation – not optimized for large sets.
            var hashes = transactions.Select(t => t.ComputeHash()).ToList();
            if (!hashes.Any())
                return string.Empty;

            while (hashes.Count > 1)
            {
                var nextLevel = new List<string>();
                for (int i = 0; i < hashes.Count; i += 2)
                {
                    var left = hashes[i];
                    var right = i + 1 < hashes.Count ? hashes[i + 1] : left; // duplicate if odd
                    using var sha256 = SHA256.Create();
                    var combined = Encoding.UTF8.GetBytes(left + right);
                    var combinedHash = sha256.ComputeHash(combined);
                    nextLevel.Add(Convert.ToHexString(combinedHash).ToLowerInvariant());
                }
                hashes = nextLevel;
            }
            return hashes[0];
        }

        private static bool HasValidProof(string hash, int difficulty)
        {
            var prefix = new string('0', difficulty);
            return hash.StartsWith(prefix, StringComparison.Ordinal);
        }

        public async Task<Block> MineAsync(CancellationToken ct)
        {
            _block.MerkleRoot = ComputeMerkleRoot(_block.Transactions);
            _block.Nonce = 0;
            string hash;
            do
            {
                ct.ThrowIfCancellationRequested();
                _block.Nonce++;
                hash = ComputeBlockHeaderHash(_block);
                // Simple throttling to avoid tight CPU loop in demo environments.
                await Task.Yield();
            } while (!HasValidProof(hash, _difficulty));

            _block.Hash = hash;
            return _block;
        }
    }

    #endregion

    #region Transaction Processor Service

    /// <summary>
    /// Core service responsible for receiving, validating, and committing transactions to the blockchain.
    /// </summary>
    public sealed class TransactionProcessor : IDisposable
    {
        private readonly TransactionPool _pool = new();
        private readonly List<Block> _chain = new();
        private readonly SemaphoreSlim _chainLock = new(1, 1);
        private readonly CancellationTokenSource _cts = new();
        private readonly Task _backgroundTask;
        private readonly int _blockSize;
        private readonly int _difficulty;
        private readonly string _minerAddress;

        public TransactionProcessor(int blockSize = 10, int difficulty = 3, string? minerAddress = null)
        {
            _blockSize = blockSize;
            _difficulty = difficulty;
            _minerAddress = minerAddress ?? GenerateMinerAddress();
            // Genesis block
            var genesis = new Block
            {
                Index = 0,
                Timestamp = DateTime.UtcNow,
                PreviousHash = new string('0', 64),
                Transactions = new List<Transaction>(),
                MerkleRoot = string.Empty,
                Nonce = 0,
                Difficulty = difficulty,
                MinerAddress = _minerAddress,
                Hash = ComputeGenesisHash()
            };
            _chain.Add(genesis);
            _backgroundTask = Task.Run(ProcessLoopAsync);
        }

        private static string ComputeGenesisHash()
        {
            using var sha256 = SHA256.Create();
            var data = Encoding.UTF8.GetBytes("GENESIS");
            var hash = sha256.ComputeHash(data);
            return Convert.ToHexString(hash).ToLowerInvariant();
        }

        private static string GenerateMinerAddress()
        {
            // Very naive address generation – replace with proper key‑pair logic.
            var guid = Guid.NewGuid().ToString("N");
            return "0x" + guid.Substring(0, 40);
        }

        /// <summary>
        /// Submit a new transaction to the pool. Returns true if accepted.
        /// </summary>
        public async Task<bool> SubmitTransactionAsync(Transaction tx)
        {
            if (tx == null) throw new ArgumentNullException(nameof(tx));
            // Basic validation before entering the pool.
            if (!ValidateTransaction(tx))
                return false;

            // Ensure uniqueness of transaction ID.
            var added = _pool.TryAdd(tx);
            if (added)
                tx.Status = TransactionStatus.Pending;
            return added;
        }

        private bool ValidateTransaction(Transaction tx)
        {
            // Basic sanity checks.
            if (string.IsNullOrWhiteSpace(tx.Id))
                return false;
            if (string.IsNullOrWhiteSpace(tx.Sender) || string.IsNullOrWhiteSpace(tx.Recipient))
                return false;
            if (tx.Amount <= 0)
                return false;
            if (!CryptoUtils.VerifySignature(tx))
                return false;
            // Additional checks (nonce ordering, balance) would be performed against a state DB.
            return true;
        }

        private async Task ProcessLoopAsync()
        {
            while (!_cts.IsCancellationRequested)
            {
                try
                {
                    if (_pool.Count >= _blockSize)
                    {
                        var snapshot = _pool.Snapshot().Take(_blockSize).ToList();
                        foreach (var tx in snapshot)
                            _pool.TryRemove(tx.Id, out _);

                        var previousHash = _chain.Last().Hash;
                        var builder = new BlockBuilder(_chain.Count, previousHash, snapshot, _minerAddress, _difficulty);
                        var newBlock = await builder.MineAsync(_cts.Token);

                        await _chainLock.WaitAsync(_cts.Token);
                        try
                        {
                            _chain.Add(newBlock);
                            // Mark transactions as confirmed.
                            foreach (var tx in newBlock.Transactions)
                                tx.Status = TransactionStatus.Confirmed;
                        }
                        finally
                        {
                            _chainLock.Release();
                        }
                    }
                    else
                    {
                        // No enough txs – wait a short interval.
                        await Task.Delay(500, _cts.Token);
                    }
                }
                catch (OperationCanceledException)
                {
                    // Graceful shutdown.
                    break;
                }
                catch (Exception ex)
                {
                    // In a real system we would log this.
                    Console.Error.WriteLine($"[TransactionProcessor] Error: {ex.Message}");
                    await Task.Delay(1000, _cts.Token);
                }
            }
        }

        /// <summary>
        /// Retrieve the current blockchain as an immutable list.
        /// </summary>
        public IReadOnlyList<Block> GetChain()
        {
            return _chain.ToImmutableArray();
        }

        /// <summary>
        /// Gracefully stop the background processing loop.
        /// </summary>
        public void Dispose()
        {
            _cts.Cancel();
            try
            {
                _backgroundTask.Wait();
            }
            catch (AggregateException) { }
            _cts.Dispose();
            _chainLock.Dispose();
        }
    }

    #endregion
}
