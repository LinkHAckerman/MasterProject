using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace MagnumOpus.Core
{
    public class TransactionProcessor
    {
        private readonly Dictionary<string, Wallet> _wallets;
        private readonly Dictionary<string, Token> _tokens;
        private readonly List<Transaction> _pendingTransactions;
        private readonly List<Block> _blockchain;
        private readonly int _difficulty;
        private readonly int _blockTime;
        private readonly object _lock = new object();

        public TransactionProcessor(int difficulty = 4, int blockTime = 10)
        {
            _wallets = new Dictionary<string, Wallet>();
            _tokens = new Dictionary<string, Token>();
            _pendingTransactions = new List<Transaction>();
            _blockchain = new List<Block>();
            _difficulty = difficulty;
            _blockTime = blockTime;

            // Initialize with genesis block
            _blockchain.Add(CreateGenesisBlock());
        }

        private Block CreateGenesisBlock()
        {
            var genesisTransaction = new Transaction
            {
                Sender = "0",
                Recipient = "0",
                Amount = 0,
                Timestamp = DateTime.UtcNow,
                Signature = "genesis"
            };

            return new Block
            {
                Index = 0,
                Timestamp = DateTime.UtcNow,
                Transactions = new List<Transaction> { genesisTransaction },
                PreviousHash = "0",
                Nonce = 0,
                Hash = CalculateHash(0, DateTime.UtcNow, new List<Transaction> { genesisTransaction }, "0", 0)
            };
        }

        public void AddWallet(string address, Wallet wallet)
        {
            lock (_lock)
            {
                _wallets[address] = wallet;
            }
        }

        public void AddToken(string symbol, Token token)
        {
            lock (_lock)
            {
                _tokens[symbol] = token;
            }
        }

        public async Task<string> CreateTransaction(string sender, string recipient, decimal amount, string signature)
        {
            var transaction = new Transaction
            {
                Sender = sender,
                Recipient = recipient,
                Amount = amount,
                Timestamp = DateTime.UtcNow,
                Signature = signature
            };

            // Validate transaction
            if (!await ValidateTransaction(transaction))
            {
                throw new InvalidOperationException("Invalid transaction");
            }

            lock (_lock)
            {
                _pendingTransactions.Add(transaction);
            }

            return transaction.Id;
        }

        private async Task<bool> ValidateTransaction(Transaction transaction)
        {
            // Check if sender has enough balance
            if (!_wallets.ContainsKey(transaction.Sender))
            {
                return false;
            }

            var senderWallet = _wallets[transaction.Sender];
            if (senderWallet.Balance < transaction.Amount)
            {
                return false;
            }

            // Verify signature
            if (!await VerifySignature(transaction))
            {
                return false;
            }

            return true;
        }

        private async Task<bool> VerifySignature(Transaction transaction)
        {
            // In a real implementation, this would verify the cryptographic signature
            // For this example, we'll just check if the signature is not empty
            return !string.IsNullOrEmpty(transaction.Signature);
        }

        public async Task MineBlock(string minerAddress)
        {
            List<Transaction> blockTransactions;
            lock (_lock)
            {
                blockTransactions = _pendingTransactions.Take(10).ToList();
                _pendingTransactions.RemoveRange(0, blockTransactions.Count);
            }

            var lastBlock = _blockchain.Last();
            var newBlock = new Block
            {
                Index = lastBlock.Index + 1,
                Timestamp = DateTime.UtcNow,
                Transactions = blockTransactions,
                PreviousHash = lastBlock.Hash,
                Nonce = 0
            };

            // Mine the block
            await Mine(newBlock);

            // Add the mined block to the blockchain
            lock (_lock)
            {
                _blockchain.Add(newBlock);
            }

            // Reward the miner
            await CreateTransaction("0", minerAddress, 1, "mining_reward");
        }

        private async Task Mine(Block block)
        {
            var stopwatch = System.Diagnostics.Stopwatch.StartNew();
            while (!IsValidHash(block.Hash, _difficulty))
            {
                block.Nonce++;
                block.Hash = CalculateHash(block.Index, block.Timestamp, block.Transactions, block.PreviousHash, block.Nonce);

                // Check if we should stop mining
                if (stopwatch.Elapsed.TotalSeconds >= _blockTime)
                {
                    break;
                }
            }
            stopwatch.Stop();
        }

        private bool IsValidHash(string hash, int difficulty)
        {
            var leadingZeros = new string('0', difficulty);
            return hash.StartsWith(leadingZeros);
        }

        private string CalculateHash(int index, DateTime timestamp, List<Transaction> transactions, string previousHash, int nonce)
        {
            var blockHeader = $"{index}{timestamp:yyyyMMddHHmmss}{previousHash}{nonce}";
            var transactionData = string.Join("", transactions.Select(t => t.Id));
            var blockData = blockHeader + transactionData;

            using (var sha256 = SHA256.Create())
            {
                var hashBytes = sha256.ComputeHash(Encoding.UTF8.GetBytes(blockData));
                return BitConverter.ToString(hashBytes).Replace("-", "").ToLower();
            }
        }

        public List<Block> GetBlockchain()
        {
            lock (_lock)
            {
                return new List<Block>(_blockchain);
            }
        }

        public List<Transaction> GetPendingTransactions()
        {
            lock (_lock)
            {
                return new List<Transaction>(_pendingTransactions);
            }
        }
    }

    public class Wallet
    {
        public string Address { get; set; }
        public decimal Balance { get; set; }
        public Dictionary<string, decimal> TokenBalances { get; set; }

        public Wallet(string address)
        {
            Address = address;
            Balance = 0;
            TokenBalances = new Dictionary<string, decimal>();
        }
    }

    public class Token
    {
        public string Symbol { get; set; }
        public string Name { get; set; }
        public decimal TotalSupply { get; set; }
        public int Decimals { get; set; }
    }

    public class Transaction
    {
        public string Id { get; } = Guid.NewGuid().ToString();
        public string Sender { get; set; }
        public string Recipient { get; set; }
        public decimal Amount { get; set; }
        public DateTime Timestamp { get; set; }
        public string Signature { get; set; }
    }

    public class Block
    {
        public int Index { get; set; }
        public DateTime Timestamp { get; set; }
        public List<Transaction> Transactions { get; set; }
        public string PreviousHash { get; set; }
        public int Nonce { get; set; }
        public string Hash { get; set; }
    }
}