using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using System.Security.Cryptography;
using System.Text;
using System.Numerics;

namespace MagnumOpus.Core
{
    public class TransactionProcessor
    {
        private readonly Dictionary<string, BigInteger> _balances = new Dictionary<string, BigInteger>();
        private readonly List<Transaction> _pendingTransactions = new List<Transaction>();
        private readonly List<Block> _blockchain = new List<Block>();
        private readonly object _lock = new object();

        public class Transaction
        {
            public string From { get; set; }
            public string To { get; set; }
            public BigInteger Amount { get; set; }
            public string Signature { get; set; }
            public string TransactionHash { get; set; }
            public DateTime Timestamp { get; set; }
        }

        public class Block
        {
            public int Index { get; set; }
            public string PreviousHash { get; set; }
            public string Hash { get; set; }
            public DateTime Timestamp { get; set; }
            public List<Transaction> Transactions { get; set; } = new List<Transaction>();
            public int Nonce { get; set; }
        }

        public async Task<string> CreateTransaction(string from, string to, BigInteger amount, string privateKey)
        {
            if (string.IsNullOrEmpty(from) || string.IsNullOrEmpty(to) || amount <= 0)
            {
                throw new ArgumentException("Invalid transaction parameters");
            }

            var transaction = new Transaction
            {
                From = from,
                To = to,
                Amount = amount,
                Timestamp = DateTime.UtcNow
            };

            // Generate transaction hash
            transaction.TransactionHash = ComputeTransactionHash(transaction);

            // Sign the transaction
            transaction.Signature = SignTransaction(transaction.TransactionHash, privateKey);

            lock (_lock)
            {
                _pendingTransactions.Add(transaction);
            }

            return transaction.TransactionHash;
        }

        public async Task<Block> MineBlock(string minerAddress)
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
                PreviousHash = _blockchain.Count == 0 ? "0" : _blockchain.Last().Hash,
                Timestamp = DateTime.UtcNow,
                Transactions = transactionsToMine
            };

            // Proof of Work
            block.Hash = ComputeBlockHash(block);
            block.Nonce = await MineProofOfWork(block);

            // Reward the miner
            var rewardTransaction = new Transaction
            {
                From = "0",
                To = minerAddress,
                Amount = 10,
                Timestamp = DateTime.UtcNow
            };
            rewardTransaction.TransactionHash = ComputeTransactionHash(rewardTransaction);
            block.Transactions.Add(rewardTransaction);

            lock (_lock)
            {
                _blockchain.Add(block);
                UpdateBalances(block);
            }

            return block;
        }

        private string ComputeTransactionHash(Transaction transaction)
        {
            var data = $"{transaction.From}{transaction.To}{transaction.Amount}{transaction.Timestamp}";
            using (var sha256 = SHA256.Create())
            {
                var hashBytes = sha256.ComputeHash(Encoding.UTF8.GetBytes(data));
                return BitConverter.ToString(hashBytes).Replace("-", "").ToLower();
            }
        }

        private string SignTransaction(string transactionHash, string privateKey)
        {
            // In a real implementation, this would use proper ECDSA signing
            using (var sha256 = SHA256.Create())
            {
                var hashBytes = sha256.ComputeHash(Encoding.UTF8.GetBytes(transactionHash + privateKey));
                return BitConverter.ToString(hashBytes).Replace("-", "").ToLower();
            }
        }

        private string ComputeBlockHash(Block block)
        {
            var data = $"{block.Index}{block.PreviousHash}{block.Timestamp}{string.Join("", block.Transactions.Select(t => t.TransactionHash))}{block.Nonce}";
            using (var sha256 = SHA256.Create())
            {
                var hashBytes = sha256.ComputeHash(Encoding.UTF8.GetBytes(data));
                return BitConverter.ToString(hashBytes).Replace("-", "").ToLower();
            }
        }

        private async Task<int> MineProofOfWork(Block block)
        {
            return await Task.Run(() =>
            {
                int nonce = 0;
                string hash;
                do
                {
                    block.Nonce = nonce;
                    hash = ComputeBlockHash(block);
                    nonce++;
                } while (!hash.StartsWith("0000"));
                return nonce - 1;
            });
        }

        private void UpdateBalances(Block block)
        {
            foreach (var transaction in block.Transactions)
            {
                if (transaction.From != "0") // Not a mining reward
                {
                    if (_balances.ContainsKey(transaction.From))
                    {
                        _balances[transaction.From] -= transaction.Amount;
                    }
                }

                if (_balances.ContainsKey(transaction.To))
                {
                    _balances[transaction.To] += transaction.Amount;
                }
                else
                {
                    _balances[transaction.To] = transaction.Amount;
                }
            }
        }

        public BigInteger GetBalance(string address)
        {
            lock (_lock)
            {
                return _balances.ContainsKey(address) ? _balances[address] : 0;
            }
        }

        public List<Block> GetBlockchain()
        {
            lock (_lock)
            {
                return new List<Block>(_blockchain);
            }
        }
    }
}