using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using System.Numerics;
using System.Security.Cryptography;
using System.Text;

namespace MagnumOpus.Backend.Core
{
    public class TransactionProcessor
    {
        private readonly Dictionary<string, BigInteger> _balances = new Dictionary<string, BigInteger>();
        private readonly List<Transaction> _pendingTransactions = new List<Transaction>();
        private readonly List<Block> _blockchain = new List<Block>();
        private readonly int _difficulty = 4;
        private readonly object _lock = new object();

        public class Transaction
        {
            public string FromAddress { get; set; }
            public string ToAddress { get; set; }
            public BigInteger Amount { get; set; }
            public string Signature { get; set; }
            public string TransactionId { get; set; }

            public Transaction(string from, string to, BigInteger amount)
            {
                FromAddress = from;
                ToAddress = to;
                Amount = amount;
                TransactionId = ComputeTransactionId();
            }

            private string ComputeTransactionId()
            {
                using (SHA256 sha256 = SHA256.Create())
                {
                    byte[] hashBytes = sha256.ComputeHash(Encoding.UTF8.GetBytes($"{FromAddress}{ToAddress}{Amount}"));
                    return BitConverter.ToString(hashBytes).Replace("-", "").ToLower();
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

            public Block(int index, List<Transaction> transactions, string previousHash)
            {
                Index = index;
                Timestamp = DateTime.UtcNow;
                Transactions = transactions;
                PreviousHash = previousHash;
                Hash = ComputeHash();
            }

            public string ComputeHash()
            {
                using (SHA256 sha256 = SHA256.Create())
                {
                    string transactionData = string.Join("", Transactions.Select(t => t.TransactionId));
                    byte[] hashBytes = sha256.ComputeHash(Encoding.UTF8.GetBytes($"{Index}{Timestamp}{transactionData}{PreviousHash}{Nonce}"));
                    return BitConverter.ToString(hashBytes).Replace("-", "").ToLower();
                }
            }

            public void MineBlock(int difficulty)
            {
                string target = new string('0', difficulty);
                while (Hash.Substring(0, difficulty) != target)
                {
                    Nonce++;
                    Hash = ComputeHash();
                }
            }
        }

        public void AddTransaction(Transaction transaction)
        {
            lock (_lock)
            {
                if (!IsValidTransaction(transaction))
                {
                    throw new InvalidOperationException("Invalid transaction");
                }

                _pendingTransactions.Add(transaction);
            }
        }

        public void MinePendingTransactions(string minerAddress)
        {
            lock (_lock)
            {
                if (_pendingTransactions.Count == 0)
                {
                    return;
                }

                Block newBlock = new Block(_blockchain.Count, _pendingTransactions, GetLatestBlock()?.Hash ?? "0")
                {
                    Nonce = 0
                };

                newBlock.MineBlock(_difficulty);

                _blockchain.Add(newBlock);
                _pendingTransactions.Clear();

                // Reward the miner
                Transaction rewardTransaction = new Transaction("0", minerAddress, 10);
                _pendingTransactions.Add(rewardTransaction);
            }
        }

        public bool IsValidTransaction(Transaction transaction)
        {
            if (transaction.FromAddress == null || transaction.ToAddress == null || transaction.Amount <= 0)
            {
                return false;
            }

            if (!_balances.ContainsKey(transaction.FromAddress) || _balances[transaction.FromAddress] < transaction.Amount)
            {
                return false;
            }

            return true;
        }

        public bool IsChainValid()
        {
            for (int i = 1; i < _blockchain.Count; i++)
            {
                Block currentBlock = _blockchain[i];
                Block previousBlock = _blockchain[i - 1];

                if (currentBlock.Hash != currentBlock.ComputeHash())
                {
                    return false;
                }

                if (currentBlock.PreviousHash != previousBlock.Hash)
                {
                    return false;
                }
            }

            return true;
        }

        public Block GetLatestBlock()
        {
            return _blockchain.LastOrDefault();
        }

        public BigInteger GetBalance(string address)
        {
            lock (_lock)
            {
                return _balances.ContainsKey(address) ? _balances[address] : 0;
            }
        }

        public void UpdateBalance(string address, BigInteger amount)
        {
            lock (_lock)
            {
                if (_balances.ContainsKey(address))
                {
                    _balances[address] += amount;
                }
                else
                {
                    _balances[address] = amount;
                }
            }
        }
    }
}