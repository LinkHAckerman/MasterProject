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
        private readonly int _blockTime;
        private DateTime _lastBlockTime;

        public TransactionProcessor(int difficulty = 4, int blockTime = 10)
        {
            _wallets = new Dictionary<string, Wallet>();
            _tokens = new Dictionary<string, Token>();
            _pendingTransactions = new List<Transaction>();
            _blockchain = new List<Block>();
            _difficulty = difficulty;
            _blockTime = blockTime;
            _lastBlockTime = DateTime.UtcNow;

            // Initialize with genesis block
            var genesisBlock = new Block
            {
                Index = 0,
                Timestamp = DateTime.UtcNow,
                Transactions = new List<Transaction>(),
                PreviousHash = "0",
                Nonce = 0,
                Hash = CalculateHash(new Block
                {
                    Index = 0,
                    Timestamp = DateTime.UtcNow,
                    Transactions = new List<Transaction>(),
                    PreviousHash = "0",
                    Nonce = 0
                })
            };
            _blockchain.Add(genesisBlock);
        }

        public void AddWallet(string address, Wallet wallet)
        {
            _wallets[address] = wallet;
        }

        public void AddToken(string symbol, Token token)
        {
            _tokens[symbol] = token;
        }

        public void AddTransaction(Transaction transaction)
        {
            if (IsValidTransaction(transaction))
            {
                _pendingTransactions.Add(transaction);
            }
        }

        public async Task MinePendingTransactions(string minerAddress)
        {
            if (_pendingTransactions.Count == 0) return;

            var block = new Block
            {
                Index = _blockchain.Count,
                Timestamp = DateTime.UtcNow,
                Transactions = new List<Transaction>(_pendingTransactions),
                PreviousHash = GetLatestBlock().Hash,
                Nonce = 0
            };

            // Add miner reward
            var rewardTransaction = new Transaction
            {
                FromAddress = "0",
                ToAddress = minerAddress,
                Amount = 10,
                Timestamp = DateTime.UtcNow,
                TokenSymbol = "MAGNUM",
                Signature = "MINER_REWARD"
            };
            block.Transactions.Add(rewardTransaction);

            // Mine the block
            await MineBlock(block);

            // Add block to the blockchain
            _blockchain.Add(block);

            // Clear pending transactions
            _pendingTransactions.Clear();

            // Update last block time
            _lastBlockTime = DateTime.UtcNow;
        }

        private async Task MineBlock(Block block)
        {
            while (!IsValidHash(block.Hash, _difficulty))
            {
                block.Nonce++;
                block.Hash = CalculateHash(block);
                await Task.Delay(1); // Prevent CPU overload
            }
        }

        private bool IsValidTransaction(Transaction transaction)
        {
            // Check if transaction is valid
            if (transaction.FromAddress == null || transaction.ToAddress == null)
                return false;

            if (!_wallets.ContainsKey(transaction.FromAddress) || !_wallets.ContainsKey(transaction.ToAddress))
                return false;

            if (transaction.TokenSymbol != null && !_tokens.ContainsKey(transaction.TokenSymbol))
                return false;

            if (transaction.Amount <= 0)
                return false;

            // Check if sender has enough balance
            var senderWallet = _wallets[transaction.FromAddress];
            if (transaction.TokenSymbol == null)
            {
                if (senderWallet.Balance < transaction.Amount)
                    return false;
            }
            else
            {
                if (!senderWallet.TokenBalances.ContainsKey(transaction.TokenSymbol) ||
                    senderWallet.TokenBalances[transaction.TokenSymbol] < transaction.Amount)
                    return false;
            }

            // Verify signature
            if (!VerifySignature(transaction))
                return false;

            return true;
        }

        private bool VerifySignature(Transaction transaction)
        {
            // Simplified signature verification
            if (transaction.Signature == "MINER_REWARD")
                return true;

            // In a real implementation, you would use a proper cryptographic signature verification
            // For this example, we'll just check if the signature is not null or empty
            return !string.IsNullOrEmpty(transaction.Signature);
        }

        private string CalculateHash(Block block)
        {
            var blockData = JsonSerializer.Serialize(block);
            using (var sha256 = SHA256.Create())
            {
                var hashBytes = sha256.ComputeHash(Encoding.UTF8.GetBytes(blockData));
                return BitConverter.ToString(hashBytes).Replace("-", "").ToLower();
            }
        }

        private bool IsValidHash(string hash, int difficulty)
        {
            var prefix = new string('0', difficulty);
            return hash.StartsWith(prefix);
        }

        public Block GetLatestBlock()
        {
            return _blockchain.Last();
        }

        public List<Block> GetBlockchain()
        {
            return new List<Block>(_blockchain);
        }

        public List<Transaction> GetPendingTransactions()
        {
            return new List<Transaction>(_pendingTransactions);
        }
    }

    public class Wallet
    {
        public string Address { get; set; }
        public double Balance { get; set; }
        public Dictionary<string, double> TokenBalances { get; set; }

        public Wallet()
        {
            TokenBalances = new Dictionary<string, double>();
        }
    }

    public class Token
    {
        public string Symbol { get; set; }
        public string Name { get; set; }
        public double TotalSupply { get; set; }
    }

    public class Transaction
    {
        public string FromAddress { get; set; }
        public string ToAddress { get; set; }
        public double Amount { get; set; }
        public DateTime Timestamp { get; set; }
        public string TokenSymbol { get; set; }
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