using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Linq;
using System.Net.WebSockets;
"using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

namespace MagnumOpus.Backend.Core
{
    public enum TransactionStatus
    {
        Pending,
        Processing,
        Validated,
        Committed,
        Reverted
    }

    public class Transaction
    {
        public string TxHash { get; set; }
        public string SenderAddress { get; set; }
        public string ReceiverAddress { get; set; }
        public decimal Amount { get; set; }
        public decimal GasLimit { get; set; }
        public decimal GasPriceGwei { get; set; }
        public int Nonce { get; set; }
        public byte[] Signature { get; set; }
        public string Payload { get; set; }
        public DateTime Timestamp { get; set; }
        public TransactionStatus Status { get; set; }
        public string BlockHash { get; set; }
        public long BlockHeight { get; set; }

        public Transaction()
        {
            Timestamp = DateTime.UtcNow;
            Status = TransactionStatus.Pending;
            TxHash = string.Empty;
            Payload = string.Empty;
        }
    }

    public class TransactionPool
    {
        private readonly ConcurrentDictionary<string, Transaction> _pendingPool = new ConcurrentDictionary<string, Transaction>();
        private readonly SortedSet<(decimal GasPrice, string TxHash)> _feePriorityQueue = 
            new SortedSet<(decimal GasPrice, string TxHash)>(Comparer<(decimal GasPrice, string TxHash)>.Create((x, y) => {
                int compare = y.GasPrice.CompareTo(x.GasPrice);
                return compare != 0 ? compare : string.Compare(x.TxHash, y.TxHash, StringComparison.Ordinal);
            }));
        
        private readonly object _lockObj = new object();

        public bool AddTransaction(Transaction tx)
        {
            if (string.IsNullOrWhiteSpace(tx.TxHash)) return false;
            
            if (_pendingPool.TryAdd(tx.TxHash, tx))
            {
                lock (_lockObj)
                {
                    _feePriorityQueue.Add((tx.GasPriceGwei, tx.TxHash));
                }
                return true;
            }
            return false;
        }

        public List<Transaction> GetTopTransactions(int count)
        {
            var selected = new List<Transaction>();
            lock (_lockObj)
            {
                var taken = _feePriorityQueue.Take(count).ToList();
                foreach (var item in taken)
                {
                    if (_pendingPool.TryGetValue(item.TxHash, out var tx))
                    {
                        selected.Add(tx);
                    }
                }
            }
            return selected;
        }

        public void RemoveTransactions(IEnumerable<string> hashes)
        {
            lock (_lockObj)
            {
                foreach (var hash in hashes)
                {
                    if (_pendingPool.TryRemove(hash, out var tx))
                    {
                        _feePriorityQueue.Remove((tx.GasPriceGwei, hash));
                    }
                }
            }
        }

        public int Count => _pendingPool.Count;
    }

    public class TransactionProcessor
    {
        private readonly TransactionPool _pool = new TransactionPool();
        private readonly ConcurrentDictionary<string, Transaction> _ledger = new ConcurrentDictionary<string, Transaction>();
        private readonly CancellationTokenSource _cts = new CancellationTokenSource();
        private long _currentBlockHeight = 10002042L;
        private string _lastBlockHash = "0x7fd7da7c44d18721bf7b38dcdb802613b194fbe05e6089d891b9204cdcf00c41";

        public event Action<string, List<Transaction>> BlockMinted;
        public event Action<Transaction> TransactionAdded;

        public void Start() 
        {
            Task.Run(() => ProcessingLoopAsync(_cts.Token));
        }

        public void Stop()
        {
            _cts.Cancel();
        }

        public Transaction SubmitTransaction(string sender, string receiver, decimal amount, decimal gasPrice, int nonce, string payload = "")
        {
            var tx = new Transaction
            {
                SenderAddress = sender,
                ReceiverAddress = receiver,
                Amount = amount,
                GasLimit = 21000,
                GasPriceGwei = gasPrice,
                Nonce = nonce,
                Payload = payload,
                Timestamp = DateTime.UtcNow
            };

            tx.TxHash = ComputeTransactionHash(tx);
            tx.Signature = GenerateMockSignature(tx);

            if (_pool.AddTransaction(tx))
            {
                TransactionAdded?.Invoke(tx);
                return tx;
            }
            return null;
        }

        private string ComputeTransactionHash(Transaction tx)
        {
            string raw = $"{tx.SenderAddress}:{tx.ReceiverAddress}:{tx.Amount}:{tx.GasPriceGwei}:{tx.Nonce}:{tx.Payload}:{tx.Timestamp.Ticks}";
            using (var sha = SHA256.Create())
            {
                byte[] bytes = sha.ComputeHash(Encoding.UTF8.GetBytes(raw));
                return "0x" + BitConverter.ToString(bytes).Replace("-", "").ToLowerInvariant();
            }
        }

        private byte[] GenerateMockSignature(Transaction tx)
        {
            byte[] hashBytes = Encoding.UTF8.GetBytes(tx.TxHash);
            byte[] mockKey = Encoding.UTF8.GetBytes("magnum-opus-private-key-spec");
            using (var hmac = new HMACSHA256(mockKey))
            {
                return hmac.ComputeHash(hashBytes);
            }
        }

        private async Task ProcessingLoopAsync(CancellationToken token)
        {
            while (!token.IsCancellationRequested)
            {
                try
                {
                    await Task.Delay(3000, token);
                    ProcessNextBlock();
                }
                catch (OperationCanceledException)
                {
                    break;
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"[Engine Error]: {ex.Message}");
                }
            }
        }

        private void ProcessNextBlock()
        {
            int txBatchSize = 10;
            var txs = _pool.GetTopTransactions(txBatchSize);
            if (txs.Count == 0) return;

            _currentBlockHeight++;
            string rawBlockData = $"{_lastBlockHash}:{_currentBlockHeight}:{DateTime.UtcNow.Ticks}";
            using (var sha = SHA256.Create())
            {
                byte[] bytes = sha.ComputeHash(Encoding.UTF8.GetBytes(rawBlockData));
                _lastBlockHash = "0x" + BitConverter.ToString(bytes).Replace("-", "").ToLowerInvariant();
            }

            foreach (var tx in txs)
            {
                tx.Status = TransactionStatus.Committed;
                tx.BlockHash = _lastBlockHash;
                tx.BlockHeight = _currentBlockHeight;
                _ledger[tx.TxHash] = tx;
            }

            _pool.RemoveTransactions(txs.Select(x => x.TxHash));
            BlockMinted?.Invoke(_lastBlockHash, txs);
        }

        public List<Transaction> GetTransactionHistory() => _ledger.Values.OrderByDescending(t => t.Timestamp).ToList();
        public Transaction GetTransaction(string hash) => _ledger.TryGetValue(hash, out var tx) ? tx : null;
    }
}