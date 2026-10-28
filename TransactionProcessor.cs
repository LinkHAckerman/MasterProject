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

        [JsonPropertyName("createdAt")]
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
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
        private readonly ConcurrentDictionary<string, Transaction> _pendingTransactions = new ConcurrentDictionary<string, Transaction>(StringComparer.OrdinalIgnoreCase);
        private readonly ConcurrentDictionary<string, TransactionReceipt> _transactionReceipts = new ConcurrentDictionary<string, TransactionReceipt>(StringComparer.OrdinalIgnoreCase);
        private readonly ConcurrentDictionary<string, Wallet> _wallets = new ConcurrentDictionary<string, Wallet>(StringComparer.OrdinalIgnoreCase);
        private readonly ConcurrentDictionary<string, Token> _tokens = new ConcurrentDictionary<string, Token>(StringComparer.OrdinalIgnoreCase);
        private readonly ConcurrentQueue<Block> _blockchain = new ConcurrentQueue<Block>();
        private readonly SemaphoreSlim _blockMiningSemaphore = new SemaphoreSlim(1, 1);
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
            _blockchain.Enqueue(genesisBlock);
        }

        public async Task<TransactionReceipt> ProcessTransactionAsync(Transaction transaction, CancellationToken cancellationToken = default)
        {
            // Validate transaction
            if (string.IsNullOrWhiteSpace(transaction.Id))
            {
                transaction.Id = Guid.NewGuid().ToString();
            }

            if (string.IsNullOrWhiteSpace(transaction.Sender) || string.IsNullOrWhiteSpace(transaction.Recipient))
            {
                throw new ArgumentException("Invalid sender or recipient address");
            }

            if (transaction.Amount <= 0)
            {
                throw new ArgumentException("Invalid transaction amount");
            }

            if (transaction.Fee <= 0)
            {
                throw new ArgumentException("Invalid transaction fee");
            }

            // Check if sender has enough balance
            var senderWallet = await GetWalletAsync(transaction.Sender, cancellationToken);
            if (senderWallet.Balance < transaction.Amount + transaction.Fee)
            {
                throw new InvalidOperationException("Insufficient balance");
            }

            // Check if sender nonce is valid
            if (senderWallet.Nonce != transaction.Nonce)
            {
                throw new InvalidOperationException("Invalid nonce");
            }

            // Add transaction to pending transactions
            _pendingTransactions.TryAdd(transaction.Id, transaction);

            // Create transaction receipt
            var transactionReceipt = new TransactionReceipt
            {
                TransactionId = transaction.Id,
                BlockIndex = -1,
                BlockHash = string.Empty,
                GasUsed = transaction.Fee,
                FeePaid = transaction.Fee,
                Status = TransactionStatus.Pending,
                Timestamp = DateTime.UtcNow,
                ExecutionMessage = "Transaction is pending"
            };

            _transactionReceipts.TryAdd(transaction.Id, transactionReceipt);

            return transactionReceipt;
        }

        public async Task<Block> MineBlockAsync(CancellationToken cancellationToken = default)
        {
            await _blockMiningSemaphore.WaitAsync(cancellationToken);

            try
            {
                // Get the latest block
                var latestBlock = await GetLatestBlockAsync(cancellationToken);

                // Create a new block
                var newBlock = new Block
                {
                    Index = latestBlock.Index + 1,
                    Timestamp = DateTime.UtcNow,
                    Transactions = new List<Transaction>(),
                    PreviousHash = latestBlock.Hash,
                    MerkleRoot = string.Empty,
                    Nonce = 0,
                    Hash = string.Empty,
                    MinerAddress = "0",
                    Difficulty = latestBlock.Difficulty
                };

                // Add pending transactions to the new block
                foreach (var transaction in _pendingTransactions.Values)
                {
                    newBlock.Transactions.Add(transaction);
                }

                // Calculate Merkle root
                newBlock.MerkleRoot = CalculateMerkleRoot(newBlock.Transactions);

                // Mine the block
                MineBlock(newBlock);

                // Add the new block to the blockchain
                _blockchain.Enqueue(newBlock);

                // Update transaction receipts
                foreach (var transaction in newBlock.Transactions)
                {
                    if (_transactionReceipts.TryGetValue(transaction.Id, out var receipt))
                    {
                        receipt.BlockIndex = newBlock.Index;
                        receipt.BlockHash = newBlock.Hash;
                        receipt.Status = TransactionStatus.Confirmed;
                        receipt.Timestamp = newBlock.Timestamp;
                        receipt.ExecutionMessage = "Transaction confirmed";
                    }
                }

                // Clear pending transactions
                _pendingTransactions.Clear();

                return newBlock;
            }
            finally
            {
                _blockMiningSemaphore.Release();
            }
        }

        private void MineBlock(Block block)
        {
            // Implement block mining logic here
            // For simplicity, we'll just set a random nonce and hash
            block.Nonce = (ulong)_random.Next();
            block.Hash = CalculateBlockHash(block);
        }

        private string CalculateBlockHash(Block block)
        {
            using var sha256 = SHA256.Create();
            var blockData = $"{block.Index}:{block.Timestamp:O}:{block.MerkleRoot}:{block.PreviousHash}:{block.Nonce}";
            var bytes = Encoding.UTF8.GetBytes(blockData);
            var hash = sha256.ComputeHash(bytes);
            return Convert.ToHexString(hash).ToLowerInvariant();
        }

        private string CalculateMerkleRoot(List<Transaction> transactions)
        {
            if (transactions.Count == 0)
            {
                return string.Empty;
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
                    var combined = left + right;
                    var bytes = Encoding.UTF8.GetBytes(combined);
                    var hash = sha256.ComputeHash(bytes);
                    newHashes.Add(Convert.ToHexString(hash).ToLowerInvariant());
                }

                hashes = newHashes;
            }

            return hashes[0];
        }

        public async Task<Block> GetLatestBlockAsync(CancellationToken cancellationToken = default)
        {
            if (_blockchain.TryPeek(out var latestBlock))
            {
                return latestBlock;
            }

            throw new InvalidOperationException("Blockchain is empty");
        }

        public async Task<Transaction> GetTransactionAsync(string transactionId, CancellationToken cancellationToken = default)
        {
            if (_pendingTransactions.TryGetValue(transactionId, out var transaction))
            {
                return transaction;
            }

            foreach (var block in _blockchain)
            {
                var foundTransaction = block.Transactions.FirstOrDefault(t => t.Id == transactionId);
                if (foundTransaction != null)
                {
                    return foundTransaction;
                }
            }

            throw new KeyNotFoundException("Transaction not found");
        }

        public async Task<TransactionReceipt> GetTransactionReceiptAsync(string transactionId, CancellationToken cancellationToken = default)
        {
            if (_transactionReceipts.TryGetValue(transactionId, out var receipt))
            {
                return receipt;
            }

            throw new KeyNotFoundException("Transaction receipt not found");
        }

        public async Task<Wallet> GetWalletAsync(string address, CancellationToken cancellationToken = default)
        {
            if (_wallets.TryGetValue(address, out var wallet))
            {
                return wallet;
            }

            // Create a new wallet if it doesn't exist
            wallet = new Wallet
            {
                Address = address,
                PublicKey = address,
                Balance = 0,
                TokenBalances = new Dictionary<string, decimal>(StringComparer.OrdinalIgnoreCase),
                Nonce = 0,
                CreatedAt = DateTime.UtcNow
            };

            _wallets.TryAdd(address, wallet);

            return wallet;
        }

        public async Task<Token> GetTokenAsync(string symbol, CancellationToken cancellationToken = default)
        {
            if (_tokens.TryGetValue(symbol, out var token))
            {
                return token;
            }

            throw new KeyNotFoundException("Token not found");
        }
    }

    #endregion
}