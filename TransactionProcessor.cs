using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace MagnumOpus.Backend.Core
{
    public class TransactionProcessor
    {
        private readonly Dictionary<string, Wallet> _wallets;
        private readonly Dictionary<string, Token> _tokens;
        private readonly List<Transaction> _pendingTransactions;
        private readonly List<Block> _blockchain;
        private readonly int _difficulty;
        private readonly object _lock = new object();

        public TransactionProcessor(int difficulty = 4)
        {
            _wallets = new Dictionary<string, Wallet>();
            _tokens = new Dictionary<string, Token>();
            _pendingTransactions = new List<Transaction>();
            _blockchain = new List<Block>();
            _difficulty = difficulty;

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

        public string CalculateHash(int index, DateTime timestamp, List<Transaction> transactions, string previousHash, int nonce)
        {
            using (SHA256 sha256 = SHA256.Create())
            {
                string rawData = $"{index}{timestamp:yyyyMMddHHmmss}{previousHash}{nonce}{string.Join("", transactions.Select(t => t.ToString()))}";
                byte[] bytes = sha256.ComputeHash(Encoding.UTF8.GetBytes(rawData));
                return BitConverter.ToString(bytes).Replace("-", "").ToLower();
            }
        }

        public bool AddTransaction(Transaction transaction)
        {
            if (transaction == null)
                throw new ArgumentNullException(nameof(transaction));

            if (!IsValidTransaction(transaction))
                return false;

            lock (_lock)
            {
                _pendingTransactions.Add(transaction);
            }

            return true;
        }

        private bool IsValidTransaction(Transaction transaction)
        {
            // Verify transaction signature
            if (!VerifySignature(transaction))
                return false;

            // Check if sender has sufficient balance
            if (!_wallets.ContainsKey(transaction.Sender))
                return false;

            var senderWallet = _wallets[transaction.Sender];
            if (senderWallet.Balance < transaction.Amount)
                return false;

            return true;
        }

        private bool VerifySignature(Transaction transaction)
        {
            // Implement ECDSA signature verification
            // This is a simplified version for demonstration
            return !string.IsNullOrEmpty(transaction.Signature);
        }

        public async Task MinePendingTransactions(string minerAddress)
        {
            if (_pendingTransactions.Count == 0)
                return;

            var block = new Block
            {
                Index = _blockchain.Count,
                Timestamp = DateTime.UtcNow,
                Transactions = new List<Transaction>(_pendingTransactions),
                PreviousHash = GetLatestBlock().Hash
            };

            // Add reward transaction for the miner
            var rewardTransaction = new Transaction
            {
                Sender = "0",
                Recipient = minerAddress,
                Amount = 10,
                Timestamp = DateTime.UtcNow,
                Signature = "mining_reward"
            };

            block.Transactions.Add(rewardTransaction);

            // Mine the block
            await MineBlock(block);

            lock (_lock)
            {
                _blockchain.Add(block);
                _pendingTransactions.Clear();
            }
        }

        private async Task MineBlock(Block block)
        {
            block.Nonce = 0;
            block.Hash = CalculateHash(block.Index, block.Timestamp, block.Transactions, block.PreviousHash, block.Nonce);

            while (!IsValidHash(block.Hash, _difficulty))
            {
                block.Nonce++;
                block.Hash = CalculateHash(block.Index, block.Timestamp, block.Transactions, block.PreviousHash, block.Nonce);
                await Task.Delay(1); // Simulate mining delay
            }
        }

        private bool IsValidHash(string hash, int difficulty)
        {
            string target = new string('0', difficulty);
            return hash.StartsWith(target);
        }

        public Block GetLatestBlock()
        {
            lock (_lock)
            {
                return _blockchain.LastOrDefault();
            }
        }

        public bool IsChainValid()
        {
            lock (_lock)
            {
                for (int i = 1; i < _blockchain.Count; i++)
                {
                    var currentBlock = _blockchain[i];
                    var previousBlock = _blockchain[i - 1];

                    // Check if current block hash is valid
                    if (currentBlock.Hash != CalculateHash(currentBlock.Index, currentBlock.Timestamp, currentBlock.Transactions, currentBlock.PreviousHash, currentBlock.Nonce))
                        return false;

                    // Check if previous block hash is correct
                    if (currentBlock.PreviousHash != previousBlock.Hash)
                        return false;
                }
            }

            return true;
        }

        public void AddWallet(Wallet wallet)
        {
            if (wallet == null)
                throw new ArgumentNullException(nameof(wallet));

            lock (_lock)
            {
                _wallets[wallet.Address] = wallet;
            }
        }

        public void AddToken(Token token)
        {
            if (token == null)
                throw new ArgumentNullException(nameof(token));

            lock (_lock)
            {
                _tokens[token.Symbol] = token;
            }
        }
    }

    public class Wallet
    {
        public string Address { get; set; }
        public decimal Balance { get; set; }
        public Dictionary<string, decimal> TokenBalances { get; set; } = new Dictionary<string, decimal>();
    }

    public class Token
    {
        public string Symbol { get; set; }
        public string Name { get; set; }
        public decimal TotalSupply { get; set; }
    }

    public class Transaction
    {
        public string Sender { get; set; }
        public string Recipient { get; set; }
        public decimal Amount { get; set; }
        public DateTime Timestamp { get; set; }
        public string Signature { get; set; }

        public override string ToString()
        {
            return $"{Sender}{Recipient}{Amount}{Timestamp:yyyyMMddHHmmss}{Signature}";
        }
    }

    public class Block
    {
        public int Index { get; set; }
        public DateTime Timestamp { get; set; }
        public List<Transaction> Transactions { get; set; } = new List<Transaction>();
        public string PreviousHash { get; set; }
        public int Nonce { get; set; }
        public string Hash { get; set; }
    }
}