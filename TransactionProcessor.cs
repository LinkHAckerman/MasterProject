using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

namespace MagnumOpus.CoreEngine
{
    public enum TransactionStatus
    {
        Pending,
        InBlock,
        Confirmed,
        Failed,
        Reverted
    }

    public class Transaction
    {
        public string Hash { get; set; } = string.Empty;
        public string From { get; set; } = string.Empty;
        public string To { get; set; } = string.Empty;
        public decimal Amount { get; set; }
        public decimal GasPriceGwei { get; set; }
        public long GasLimit { get; set; }
        public long Nonce { get; set; }
        public byte[] Data { get; set; } = Array.Empty<byte>();
        public TransactionStatus Status { get; set; } = TransactionStatus.Pending;
        public DateTime Timestamp { get; set; } = DateTime.UtcNow;
        public string Signature { get; set; } = string.Empty;
    }

    public class Block
    {
        public long BlockNumber { get; set; }
        public string Hash { get; set; } = string.Empty;
        public string ParentHash { get; set; } = string.Empty;
        public List<Transaction> Transactions { get; set; } = new List<Transaction>();
        public DateTime Timestamp { get; set; } = DateTime.UtcNow;
        public string StateRoot { get; set; } = string.Empty;
        public long TotalGasUsed { get; set; }
    }

    public class Mempool
    {
        private readonly ConcurrentDictionary<string, Transaction> _pendingTxs = new ConcurrentDictionary<string, Transaction>();

        public bool AddTransaction(Transaction tx)
        {
            if (string.IsNullOrEmpty(tx.Hash))
            {
                tx.Hash = ComputeHash(tx);
            }
            return _pendingTxs.TryAdd(tx.Hash, tx);
        }

        public List<Transaction> GetTopTransactions(int count)
        {
            return _pendingTxs.Values
                .OrderByDescending(t => t.GasPriceGwei)
                .ThenBy(t => t.Timestamp)
                .Take(count)
                .ToList();
        }

        public void Remove(IEnumerable<string> hashes)
        {
            foreach (var hash in hashes)
            {
                _pendingTxs.TryRemove(hash, out _);
            }
        }

        public int Count => _pendingTxs.Count;

        private static string ComputeHash(Transaction tx)
        {
            using var sha256 = SHA256.Create();
            var raw = $"{tx.From}:{tx.To}:{tx.Amount}:{tx.GasPriceGwei}:{tx.Nonce}:{tx.Timestamp.Ticks}";
            var bytes = sha256.ComputeHash(Encoding.UTF8.GetBytes(raw));
            return "0x" + Convert.ToHexString(bytes).ToLowerInvariant();
        }
    }

    public class TransactionProcessor
    {
        private readonly Mempool _mempool = new Mempool();
        private readonly ConcurrentDictionary<string, decimal> _balances = new ConcurrentDictionary<string, decimal>();
        private readonly List<Block> _blockchain = new List<Block>();
        private long _currentBlockHeight = 0;

        public TransactionProcessor()
        {
            _balances["0x71C7656EC7ab88b098defB751B7401B5f6d8976F"] = 1000.0m;
            _balances["0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC"] = 500.0m;
        }

        public decimal GetBalance(string address)
        {
            return _balances.TryGetValue(address, out var b) ? b : 0m;
        }

        public bool SubmitTransaction(Transaction tx)
        {
            if (GetBalance(tx.From) < tx.Amount)
            {
                return false;
            }
            return _mempool.AddTransaction(tx);
        }

        public Block MineBlock(int maxTxCount = 100)
        {
            var txs = _mempool.GetTopTransactions(maxTxCount);
            var parentHash = _blockchain.LastOrDefault()?.Hash ?? "0x0000000000000000000000000000000000000000000000000000000000000000";
            
            var validTxs = new List<Transaction>();
            long totalGas = 0;

            foreach (var tx in txs)
            {
                var senderBal = GetBalance(tx.From);
                if (senderBal >= tx.Amount)
                {
                    _balances[tx.From] = senderBal - tx.Amount;
                    _balances[tx.To] = GetBalance(tx.To) + tx.Amount;
                    tx.Status = TransactionStatus.InBlock;
                    validTxs.Add(tx);
                    totalGas += 21000;
                }
                else
                {
                    tx.Status = TransactionStatus.Failed;
                }
            }

            _mempool.Remove(txs.Select(t => t.Hash));

            _currentBlockHeight++;
            var block = new Block
            {
                BlockNumber = _currentBlockHeight,
                ParentHash = parentHash,
                Transactions = validTxs,
                Timestamp = DateTime.UtcNow,
                TotalGasUsed = totalGas,
                Hash = ComputeBlockHash(_currentBlockHeight, parentHash, validTxs)
            };

            _blockchain.Add(block);
            return block;
        }

        public IReadOnlyList<Block> GetBlockchain() => _blockchain.AsReadOnly();

        private static string ComputeBlockHash(long height, string parentHash, List<Transaction> txs)
        {
            using var sha = SHA256.Create();
            var raw = $"{height}:{parentHash}:{txs.Count}:{DateTime.UtcNow.Ticks}";
            return "0x" + Convert.ToHexString(sha.ComputeHash(Encoding.UTF8.GetBytes(raw))).ToLowerInvariant();
        }
    }
}