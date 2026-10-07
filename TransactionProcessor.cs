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
        private readonly Dictionary<string, Wallet> _wallets = new Dictionary<string, Wallet>();
        private readonly Dictionary<string, Token> _tokens = new Dictionary<string, Token>();
        private readonly List<Transaction> _pendingTransactions = new List<Transaction>();
        private readonly List<Block> _blockchain = new List<Block>();
        private readonly object _lock = new object();

        public class Wallet
        {
            public string Address { get; set; }
            public Dictionary<string, decimal> Balances { get; set; } = new Dictionary<string, decimal>();
            public string PublicKey { get; set; }
            public string PrivateKey { get; set; }
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
            public string From { get; set; }
            public string To { get; set; }
            public string TokenSymbol { get; set; }
            public decimal Amount { get; set; }
            public string Signature { get; set; }
            public string Hash { get; set; }
            public DateTime Timestamp { get; set; } = DateTime.UtcNow;
            public bool IsValid { get; set; } = false;
        }

        public class Block
        {
            public int Index { get; set; }
            public string PreviousHash { get; set; }
            public string Hash { get; set; }
            public DateTime Timestamp { get; set; } = DateTime.UtcNow;
            public List<Transaction> Transactions { get; set; } = new List<Transaction>();
            public int Nonce { get; set; } = 0;
        }

        public TransactionProcessor()
        {
            // Initialize with some test wallets and tokens
            InitializeTestData();
        }

        private void InitializeTestData()
        {
            // Add test tokens
            _tokens.Add("ETH", new Token { Symbol = "ETH", Name = "Ethereum", TotalSupply = 100000000, Decimals = 18 });
            _tokens.Add("USDT", new Token { Symbol = "USDT", Name = "Tether", TotalSupply = 10000000000, Decimals = 6 });
            _tokens.Add("MAGNUM", new Token { Symbol = "MAGNUM", Name = "Magnum Opus", TotalSupply = 1000000000, Decimals = 18 });

            // Add test wallets
            var wallet1 = new Wallet { Address = "0x1234567890abcdef", PublicKey = "publicKey1", PrivateKey = "privateKey1" };
            wallet1.Balances.Add("ETH", 100.0m);
            wallet1.Balances.Add("USDT", 10000.0m);
            wallet1.Balances.Add("MAGNUM", 1000.0m);
            _wallets.Add(wallet1.Address, wallet1);

            var wallet2 = new Wallet { Address = "0xabcdef1234567890", PublicKey = "publicKey2", PrivateKey = "privateKey2" };
            wallet2.Balances.Add("ETH", 50.0m);
            wallet2.Balances.Add("USDT", 5000.0m);
            wallet2.Balances.Add("MAGNUM", 500.0m);
            _wallets.Add(wallet2.Address, wallet2);
        }

        public async Task<string> CreateTransaction(string from, string to, string tokenSymbol, decimal amount, string privateKey)
        {
            if (!_wallets.ContainsKey(from) || !_wallets.ContainsKey(to))
            {
                throw new Exception("Invalid wallet address");
            }

            if (!_tokens.ContainsKey(tokenSymbol))
            {
                throw new Exception("Invalid token symbol");
            }

            var wallet = _wallets[from];
            if (!wallet.Balances.ContainsKey(tokenSymbol) || wallet.Balances[tokenSymbol] < amount)
            {
                throw new Exception("Insufficient balance");
            }

            var transaction = new Transaction
            {
                From = from,
                To = to,
                TokenSymbol = tokenSymbol,
                Amount = amount,
                Timestamp = DateTime.UtcNow
            };

            // Sign the transaction
            transaction.Signature = SignTransaction(transaction, privateKey);
            transaction.Hash = ComputeTransactionHash(transaction);
            transaction.IsValid = VerifyTransaction(transaction);

            if (!transaction.IsValid)
            {
                throw new Exception("Invalid transaction");
            }

            lock (_lock)
            {
                _pendingTransactions.Add(transaction);
            }

            return transaction.Hash;
        }

        private string SignTransaction(Transaction transaction, string privateKey)
        {
            // In a real implementation, this would use proper cryptographic signing
            // For this example, we'll use a simple hash-based signature
            var transactionData = $"{transaction.From}{transaction.To}{transaction.TokenSymbol}{transaction.Amount}{transaction.Timestamp}";
            using (var sha256 = SHA256.Create())
            {
                var hashBytes = sha256.ComputeHash(Encoding.UTF8.GetBytes(transactionData + privateKey));
                return Convert.ToBase64String(hashBytes);
            }
        }

        private string ComputeTransactionHash(Transaction transaction)
        {
            var transactionData = $"{transaction.From}{transaction.To}{transaction.TokenSymbol}{transaction.Amount}{transaction.Timestamp}{transaction.Signature}";
            using (var sha256 = SHA256.Create())
            {
                var hashBytes = sha256.ComputeHash(Encoding.UTF8.GetBytes(transactionData));
                return Convert.ToBase64String(hashBytes);
            }
        }

        private bool VerifyTransaction(Transaction transaction)
        {
            // Verify the signature
            var expectedSignature = SignTransaction(transaction, _wallets[transaction.From].PrivateKey);
            if (transaction.Signature != expectedSignature)
            {
                return false;
            }

            // Verify the hash
            var expectedHash = ComputeTransactionHash(transaction);
            if (transaction.Hash != expectedHash)
            {
                return false;
            }

            return true;
        }

        public async Task<string> MineBlock()
        {
            List<Transaction> transactionsToMine;
            lock (_lock)
            {
                transactionsToMine = _pendingTransactions.Take(10).ToList();
                _pendingTransactions.RemoveRange(0, transactionsToMine.Count);
            }

            var block = new Block
            {
                Index = _blockchain.Count,
                PreviousHash = _blockchain.Count > 0 ? _blockchain.Last().Hash : "0",
                Transactions = transactionsToMine
            };

            // Mine the block
            block.Hash = MineBlockHash(block);

            // Process the transactions
            foreach (var transaction in block.Transactions)
            {
                ProcessTransaction(transaction);
            }

            lock (_lock)
            {
                _blockchain.Add(block);
            }

            return block.Hash;
        }

        private string MineBlockHash(Block block)
        {
            var blockData = $"{block.Index}{block.PreviousHash}{block.Timestamp}{string.Join("", block.Transactions.Select(t => t.Hash))}";
            using (var sha256 = SHA256.Create())
            {
                while (true)
                {
                    var hashBytes = sha256.ComputeHash(Encoding.UTF8.GetBytes(blockData + block.Nonce));
                    var hash = Convert.ToBase64String(hashBytes);
                    if (hash.StartsWith("0000")) // Simple proof-of-work
                    {
                        return hash;
                    }
                    block.Nonce++;
                }
            }
        }

        private void ProcessTransaction(Transaction transaction)
        {
            if (!_wallets.ContainsKey(transaction.From) || !_wallets.ContainsKey(transaction.To))
            {
                throw new Exception("Invalid wallet address");
            }

            if (!_tokens.ContainsKey(transaction.TokenSymbol))
            {
                throw new Exception("Invalid token symbol");
            }

            var fromWallet = _wallets[transaction.From];
            var toWallet = _wallets[transaction.To];

            if (!fromWallet.Balances.ContainsKey(transaction.TokenSymbol) || fromWallet.Balances[transaction.TokenSymbol] < transaction.Amount)
            {
                throw new Exception("Insufficient balance");
            }

            fromWallet.Balances[transaction.TokenSymbol] -= transaction.Amount;
            if (!toWallet.Balances.ContainsKey(transaction.TokenSymbol))
            {
                toWallet.Balances[transaction.TokenSymbol] = 0;
            }
            toWallet.Balances[transaction.TokenSymbol] += transaction.Amount;
        }

        public async Task<List<Transaction>> GetPendingTransactions()
        {
            lock (_lock)
            {
                return _pendingTransactions.ToList();
            }
        }

        public async Task<List<Block>> GetBlockchain()
        {
            lock (_lock)
            {
                return _blockchain.ToList();
            }
        }

        public async Task<Wallet> GetWallet(string address)
        {
            lock (_lock)
            {
                if (_wallets.ContainsKey(address))
                {
                    return _wallets[address];
                }
                return null;
            }
        }
    }
}