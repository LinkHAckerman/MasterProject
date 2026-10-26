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
        public int ActiveConnections { get; set; }
        public long PendingTransactions { get; set; }
        public long TotalTransactions { get; set; }
        public decimal TotalSupply { get; set; }
        public decimal CirculatingSupply { get; set; }
        public decimal MarketCap { get; set; }
        public decimal CurrentPrice { get; set; }
        public decimal PriceChange24h { get; set; }
        public decimal Volume24h { get; set; }
        public decimal MarketDominance { get; set; }
        public DateTime LastUpdated { get; set; } = DateTime.UtcNow;
    }

    public interface ITransactionProcessor
    {
        Task<TransactionReceipt> ProcessTransactionAsync(Transaction transaction, CancellationToken cancellationToken = default);
        Task<Block> MineBlockAsync(CancellationToken cancellationToken = default);
        Task<Block> GetLatestBlockAsync(CancellationToken cancellationToken = default);
        Task<NodeStats> GetNodeStatsAsync(CancellationToken cancellationToken = default);
        Task<Wallet> GetWalletAsync(string address, CancellationToken cancellationToken = default);
        Task<Token> GetTokenAsync(string symbol, CancellationToken cancellationToken = default);
    }

    public sealed class TransactionProcessor : ITransactionProcessor
    {
        private readonly ConcurrentDictionary<string, Transaction> _pendingTransactions = new ConcurrentDictionary<string, Transaction>();
        private readonly ConcurrentDictionary<string, Block> _blocks = new ConcurrentDictionary<string, Block>();
        private readonly ConcurrentDictionary<string, Wallet> _wallets = new ConcurrentDictionary<string, Wallet>();
        private readonly ConcurrentDictionary<string, Token> _tokens = new ConcurrentDictionary<string, Token>();
        private readonly ConcurrentQueue<Transaction> _transactionQueue = new ConcurrentQueue<Transaction>();
        private readonly ConcurrentQueue<Block> _blockQueue = new ConcurrentQueue<Block>();
        private readonly SemaphoreSlim _semaphore = new SemaphoreSlim(1, 1);
        private readonly Random _random = new Random();
        private readonly SHA256 _sha256 = SHA256.Create();
        private readonly object _lock = new object();

        private long _chainHeight;
        private int _peerCount;
        private int _activeConnections;
        private long _totalTransactions;
        private decimal _totalSupply = 1_000_000_000m;
        private decimal _circulatingSupply = 1_000_000_000m;
        private decimal _currentPrice = 1.0m;
        private decimal _priceChange24h = 0.0m;
        private decimal _volume24h = 0.0m;
        private decimal _marketDominance = 0.0m;

        public TransactionProcessor()
        {
            // Initialize with genesis block
            var genesisBlock = new Block
            {
                Index = 0,
                Timestamp = DateTime.UtcNow,
                Transactions = new List<Transaction>(),
                PreviousHash = "0",
                MerkleRoot = "0",
                Nonce = 0,
                Hash = "0",
                MinerAddress = "0",
                Difficulty = 1
            };
            _blocks.TryAdd(genesisBlock.Hash, genesisBlock);
            _chainHeight = 0;
        }

        public async Task<TransactionReceipt> ProcessTransactionAsync(Transaction transaction, CancellationToken cancellationToken = default)
        {
            if (transaction == null)
            {
                throw new ArgumentNullException(nameof(transaction));
            }

            if (string.IsNullOrWhiteSpace(transaction.Id))
            {
                transaction.Id = Guid.NewGuid().ToString();
            }

            if (string.IsNullOrWhiteSpace(transaction.Sender) || string.IsNullOrWhiteSpace(transaction.Recipient))
            {
                throw new ArgumentException("Sender and recipient addresses are required.");
            }

            if (transaction.Amount <= 0)
            {
                throw new ArgumentException("Transaction amount must be greater than zero.");
            }

            if (transaction.Fee <= 0)
            {
                throw new ArgumentException("Transaction fee must be greater than zero.");
            }

            if (string.IsNullOrWhiteSpace(transaction.TokenSymbol))
            {
                transaction.TokenSymbol = "MOPUS";
            }

            if (string.IsNullOrWhiteSpace(transaction.Signature))
            {
                throw new ArgumentException("Transaction signature is required.");
            }

            if (!_wallets.TryGetValue(transaction.Sender, out var senderWallet))
            {
                throw new InvalidOperationException("Sender wallet not found.");
            }

            if (senderWallet.Nonce != transaction.Nonce)
            {
                throw new InvalidOperationException("Invalid transaction nonce.");
            }

            if (senderWallet.Balance < transaction.Amount + transaction.Fee)
            {
                throw new InvalidOperationException("Insufficient balance.");
            }

            if (!_tokens.TryGetValue(transaction.TokenSymbol, out var token))
            {
                throw new InvalidOperationException("Token not found.");
            }

            if (!senderWallet.TokenBalances.TryGetValue(transaction.TokenSymbol, out var senderTokenBalance) || senderTokenBalance < transaction.Amount)
            {
                throw new InvalidOperationException("Insufficient token balance.");
            }

            transaction.Status = TransactionStatus.Pending;
            _pendingTransactions.TryAdd(transaction.Id, transaction);
            _transactionQueue.Enqueue(transaction);

            var receipt = new TransactionReceipt
            {
                TransactionId = transaction.Id,
                BlockIndex = _chainHeight + 1,
                BlockHash = string.Empty,
                GasUsed = transaction.Fee,
                FeePaid = transaction.Fee,
                Status = TransactionStatus.Pending,
                Timestamp = DateTime.UtcNow,
                ExecutionMessage = "Transaction added to the mempool."
            };

            return receipt;
        }

        public async Task<Block> MineBlockAsync(CancellationToken cancellationToken = default)
        {
            await _semaphore.WaitAsync(cancellationToken);

            try
            {
                var transactions = new List<Transaction>();
                while (_transactionQueue.TryDequeue(out var transaction))
                {
                    transactions.Add(transaction);
                }

                if (transactions.Count == 0)
                {
                    return null;
                }

                var latestBlock = _blocks.Values.OrderByDescending(b => b.Index).First();
                var newBlock = new Block
                {
                    Index = latestBlock.Index + 1,
                    Timestamp = DateTime.UtcNow,
                    Transactions = transactions,
                    PreviousHash = latestBlock.Hash,
                    MerkleRoot = CalculateMerkleRoot(transactions),
                    Nonce = 0,
                    Hash = string.Empty,
                    MinerAddress = "0",
                    Difficulty = 1
                };

                newBlock.Hash = MineBlock(newBlock);

                foreach (var transaction in transactions)
                {
                    transaction.Status = TransactionStatus.Confirmed;
                    _pendingTransactions.TryRemove(transaction.Id, out _);

                    if (_wallets.TryGetValue(transaction.Sender, out var senderWallet))
                    {
                        senderWallet.Balance -= transaction.Amount + transaction.Fee;
                        senderWallet.Nonce++;
                        senderWallet.TokenBalances[transaction.TokenSymbol] -= transaction.Amount;
                    }

                    if (_wallets.TryGetValue(transaction.Recipient, out var recipientWallet))
                    {
                        recipientWallet.Balance += transaction.Amount;
                        recipientWallet.TokenBalances[transaction.TokenSymbol] += transaction.Amount;
                    }
                }

                _blocks.TryAdd(newBlock.Hash, newBlock);
                _chainHeight = newBlock.Index;
                _totalTransactions += transactions.Count;

                return newBlock;
            }
            finally
            {
                _semaphore.Release();
            }
        }

        private string MineBlock(Block block)
        {
            var target = new string('0', block.Difficulty);
            var hash = string.Empty;

            while (!hash.StartsWith(target))
            {
                block.Nonce++;
                hash = CalculateBlockHash(block);
            }

            return hash;
        }

        private string CalculateBlockHash(Block block)
        {
            var blockData = $"{block.Index}:{block.Timestamp:O}:{block.PreviousHash}:{block.MerkleRoot}:{block.Nonce}";
            var blockBytes = Encoding.UTF8.GetBytes(blockData);
            var hashBytes = _sha256.ComputeHash(blockBytes);
            return BitConverter.ToString(hashBytes).Replace("-", "").ToLower();
        }

        private string CalculateMerkleRoot(List<Transaction> transactions)
        {
            if (transactions.Count == 0)
            {
                return string.Empty;
            }

            var merkleTree = new List<string>();

            foreach (var transaction in transactions)
            {
                merkleTree.Add(CalculateTransactionHash(transaction));
            }

            while (merkleTree.Count > 1)
            {
                var newMerkleTree = new List<string>();

                for (var i = 0; i < merkleTree.Count; i += 2)
                {
                    var left = merkleTree[i];
                    var right = i + 1 < merkleTree.Count ? merkleTree[i + 1] : left;
                    var combined = left + right;
                    var combinedBytes = Encoding.UTF8.GetBytes(combined);
                    var hashBytes = _sha256.ComputeHash(combinedBytes);
                    var hash = BitConverter.ToString(hashBytes).Replace("-", "").ToLower();
                    newMerkleTree.Add(hash);
                }

                merkleTree = newMerkleTree;
            }

            return merkleTree[0];
        }

        private string CalculateTransactionHash(Transaction transaction)
        {
            var transactionBytes = transaction.GetRawPayloadBytes();
            var hashBytes = _sha256.ComputeHash(transactionBytes);
            return BitConverter.ToString(hashBytes).Replace("-", "").ToLower();
        }

        public async Task<Block> GetLatestBlockAsync(CancellationToken cancellationToken = default)
        {
            return _blocks.Values.OrderByDescending(b => b.Index).FirstOrDefault();
        }

        public async Task<NodeStats> GetNodeStatsAsync(CancellationToken cancellationToken = default)
        {
            return new NodeStats
            {
                ChainHeight = _chainHeight,
                PeerCount = _peerCount,
                ActiveConnections = _activeConnections,
                PendingTransactions = _pendingTransactions.Count,
                TotalTransactions = _totalTransactions,
                TotalSupply = _totalSupply,
                CirculatingSupply = _circulatingSupply,
                MarketCap = _circulatingSupply * _currentPrice,
                CurrentPrice = _currentPrice,
                PriceChange24h = _priceChange24h,
                Volume24h = _volume24h,
                MarketDominance = _marketDominance,
                LastUpdated = DateTime.UtcNow
            };
        }

        public async Task<Wallet> GetWalletAsync(string address, CancellationToken cancellationToken = default)
        {
            if (string.IsNullOrWhiteSpace(address))
            {
                throw new ArgumentException("Wallet address is required.");
            }

            if (_wallets.TryGetValue(address, out var wallet))
            {
                return wallet;
            }

            throw new InvalidOperationException("Wallet not found.");
        }

        public async Task<Token> GetTokenAsync(string symbol, CancellationToken cancellationToken = default)
        {
            if (string.IsNullOrWhiteSpace(symbol))
            {
                throw new ArgumentException("Token symbol is required.");
            }

            if (_tokens.TryGetValue(symbol, out var token))
            {
                return token;
            }

            throw new InvalidOperationException("Token not found.");
        }
    }
}