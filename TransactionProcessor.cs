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

        [JsonPropertyName("contractAddress")]
        public string ContractAddress { get; set; } = string.Empty;
    }

    #endregion

    #region Transaction Processor

    public interface ITransactionProcessor
    {
        Task<TransactionReceipt> ProcessTransactionAsync(Transaction transaction, CancellationToken cancellationToken = default);
        Task<Block> MineBlockAsync(CancellationToken cancellationToken = default);
        Task<Block> GetLatestBlockAsync(CancellationToken cancellationToken = default);
        Task<Transaction> GetTransactionAsync(string transactionId, CancellationToken cancellationToken = default);
        Task<TransactionReceipt> GetTransactionReceiptAsync(string transactionId, CancellationToken cancellationToken = default);
        Task<Wallet> GetWalletAsync(string address, CancellationToken cancellationToken = default);
        Task<Token> GetTokenAsync(string symbol, CancellationToken cancellationToken = default);
    }

    public sealed class TransactionProcessor : ITransactionProcessor
    {
        private readonly ConcurrentDictionary<string, Transaction> _pendingTransactions = new ConcurrentDictionary<string, Transaction>();
        private readonly ConcurrentDictionary<string, TransactionReceipt> _transactionReceipts = new ConcurrentDictionary<string, TransactionReceipt>();
        private readonly ConcurrentDictionary<string, Block> _blocks = new ConcurrentDictionary<string, Block>();
        private readonly ConcurrentDictionary<string, Wallet> _wallets = new ConcurrentDictionary<string, Wallet>();
        private readonly ConcurrentDictionary<string, Token> _tokens = new ConcurrentDictionary<string, Token>();
        private readonly object _miningLock = new object();
        private readonly object _walletLock = new object();
        private readonly object _tokenLock = new object();
        private readonly Random _random = new Random();

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
        }

        public async Task<TransactionReceipt> ProcessTransactionAsync(Transaction transaction, CancellationToken cancellationToken = default)
        {
            // Validate transaction
            if (string.IsNullOrWhiteSpace(transaction.Sender) || string.IsNullOrWhiteSpace(transaction.Recipient))
            {
                throw new ArgumentException("Invalid transaction sender or recipient");
            }

            if (transaction.Amount <= 0)
            {
                throw new ArgumentException("Invalid transaction amount");
            }

            if (transaction.Fee <= 0)
            {
                throw new ArgumentException("Invalid transaction fee");
            }

            // Check if transaction already exists
            if (_pendingTransactions.ContainsKey(transaction.Id) || _transactionReceipts.ContainsKey(transaction.Id))
            {
                throw new InvalidOperationException("Transaction already exists");
            }

            // Add transaction to pending transactions
            _pendingTransactions.TryAdd(transaction.Id, transaction);

            // Return pending transaction receipt
            return new TransactionReceipt
            {
                TransactionId = transaction.Id,
                BlockIndex = -1,
                BlockHash = string.Empty,
                GasUsed = 0,
                FeePaid = 0,
                Status = TransactionStatus.Pending,
                Timestamp = DateTime.UtcNow,
                ExecutionMessage = "Transaction is pending"
            };
        }

        public async Task<Block> MineBlockAsync(CancellationToken cancellationToken = default)
        {
            lock (_miningLock)
            {
                // Get the latest block
                var latestBlock = _blocks.Values.OrderByDescending(b => b.Index).FirstOrDefault();

                // Create new block
                var newBlock = new Block
                {
                    Index = latestBlock.Index + 1,
                    Timestamp = DateTime.UtcNow,
                    Transactions = _pendingTransactions.Values.ToList(),
                    PreviousHash = latestBlock.Hash,
                    MerkleRoot = ComputeMerkleRoot(_pendingTransactions.Values.ToList()),
                    Nonce = (ulong)_random.Next(),
                    MinerAddress = "0",
                    Difficulty = 1
                };

                // Compute block hash
                newBlock.Hash = ComputeBlockHash(newBlock);

                // Add block to blocks
                _blocks.TryAdd(newBlock.Hash, newBlock);

                // Clear pending transactions
                _pendingTransactions.Clear();

                // Create transaction receipts
                foreach (var transaction in newBlock.Transactions)
                {
                    var receipt = new TransactionReceipt
                    {
                        TransactionId = transaction.Id,
                        BlockIndex = newBlock.Index,
                        BlockHash = newBlock.Hash,
                        GasUsed = 0,
                        FeePaid = transaction.Fee,
                        Status = TransactionStatus.Confirmed,
                        Timestamp = DateTime.UtcNow,
                        ExecutionMessage = "Transaction confirmed"
                    };
                    _transactionReceipts.TryAdd(receipt.TransactionId, receipt);
                }

                return newBlock;
            }
        }

        public async Task<Block> GetLatestBlockAsync(CancellationToken cancellationToken = default)
        {
            return _blocks.Values.OrderByDescending(b => b.Index).FirstOrDefault();
        }

        public async Task<Transaction> GetTransactionAsync(string transactionId, CancellationToken cancellationToken = default)
        {
            if (_pendingTransactions.TryGetValue(transactionId, out var pendingTransaction))
            {
                return pendingTransaction;
            }

            var receipt = await GetTransactionReceiptAsync(transactionId, cancellationToken);
            if (receipt != null && _blocks.TryGetValue(receipt.BlockHash, out var block))
            {
                return block.Transactions.FirstOrDefault(t => t.Id == transactionId);
            }

            return null;
        }

        public async Task<TransactionReceipt> GetTransactionReceiptAsync(string transactionId, CancellationToken cancellationToken = default)
        {
            if (_transactionReceipts.TryGetValue(transactionId, out var receipt))
            {
                return receipt;
            }

            return null;
        }

        public async Task<Wallet> GetWalletAsync(string address, CancellationToken cancellationToken = default)
        {
            lock (_walletLock)
            {
                if (_wallets.TryGetValue(address, out var wallet))
                {
                    return wallet;
                }

                // Create new wallet
                wallet = new Wallet
                {
                    Address = address,
                    PublicKey = string.Empty,
                    Balance = 0,
                    TokenBalances = new Dictionary<string, decimal>(StringComparer.OrdinalIgnoreCase),
                    Nonce = 0,
                    CreatedAt = DateTime.UtcNow
                };
                _wallets.TryAdd(wallet.Address, wallet);

                return wallet;
            }
        }

        public async Task<Token> GetTokenAsync(string symbol, CancellationToken cancellationToken = default)
        {
            lock (_tokenLock)
            {
                if (_tokens.TryGetValue(symbol, out var token))
                {
                    return token;
                }

                // Create new token
                token = new Token
                {
                    Symbol = symbol,
                    Name = string.Empty,
                    Decimals = 18,
                    TotalSupply = 0,
                    ContractAddress = string.Empty
                };
                _tokens.TryAdd(token.Symbol, token);

                return token;
            }
        }

        private string ComputeMerkleRoot(List<Transaction> transactions)
        {
            if (transactions.Count == 0)
            {
                return "0";
            }

            var hashes = transactions.Select(t => t.ComputeHash()).ToList();

            while (hashes.Count > 1)
            {
                var newHashes = new List<string>();

                for (var i = 0; i < hashes.Count; i += 2)
                {
                    var left = hashes[i];
                    var right = i + 1 < hashes.Count ? hashes[i + 1] : hashes[i];

                    using var sha256 = SHA256.Create();
                    var combined = Encoding.UTF8.GetBytes(left + right);
                    var hash = sha256.ComputeHash(combined);
                    newHashes.Add(Convert.ToHexString(hash).ToLowerInvariant());
                }

                hashes = newHashes;
            }

            return hashes[0];
        }

        private string ComputeBlockHash(Block block)
        {
            using var sha256 = SHA256.Create();
            var blockData = Encoding.UTF8.GetBytes($"{block.Index}:{block.Timestamp:O}:{block.MerkleRoot}:{block.PreviousHash}:{block.Nonce}");
            var hash = sha256.ComputeHash(blockData);
            return Convert.ToHexString(hash).ToLowerInvariant();
        }
    }

    #endregion
}