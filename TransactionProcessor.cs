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
        public int PeerCount { get; set; }
        public decimal AvgBlockTimeSeconds { get; set; }
        public decimal TxPerSecond { get; set; }
        public DateTime LastBlockTimestamp { get; set; }
    }

    /// <summary>
    /// Core transaction processing engine. Handles validation, signature verification,
    /// mem‑pool management and block creation in a thread‑safe manner.
    /// </summary>
    public sealed class TransactionProcessor : IDisposable
    {
        private readonly ConcurrentDictionary<string, Wallet> _wallets = new();
        private readonly ConcurrentDictionary<string, Transaction> _pendingTx = new();
        private readonly ConcurrentQueue<string> _txQueue = new();
        private readonly List<Block> _chain = new();
        private readonly CancellationTokenSource _cts = new();
        private readonly Task _backgroundTask;
        private readonly TimeSpan _blockInterval = TimeSpan.FromSeconds(10);
        private readonly object _blockLock = new();
        private long _nextBlockIndex = 0;
        private string _lastBlockHash = string.Empty;

        public TransactionProcessor()
        {
            // Genesis block
            var genesis = new Block
            {
                Index = 0,
                Timestamp = DateTime.UtcNow,
                PreviousHash = "0",
                Nonce = 0,
                Difficulty = 1,
                Transactions = new List<Transaction>()
            };
            genesis.Hash = CryptoUtils.ComputeHash(genesis);
            _chain.Add(genesis);
            _nextBlockIndex = 1;
            _lastBlockHash = genesis.Hash;

            _backgroundTask = Task.Run(ProcessLoopAsync);
        }

        /// <summary>
        /// Submit a new transaction to the mem‑pool.
        /// </summary>
        public async Task<TransactionReceipt> SubmitTransactionAsync(Transaction tx)
        {
            // Basic validation
            var validation = ValidateTransaction(tx);
            if (!validation.isValid)
            {
                return new TransactionReceipt
                {
                    TransactionId = tx.Id,
                    Status = TransactionStatus.Rejected,
                    ExecutionMessage = validation.errorMessage,
                    Timestamp = DateTime.UtcNow
                };
            }

            // Ensure uniqueness
            if (!_pendingTx.TryAdd(tx.Id, tx))
            {
                return new TransactionReceipt
                {
                    TransactionId = tx.Id,
                    Status = TransactionStatus.Rejected,
                    ExecutionMessage = "Duplicate transaction ID",
                    Timestamp = DateTime.UtcNow
                };
            }

            _txQueue.Enqueue(tx.Id);
            return new TransactionReceipt
            {
                TransactionId = tx.Id,
                Status = TransactionStatus.Pending,
                ExecutionMessage = "Accepted into mem‑pool",
                Timestamp = DateTime.UtcNow
            };
        }

        private (bool isValid, string errorMessage) ValidateTransaction(Transaction tx)
        {
            if (string.IsNullOrWhiteSpace(tx.Id))
                return (false, "Transaction ID missing");
            if (string.IsNullOrWhiteSpace(tx.Sender) || string.IsNullOrWhiteSpace(tx.Recipient))
                return (false, "Sender or recipient missing");
            if (tx.Amount <= 0)
                return (false, "Amount must be positive");
            if (!_wallets.ContainsKey(tx.Sender))
                return (false, "Sender wallet not found");
            if (!_wallets.ContainsKey(tx.Recipient))
                return (false, "Recipient wallet not found");
            if (!_wallets[tx.Sender].TokenBalances.TryGetValue(tx.TokenSymbol, out var senderBal) || senderBal < tx.Amount + tx.Fee)
                return (false, "Insufficient balance");
            if (!CryptoUtils.VerifySignature(tx.GetRawPayloadBytes(), tx.Signature, _wallets[tx.Sender].PublicKey))
                return (false, "Invalid signature");
            return (true, string.Empty);
        }

        private async Task ProcessLoopAsync()
        {
            while (!_cts.IsCancellationRequested)
            {
                var nextBlockTime = DateTime.UtcNow + _blockInterval;
                await CreateBlockIfPendingAsync();
                var delay = nextBlockTime - DateTime.UtcNow;
                if (delay > TimeSpan.Zero)
                    await Task.Delay(delay, _cts.Token);
            }
        }

        private async Task CreateBlockIfPendingAsync()
        {
            if (_txQueue.IsEmpty)
                return;

            var blockTxs = new List<Transaction>();
            while (blockTxs.Count < 100 && _txQueue.TryDequeue(out var txId))
            {
                if (_pendingTx.TryRemove(txId, out var tx))
                {
                    // Apply state changes atomically
                    ApplyTransaction(tx);
                    blockTxs.Add(tx);
                }
            }

            if (blockTxs.Count == 0)
                return;

            var newBlock = new Block
            {
                Index = Interlocked.Read(ref _nextBlockIndex),
                Timestamp = DateTime.UtcNow,
                PreviousHash = _lastBlockHash,
                Transactions = blockTxs,
                Difficulty = 2, // simplified static difficulty
                Nonce = 0,
                MinerAddress = "MAGNUM-OPUS-MINER"
            };

            // Simple proof‑of‑work
            while (!newBlock.Hash.StartsWith(new string('0', newBlock.Difficulty)))
            {
                newBlock.Nonce++;
                newBlock.Hash = CryptoUtils.ComputeHash(newBlock);
            }

            lock (_blockLock)
            {
                _chain.Add(newBlock);
                Interlocked.Increment(ref _nextBlockIndex);
                _lastBlockHash = newBlock.Hash;
            }
        }

        private void ApplyTransaction(Transaction tx)
        {
            var senderWallet = _wallets[tx.Sender];
            var recipientWallet = _wallets[tx.Recipient];

            // Deduct amount + fee from sender
            senderWallet.TokenBalances[tx.TokenSymbol] -= (tx.Amount + tx.Fee);
            senderWallet.Nonce = Math.Max(senderWallet.Nonce, tx.Nonce + 1);

            // Credit amount to recipient
            if (!recipientWallet.TokenBalances.ContainsKey(tx.TokenSymbol))
                recipientWallet.TokenBalances[tx.TokenSymbol] = 0;
            recipientWallet.TokenBalances[tx.TokenSymbol] += tx.Amount;
        }

        /// <summary>
        /// Register a wallet. In a real system this would be persisted.
        /// </summary>
        public void RegisterWallet(Wallet wallet)
        {
            _wallets[wallet.Address] = wallet;
        }

        /// <summary>
        /// Retrieve the current blockchain as an immutable list.
        /// </summary>
        public IReadOnlyList<Block> GetChain()
        {
            lock (_blockLock)
            {
                return _chain.ToImmutableArray();
            }
        }

        public void Dispose()
        {
            _cts.Cancel();
            try
            {
                _backgroundTask.Wait();
            }
            catch (AggregateException) { }
            _cts.Dispose();
        }
    }

    /// <summary>
    /// Cryptographic helper utilities for hashing and ECDSA signature verification.
    /// </summary>
    public static class CryptoUtils
    {
        public static string ComputeHash(Block block)
        {
            var sb = new StringBuilder();
            sb.Append(block.Index);
            sb.Append(block.Timestamp.ToUniversalTime().ToString("o"));
            sb.Append(block.PreviousHash);
            sb.Append(block.Nonce);
            sb.Append(block.Difficulty);
            foreach (var tx in block.Transactions)
            {
                sb.Append(tx.Id);
            }
            using var sha = SHA256.Create();
            var bytes = sha.ComputeHash(Encoding.UTF8.GetBytes(sb.ToString()));
            return BitConverter.ToString(bytes).Replace("-", string.Empty).ToLowerInvariant();
        }

        public static string ComputeHash(Transaction tx)
        {
            using var sha = SHA256.Create();
            var bytes = sha.ComputeHash(tx.GetRawPayloadBytes());
            return BitConverter.ToString(bytes).Replace("-", string.Empty).ToLowerInvariant();
        }

        public static bool VerifySignature(byte[] payload, string signatureBase64, string publicKeyPem)
        {
            try
            {
                var signature = Convert.FromBase64String(signatureBase64);
                using var ecdsa = ECDsa.Create();
                ecdsa.ImportFromPem(publicKeyPem);
                return ecdsa.VerifyData(payload, signature, HashAlgorithmName.SHA256);
            }
            catch
            {
                return false;
            }
        }
    }
}
