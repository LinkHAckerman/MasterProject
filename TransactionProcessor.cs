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
        public int ActiveNodes { get; set; }
        public decimal TotalSupply { get; set; }
        public decimal CirculatingSupply { get; set; }
        public decimal MarketCap { get; set; }
        public decimal Price { get; set; }
        public decimal Volume24h { get; set; }
        public decimal Change24h { get; set; }
    }

    public interface ITransactionProcessor
    {
        Task<TransactionReceipt> ProcessTransactionAsync(Transaction transaction, CancellationToken cancellationToken = default);
        Task<Block> MineBlockAsync(CancellationToken cancellationToken = default);
        Task<Wallet> GetWalletAsync(string address, CancellationToken cancellationToken = default);
        Task<Token> GetTokenAsync(string symbol, CancellationToken cancellationToken = default);
        Task<NodeStats> GetNodeStatsAsync(CancellationToken cancellationToken = default);
    }

    public sealed class TransactionProcessor : ITransactionProcessor
    {
        private readonly ConcurrentDictionary<string, Wallet> _wallets = new ConcurrentDictionary<string, Wallet>(StringComparer.OrdinalIgnoreCase);
        private readonly ConcurrentDictionary<string, Token> _tokens = new ConcurrentDictionary<string, Token>(StringComparer.OrdinalIgnoreCase);
        private readonly ConcurrentQueue<Transaction> _pendingTransactions = new ConcurrentQueue<Transaction>();
        private readonly ConcurrentDictionary<long, Block> _blocks = new ConcurrentDictionary<long, Block>();
        private readonly ConcurrentDictionary<string, TransactionReceipt> _transactionReceipts = new ConcurrentDictionary<string, TransactionReceipt>(StringComparer.OrdinalIgnoreCase);
        private readonly ConcurrentDictionary<string, Transaction> _transactionPool = new ConcurrentDictionary<string, Transaction>(StringComparer.OrdinalIgnoreCase);
        private readonly object _blockchainLock = new object();
        private readonly object _walletLock = new object();
        private readonly object _tokenLock = new object();
        private readonly object _statsLock = new object();
        private readonly SHA256 _sha256 = SHA256.Create();
        private readonly Random _random = new Random();
        private readonly NodeStats _nodeStats = new NodeStats();

        public async Task<TransactionReceipt> ProcessTransactionAsync(Transaction transaction, CancellationToken cancellationToken = default)
        {
            if (transaction == null)
            {
                throw new ArgumentNullException(nameof(transaction));
            }

            if (string.IsNullOrWhiteSpace(transaction.Id))
            {
                transaction.Id = GenerateTransactionId(transaction);
            }

            if (_transactionPool.ContainsKey(transaction.Id))
            {
                throw new InvalidOperationException("Transaction already exists in the pool.");
            }

            if (!_transactionPool.TryAdd(transaction.Id, transaction))
            {
                throw new InvalidOperationException("Failed to add transaction to the pool.");
            }

            _pendingTransactions.Enqueue(transaction);

            var receipt = new TransactionReceipt
            {
                TransactionId = transaction.Id,
                Status = TransactionStatus.Pending,
                Timestamp = DateTime.UtcNow
            };

            _transactionReceipts.TryAdd(transaction.Id, receipt);

            return receipt;
        }

        public async Task<Block> MineBlockAsync(CancellationToken cancellationToken = default)
        {
            var transactions = new List<Transaction>();
            while (_pendingTransactions.TryDequeue(out var transaction))
            {
                transactions.Add(transaction);
            }

            if (transactions.Count == 0)
            {
                return null;
            }

            var block = new Block
            {
                Index = _blocks.Count + 1,
                Timestamp = DateTime.UtcNow,
                Transactions = transactions,
                PreviousHash = _blocks.Count == 0 ? "0" : _blocks[_blocks.Count - 1].Hash,
                Nonce = (ulong)_random.Next(),
                MinerAddress = "0xMinerAddress",
                Difficulty = 4
            };

            block.MerkleRoot = CalculateMerkleRoot(transactions);
            block.Hash = CalculateBlockHash(block);

            lock (_blockchainLock)
            {
                _blocks.TryAdd(block.Index, block);
                _nodeStats.ChainHeight = block.Index;
            }

            foreach (var transaction in transactions)
            {
                var receipt = _transactionReceipts[transaction.Id];
                receipt.BlockIndex = block.Index;
                receipt.BlockHash = block.Hash;
                receipt.Status = TransactionStatus.Confirmed;
                receipt.Timestamp = DateTime.UtcNow;

                _transactionReceipts[transaction.Id] = receipt;
                _transactionPool.TryRemove(transaction.Id, out _);
            }

            return block;
        }

        public async Task<Wallet> GetWalletAsync(string address, CancellationToken cancellationToken = default)
        {
            if (string.IsNullOrWhiteSpace(address))
            {
                throw new ArgumentException("Value cannot be null or whitespace.", nameof(address));
            }

            if (_wallets.TryGetValue(address, out var wallet))
            {
                return wallet;
            }

            wallet = new Wallet
            {
                Address = address,
                PublicKey = GeneratePublicKey(address),
                Balance = 0,
                Nonce = 0,
                CreatedAt = DateTime.UtcNow
            };

            lock (_walletLock)
            {
                _wallets.TryAdd(address, wallet);
            }

            return wallet;
        }

        public async Task<Token> GetTokenAsync(string symbol, CancellationToken cancellationToken = default)
        {
            if (string.IsNullOrWhiteSpace(symbol))
            {
                throw new ArgumentException("Value cannot be null or whitespace.", nameof(symbol));
            }

            if (_tokens.TryGetValue(symbol, out var token))
            {
                return token;
            }

            token = new Token
            {
                Symbol = symbol,
                Name = symbol,
                Decimals = 18,
                TotalSupply = 0,
                Owner = "0xTokenOwner"
            };

            lock (_tokenLock)
            {
                _tokens.TryAdd(symbol, token);
            }

            return token;
        }

        public async Task<NodeStats> GetNodeStatsAsync(CancellationToken cancellationToken = default)
        {
            lock (_statsLock)
            {
                return _nodeStats;
            }
        }

        private string GenerateTransactionId(Transaction transaction)
        {
            var payloadBytes = transaction.GetRawPayloadBytes();
            var hashBytes = _sha256.ComputeHash(payloadBytes);
            return BitConverter.ToString(hashBytes).Replace("-", "").ToLower();
        }

        private string CalculateMerkleRoot(List<Transaction> transactions)
        {
            if (transactions.Count == 0)
            {
                return string.Empty;
            }

            var hashes = transactions.Select(t => GenerateTransactionId(t)).ToList();

            while (hashes.Count > 1)
            {
                var newHashes = new List<string>();

                for (var i = 0; i < hashes.Count; i += 2)
                {
                    var left = hashes[i];
                    var right = i + 1 < hashes.Count ? hashes[i + 1] : hashes[i];

                    var combined = left + right;
                    var combinedBytes = Encoding.UTF8.GetBytes(combined);
                    var hashBytes = _sha256.ComputeHash(combinedBytes);
                    var hash = BitConverter.ToString(hashBytes).Replace("-", "").ToLower();

                    newHashes.Add(hash);
                }

                hashes = newHashes;
            }

            return hashes[0];
        }

        private string CalculateBlockHash(Block block)
        {
            var blockData = $"{block.Index}:{block.Timestamp:O}:{block.PreviousHash}:{block.MerkleRoot}:{block.Nonce}:{block.MinerAddress}:{block.Difficulty}";
            var blockBytes = Encoding.UTF8.GetBytes(blockData);
            var hashBytes = _sha256.ComputeHash(blockBytes);
            return BitConverter.ToString(hashBytes).Replace("-", "").ToLower();
        }

        private string GeneratePublicKey(string address)
        {
            var addressBytes = Encoding.UTF8.GetBytes(address);
            var hashBytes = _sha256.ComputeHash(addressBytes);
            return BitConverter.ToString(hashBytes).Replace("-", "").ToLower();
        }
    }
}