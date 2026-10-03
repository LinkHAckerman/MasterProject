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
        private readonly Dictionary<string, Wallet> _wallets = new Dictionary<string, Wallet>();
        private readonly List<Transaction> _pendingTransactions = new List<Transaction>();
        private readonly List<Block> _blockchain = new List<Block>();
        private readonly int _difficulty = 4;
        private readonly object _lock = new object();

        public class Wallet
        {
            public string Address { get; set; }
            public decimal Balance { get; set; }
            public string PrivateKey { get; set; }

            public Wallet(string address, decimal initialBalance = 0)
            {
                Address = address;
                Balance = initialBalance;
                PrivateKey = GeneratePrivateKey();
            }

            private string GeneratePrivateKey()
            {
                using (var rng = RandomNumberGenerator.Create())
                {
                    byte[] keyBytes = new byte[32];
                    rng.GetBytes(keyBytes);
                    return Convert.ToBase64String(keyBytes);
                }
            }
        }

        public class Transaction
        {
            public string FromAddress { get; set; }
            public string ToAddress { get; set; }
            public decimal Amount { get; set; }
            public string Signature { get; set; }
            public string TransactionId { get; set; }

            public Transaction(string fromAddress, string toAddress, decimal amount)
            {
                FromAddress = fromAddress;
                ToAddress = toAddress;
                Amount = amount;
                TransactionId = GenerateTransactionId();
            }

            private string GenerateTransactionId()
            {
                using (var sha256 = SHA256.Create())
                {
                    var input = $"{FromAddress}{ToAddress}{Amount}{DateTime.UtcNow.Ticks}";
                    var hashBytes = sha256.ComputeHash(Encoding.UTF8.GetBytes(input));
                    return Convert.ToBase64String(hashBytes);
                }
            }
        }

        public class Block
        {
            public int Index { get; set; }
            public DateTime Timestamp { get; set; }
            public List<Transaction> Transactions { get; set; }
            public string PreviousHash { get; set; }
            public string Hash { get; set; }
            public int Nonce { get; set; }

            public Block(int index, string previousHash, List<Transaction> transactions)
            {
                Index = index;
                Timestamp = DateTime.UtcNow;
                Transactions = transactions;
                PreviousHash = previousHash;
                Hash = CalculateHash();
            }

            public string CalculateHash()
            {
                using (var sha256 = SHA256.Create())
                {
                    var input = $"{Index}{Timestamp}{PreviousHash}{Nonce}{JsonSerializer.Serialize(Transactions)}";
                    var hashBytes = sha256.ComputeHash(Encoding.UTF8.GetBytes(input));
                    return Convert.ToBase64String(hashBytes);
                }
            }

            public void MineBlock(int difficulty)
            {
                var target = new string('0', difficulty);
                while (Hash.Substring(0, difficulty) != target)
                {
                    Nonce++;
                    Hash = CalculateHash();
                }
            }
        }

        public void CreateWallet(string address, decimal initialBalance = 0)
        {
            lock (_lock)
            {
                if (!_wallets.ContainsKey(address))
                {
                    _wallets[address] = new Wallet(address, initialBalance);
                }
            }
        }

        public async Task<string> CreateTransaction(string fromAddress, string toAddress, decimal amount)
        {
            if (!_wallets.ContainsKey(fromAddress) || !_wallets.ContainsKey(toAddress))
            {
                throw new Exception("Invalid wallet address");
            }

            if (_wallets[fromAddress].Balance < amount)
            {
                throw new Exception("Insufficient balance");
            }

            var transaction = new Transaction(fromAddress, toAddress, amount);
            transaction.Signature = SignTransaction(transaction, _wallets[fromAddress].PrivateKey);

            lock (_lock)
            {
                _pendingTransactions.Add(transaction);
            }

            return transaction.TransactionId;
        }

        private string SignTransaction(Transaction transaction, string privateKey)
        {
            using (var hmac = new HMACSHA256(Encoding.UTF8.GetBytes(privateKey)))
            {
                var data = Encoding.UTF8.GetBytes($"{transaction.FromAddress}{transaction.ToAddress}{transaction.Amount}");
                var hash = hmac.ComputeHash(data);
                return Convert.ToBase64String(hash);
            }
        }

        public async Task MinePendingTransactions(string minerAddress)
        {
            if (_pendingTransactions.Count == 0)
            {
                return;
            }

            var block = new Block(_blockchain.Count, GetLatestBlock()?.Hash ?? "0", _pendingTransactions.ToList());

            block.MineBlock(_difficulty);

            lock (_lock)
            {
                _blockchain.Add(block);

                foreach (var transaction in block.Transactions)
                {
                    _wallets[transaction.FromAddress].Balance -= transaction.Amount;
                    _wallets[transaction.ToAddress].Balance += transaction.Amount;
                }

                _pendingTransactions.Clear();
            }
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

                    if (currentBlock.Hash != currentBlock.CalculateHash())
                    {
                        return false;
                    }

                    if (currentBlock.PreviousHash != previousBlock.Hash)
                    {
                        return false;
                    }
                }
            }

            return true;
        }
    }
}