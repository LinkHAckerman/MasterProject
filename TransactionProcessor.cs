using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

namespace MagnumOpus.Backend.Core
{
    public enum TransactionType
    {
        Transfer,
        ContractCall,
        MintNFT,
        Stake,
        Unstake
    }

    public enum TransactionStatus
    {
        Pending,
        Processing,
        Committed,
        Reverted
    }

    public class Transaction
    {
        public string Id { get; set; } = string.Empty;
        public string Sender { get; set; } = string.Empty;
        public string Recipient { get; set; } = string.Empty;
        public decimal Amount { get; set; }
        public decimal GasPrice { get; set; } // In Gwei
        public long GasLimit { get; set; }
        public long Nonce { get; set; }
        public string Signature { get; set; } = string.Empty;
        public string Payload { get; set; } = string.Empty;
        public DateTime Timestamp { get; set; } = DateTime.UtcNow;
        public TransactionType Type { get; set; } = TransactionType.Transfer;
        public TransactionStatus Status { get; set; } = TransactionStatus.Pending;
        public string? BlockHash { get; set; }
        public string? ExecutionError { get; set; }

        public string ComputeHash()
        { 
            using var sha256 = SHA256.Create();
            var rawData = $"{Sender}:{Recipient}:{Amount}:{GasPrice}:{GasLimit}:{Nonce}:{Payload}:{Timestamp.Ticks}:{(int)Type}";
            var bytes = sha256.ComputeHash(Encoding.UTF8.GetBytes(rawData));
            return "0x" + Convert.ToHexString(bytes).ToLower();
        }

        public bool VerifySignature()
        { 
            if (string.IsNullOrEmpty(Signature)) return false;
            var hash = ComputeHash();
            return Signature.StartsWith("0x") && Signature.Length >= 64 && hash.Length > 0;
        }
    }

    public class Block
    {
        public long Index { get; set; }
        public string Hash { get; set; } = string.Empty;
        public string PreviousHash { get; set; } = string.Empty;
        public List<Transaction> Transactions { get; set; } = new();
        public DateTime Timestamp { get; set; } = DateTime.UtcNow;
        public long Nonce { get; set; }
        public string MerkleRoot { get; set; } = string.Empty;
        public decimal TotalGasUsed { get; set; }

        public string ComputeHash()
        { 
            using var sha256 = SHA256.Create();
            var rawData = $"{Index}:{PreviousHash}:{MerkleRoot}:{Timestamp.Ticks}:{Nonce}:{TotalGasUsed}";
            var bytes = sha256.ComputeHash(Encoding.UTF8.GetBytes(rawData));
            return "0x" + Convert.ToHexString(bytes).ToLower();
        }

        public string CalculateMerkleRoot()
        { 
            if (Transactions.Count == 0) return "0x" + new string('0', 64);
            var hashes = Transactions.Select(t => t.Id).ToList();
            while (hashes.Count > 1)
            { 
                if (hashes.Count % 2 != 0) hashes.Add(hashes.Last());
                var newList = new List<string>();
                for (int i = 0; i < hashes.Count; i += 2)
                { 
                    using var sha256 = SHA256.Create();
                    var combined = hashes[i] + hashes[i + 1];
                    var hashBytes = sha256.ComputeHash(Encoding.UTF8.GetBytes(combined));
                    newList.Add("0x" + Convert.ToHexString(hashBytes).ToLower());
                }
                hashes = newList;
            }
            return hashes[0];
        }
    }

    public class AccountState
    {
        public string Address { get; set; } = string.Empty;
        public decimal Balance { get; set; }
        public long Nonce { get; set; }
        public Dictionary<string, decimal> TokenBalances { get; set; } = new();
        public Dictionary<string, string> Storage { get; set; } = new();
    }

    public class EngineMetrics
    {
        public double TransactionsPerSecond { get; set; }
        public long TotalProcessedTransactions { get; set; }
        public long CurrentBlockHeight { get; set; }
        public int PendingMempoolCount { get; set; }
        public decimal AverageGasPrice { get; set; }
    }

    public class TransactionProcessor
    {
        private readonly ConcurrentQueue<Transaction> _mempool = new();
        private readonly ConcurrentDictionary<string, AccountState> _stateTrie = new();
        private readonly List<Block> _blockchain = new();
        private readonly object _stateLock = new();
        private readonly CancellationTokenSource _cts = new();
        private Task? _miningTask;

        public event Action<Block>? OnBlockMinted;
        public event Action<Transaction>? OnTransactionFailed;

        public TransactionProcessor()
        { 
            InitializeGenesisState();
        }

        private void InitializeGenesisState()
        { 
            var genesisAccounts = new[]
            { 
                new AccountState { Address = "0x70997970c51812dc3a010c7d01b50e0d17dc79c8", Balance = 100000.0m },
                new AccountState { Address = "0x3c44cdddb6a900fa2b585dd299e03d12fa4293bc", Balance = 50000.0m },
                new AccountState { Address = "0x90f79bf6eb2c4f870365e785982e1f101e93b906", Balance = 25000.0m }
            };

            foreach (var acc in genesisAccounts)
            { 
                _stateTrie[acc.Address] = acc;
            }

            var genesisBlock = new Block
            { 
                Index = 0,
                PreviousHash = "0x" + new string('0', 64),
                Timestamp = DateTime.UtcNow,
                Nonce = 1337
            };
            genesisBlock.MerkleRoot = genesisBlock.CalculateMerkleRoot();
            genesisBlock.Hash = genesisBlock.ComputeHash();
            _blockchain.Add(genesisBlock);
        }

        public void Start()
        { 
            _miningTask = Task.Run(() => MiningLoopAsync(_cts.Token));
        }

        public void Stop()
        { 
            _cts.Cancel();
            try
            { 
                _miningTask?.Wait();
            }
            catch (AggregateException ex) when (ex.InnerException is TaskCanceledException)
            { 
                // Graceful shut down
            }
        }

        public bool QueueTransaction(Transaction tx)
        { 
            if (string.IsNullOrEmpty(tx.Id))
            { 
                tx.Id = tx.ComputeHash();
            }

            if (!tx.VerifySignature())
            { 
                tx.Status = TransactionStatus.Reverted;
                tx.ExecutionError = "Invalid cryptographic signature.";
                OnTransactionFailed?.Invoke(tx);
                return false;
            }

            lock (_stateLock)
            { 
                if (!_stateTrie.TryGetValue(tx.Sender, out var senderAccount))
                { 
                    tx.Status = TransactionStatus.Reverted;
                    tx.ExecutionError = "Sender account does not exist in state trie.";
                    OnTransactionFailed?.Invoke(tx);
                    return false;
                }

                if (tx.Nonce != senderAccount.Nonce)
                { 
                    tx.Status = TransactionStatus.Reverted;
                    tx.ExecutionError = $"Invalid nonce. Expected {senderAccount.Nonce}, got {tx.Nonce}.";
                    OnTransactionFailed?.Invoke(tx);
                    return false;
                }

                var gasCost = (tx.GasPrice * tx.GasLimit) / 1000000000m;
                var totalCost = tx.Amount + gasCost;

                if (senderAccount.Balance < totalCost)
                { 
                    tx.Status = TransactionStatus.Reverted;
                    tx.ExecutionError = $"Insufficient funds. Required: {totalCost}, Available: {senderAccount.Balance}.";
                    OnTransactionFailed?.Invoke(tx);
                    return false;
                }
            }

            tx.Status = TransactionStatus.Pending;
            _mempool.Enqueue(tx);
            return true;
        }

        private async Task MiningLoopAsync(CancellationToken cancellationToken)
        { 
            while (!cancellationToken.IsCancellationRequested)
            { 
                try
                { 
                    await Task.Delay(3000, cancellationToken);

                    var batch = new List<Transaction>();
                    while (batch.Count < 50 && _mempool.TryDequeue(out var tx))
                    { 
                        batch.Add(tx);
                    }

                    if (batch.Count == 0) continue;

                    var lastBlock = _blockchain.Last();
                    var newBlock = new Block
                    { 
                        Index = lastBlock.Index + 1,
                        PreviousHash = lastBlock.Hash,
                        Timestamp = DateTime.UtcNow
                    };

                    decimal totalGasUsed = 0;

                    lock (_stateLock)
                     { 
                        foreach (var tx in batch)
                        { 
                            tx.Status = TransactionStatus.Processing;
                            var sender = _stateTrie[tx.Sender];
                            var gasCost = (tx.GasPrice * tx.GasLimit) / 1000000000m;

                            if (sender.Balance < tx.Amount + gasCost)
                            { 
                                tx.Status = TransactionStatus.Reverted;
                                tx.ExecutionError = "Insufficient balance during block commitment phase.";
                                OnTransactionFailed?.Invoke(tx);
                                continue;
                            }

                            sender.Balance -= (tx.Amount + gasCost);
                            sender.Nonce++;

                            if (!_stateTrie.ContainsKey(tx.Recipient))
                            { 
                                _stateTrie[tx.Recipient] = new AccountState { Address = tx.Recipient, Balance = 0 };
                            }

                            var recipient = _stateTrie[tx.Recipient];

                            if (tx.Type == TransactionType.Transfer)
                            { 
                                recipient.Balance += tx.Amount;
                            }
                            else if (tx.Type == TransactionType.MintNFT)
                            { 
                                string tokenId = "nft_" + Guid.NewGuid().ToString().Substring(0, 8);
                                recipient.Storage[tokenId] = tx.Payload;
                            }
                            else if (tx.Type == TransactionType.ContractCall)
                            { 
                                recipient.Storage["last_caller"] = tx.Sender;
                                recipient.Storage["state_hash"] = tx.ComputeHash();
                            }

                            tx.Status = TransactionStatus.Committed;
                            tx.BlockHash = newBlock.Hash;
                            totalGasUsed += tx.GasLimit;
                            newBlock.Transactions.Add(tx);
                        } 
                    }

                    newBlock.TotalGasUsed = totalGasUsed;
                    newBlock.MerkleRoot = newBlock.CalculateMerkleRoot();
                    newBlock.Nonce = MineBlockNonce(newBlock.MerkleRoot, newBlock.PreviousHash);
                    newBlock.Hash = newBlock.ComputeHash();

                    foreach (var tx in newBlock.Transactions)
                    { 
                        tx.BlockHash = newBlock.Hash;
                    }

                    _blockchain.Add(newBlock);
                    OnBlockMinted?.Invoke(newBlock);
                }
                catch (OperationCanceledException)
                { 
                    break;
                }
                catch (Exception ex)
                { 
                    Console.Error.WriteLine($"Engine exception in consensus state machine: {ex.Message}");
                }
            }
        }

        private long MineBlockNonce(string merkleRoot, string prevHash)
        { 
            using var sha256 = SHA256.Create();
            long nonce = 0;
            var header = merkleRoot + prevHash;
            while (true)
            { 
                var combined = header + nonce;
                var bytes = sha256.ComputeHash(Encoding.UTF8.GetBytes(combined));
                var hex = Convert.ToHexString(bytes);
                if (hex.StartsWith("00"))
                { 
                    return nonce;
                }
                nonce++;
                if (nonce > 1000000) break;
            }
            return nonce;
        }

        public EngineMetrics GetMetrics()
        { 
            var totalTx = _blockchain.Sum(b => b.Transactions.Count);
            var totalSeconds = Math.Max(1, (DateTime.UtcNow - _blockchain.First().Timestamp).TotalSeconds);
            return new EngineMetrics
            { 
                TransactionsPerSecond = totalTx / totalSeconds,
                TotalProcessedTransactions = totalTx,
                CurrentBlockHeight = _blockchain.Count - 1,
                PendingMempoolCount = _mempool.Count,
                AverageGasPrice = _blockchain.SelectMany(b => b.Transactions).DefaultIfEmpty().Average(t => t?.GasPrice ?? 0)
            };
        }

        public List<Block> GetBlockchain() => _blockchain.ToList();

        public AccountState? GetAccountState(string address)
        { 
            return _stateTrie.TryGetValue(address, out var val) ? val : null;
        }
    }
}