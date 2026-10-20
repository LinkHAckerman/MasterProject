using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Collections.Immutable;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Threading;
using System.Threading.Tasks;

namespace MagnumOpus.Backend.Core
{
    #region Data Transfer Objects and Entities

    public enum TransactionStatus
    {
        Pending,
        Confirmed,
        Failed,
        Rejected
    }

    public sealed class Transaction
    {
        [JsonPropertyName("id")]
        public string Id { get; set; } = string.Empty;

        [JsonPropertyName("sender")]
        public string Sender { get; set; } = string.Empty;

        [JsonPropertyName("recipient")]
        public string Recipient { get; set; } = string.Empty;

        [JsonPropertyName("amount")]
        public decimal Amount { get; set; }

        [JsonPropertyName("fee")]
        public decimal Fee { get; set; } = 0.0001m;

        [JsonPropertyName("nonce")]
        public ulong Nonce { get; set; }

        [JsonPropertyName("timestamp")]
        public DateTime Timestamp { get; set; } = DateTime.UtcNow;

        [JsonPropertyName("tokenSymbol")]
        public string TokenSymbol { get; set; } = "MOPUS";

        [JsonPropertyName("payload")]
        public string Payload { get; set; } = string.Empty;

        [JsonPropertyName("signature")]
        public string Signature { get; set; } = string.Empty;

        [JsonPropertyName("status")]
        public TransactionStatus Status { get; set; } = TransactionStatus.Pending;

        public override string ToString()
        {
            return $"{Sender}:{Recipient}:{Amount}:{Fee}:{Nonce}:{TokenSymbol}:{Timestamp:O}:{Payload}";
        }

        public byte[] GetRawPayloadBytes()
        {
            return Encoding.UTF8.GetBytes(ToString());
        }
    }

    public sealed class TransactionReceipt
    {
        [JsonPropertyName("transactionId")]
        public string TransactionId { get; set; } = string.Empty;

        [JsonPropertyName("blockIndex")]
        public long BlockIndex { get; set; }

        [JsonPropertyName("blockHash")]
        public string BlockHash { get; set; } = string.Empty;

        [JsonPropertyName("gasUsed")]
        public decimal GasUsed { get; set; }

        [JsonPropertyName("feePaid")]
        public decimal FeePaid { get; set; }

        [JsonPropertyName("status")]
        public TransactionStatus Status { get; set; }

        [JsonPropertyName("timestamp")]
        public DateTime Timestamp { get; set; }

        [JsonPropertyName("executionMessage")]
        public string ExecutionMessage { get; set; } = "Success";
    }

    public sealed class Block
    {
        [JsonPropertyName("index")]
        public long Index { get; set; }

        [JsonPropertyName("timestamp")]
        public DateTime Timestamp { get; set; }

        [JsonPropertyName("transactions")]
        public List<Transaction> Transactions { get; set; } = new List<Transaction>();

        [JsonPropertyName("previousHash")]
        public string PreviousHash { get; set; } = string.Empty;

        [JsonPropertyName("merkleRoot")]
        public string MerkleRoot { get; set; } = string.Empty;

        [JsonPropertyName("nonce")]
        public ulong Nonce { get; set; }

        [JsonPropertyName("hash")]
        public string Hash { get; set; } = string.Empty;

        [JsonPropertyName("minerAddress")]
        public string MinerAddress { get; set; } = string.Empty;

        [JsonPropertyName("difficulty")]
        public int Difficulty { get; set; }
    }

    public sealed class Wallet
    {
        [JsonPropertyName("address")]
        public string Address { get; set; } = string.Empty;

        [JsonPropertyName("publicKey")]
        public string PublicKey { get; set; } = string.Empty;

        [JsonPropertyName("balance")]
        public decimal Balance { get; set; }

        [JsonPropertyName("tokenBalances")]
        public Dictionary<string, decimal> TokenBalances { get; set; } = new Dictionary<string, decimal>(StringComparer.OrdinalIgnoreCase);

        [JsonPropertyName("nonce")]
        public ulong Nonce { get; set; }

        [JsonPropertyName("createdAt")]
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    }

    public sealed class Token
    {
        [JsonPropertyName("symbol")]
        public string Symbol { get; set; } = string.Empty;

        [JsonPropertyName("name")]
        public string Name { get; set; } = string.Empty;

        [JsonPropertyName("decimals")]
        public int Decimals { get; set; } = 18;

        [JsonPropertyName("totalSupply")]
        public decimal TotalSupply { get; set; }

        [JsonPropertyName("owner")]
        public string Owner { get; set; } = string.Empty;
    }

    #endregion

    public sealed class NodeStats
    {
        public long ChainHeight { get; set; }
        public int PendingTransactions { get; set; }
        public int ActiveConnections { get; set; }
        public decimal TotalSupply { get; set; }
        public decimal CirculatingSupply { get; set; }
        public decimal MarketCap { get; set; }
        public decimal CurrentPrice { get; set; }
        public decimal PriceChange24h { get; set; }
        public decimal Volume24h { get; set; }
    }

    public interface ITransactionProcessor
    {
        Task<TransactionReceipt> ProcessTransactionAsync(Transaction transaction, CancellationToken cancellationToken = default);
        Task<Block> MineBlockAsync(CancellationToken cancellationToken = default);
        Task<Block> GetLatestBlockAsync(CancellationToken cancellationToken = default);
        Task<Transaction> GetTransactionAsync(string transactionId, CancellationToken cancellationToken = default);
        Task<TransactionReceipt> GetTransactionReceiptAsync(string transactionId, CancellationToken cancellationToken = default);
        Task<Wallet> GetWalletAsync(string address, CancellationToken cancellationToken = default);
        Task<Token> GetTokenAsync(string symbol, CancellationToken cancellationToken = default);
        Task<NodeStats> GetNodeStatsAsync(CancellationToken cancellationToken = default);
    }

    public sealed class TransactionProcessor : ITransactionProcessor
    {
        private readonly ConcurrentDictionary<string, Transaction> _pendingTransactions = new ConcurrentDictionary<string, Transaction>();
        private readonly ConcurrentDictionary<string, TransactionReceipt> _transactionReceipts = new ConcurrentDictionary<string, TransactionReceipt>();
        private readonly ConcurrentDictionary<string, Block> _blocks = new ConcurrentDictionary<string, Block>();
        private readonly ConcurrentDictionary<string, Wallet> _wallets = new ConcurrentDictionary<string, Wallet>();
        private readonly ConcurrentDictionary<string, Token> _tokens = new ConcurrentDictionary<string, Token>();
        private readonly ConcurrentQueue<Transaction> _transactionQueue = new ConcurrentQueue<Transaction>();
        private readonly ConcurrentQueue<Block> _blockQueue = new ConcurrentQueue<Block>();
        private readonly SemaphoreSlim _miningSemaphore = new SemaphoreSlim(1, 1);
        private readonly SemaphoreSlim _blockSemaphore = new SemaphoreSlim(1, 1);
        private readonly SemaphoreSlim _walletSemaphore = new SemaphoreSlim(1, 1);
        private readonly SemaphoreSlim _tokenSemaphore = new SemaphoreSlim(1, 1);
        private readonly object _blockLock = new object();
        private readonly object _walletLock = new object();
        private readonly object _tokenLock = new object();
        private readonly SHA256 _sha256 = SHA256.Create();
        private readonly Random _random = new Random();
        private readonly NodeStats _nodeStats = new NodeStats();
        private readonly CancellationTokenSource _cancellationTokenSource = new CancellationTokenSource();
        private readonly Task _miningTask;
        private readonly Task _blockTask;
        private readonly Task _walletTask;
        private readonly Task _tokenTask;

        public TransactionProcessor()
        {
            _miningTask = Task.Run(async () => await MiningLoopAsync(_cancellationTokenSource.Token));
            _blockTask = Task.Run(async () => await BlockLoopAsync(_cancellationTokenSource.Token));
            _walletTask = Task.Run(async () => await WalletLoopAsync(_cancellationTokenSource.Token));
            _tokenTask = Task.Run(async () => await TokenLoopAsync(_cancellationTokenSource.Token));
        }

        public async Task<TransactionReceipt> ProcessTransactionAsync(Transaction transaction, CancellationToken cancellationToken = default)
        {
            if (transaction == null)
            {
                throw new ArgumentNullException(nameof(transaction));
            }

            if (string.IsNullOrWhiteSpace(transaction.Id))
            {
                transaction.Id = Guid.NewGuid().ToString();
            }

            if (transaction.Timestamp == default)
            {
                transaction.Timestamp = DateTime.UtcNow;
            }

            if (transaction.Status == TransactionStatus.Pending)
            {
                _pendingTransactions.TryAdd(transaction.Id, transaction);
                _transactionQueue.Enqueue(transaction);
            }

            var receipt = new TransactionReceipt
            {
                TransactionId = transaction.Id,
                Status = transaction.Status,
                Timestamp = DateTime.UtcNow,
                ExecutionMessage = "Transaction processed successfully"
            };

            _transactionReceipts.TryAdd(transaction.Id, receipt);

            return receipt;
        }

        public async Task<Block> MineBlockAsync(CancellationToken cancellationToken = default)
        {
            await _miningSemaphore.WaitAsync(cancellationToken);

            try
            {
                var transactions = new List<Transaction>();
                while (_transactionQueue.TryDequeue(out var transaction))
                {
                    transactions.Add(transaction);
                }

                if (transactions.Count == 0)
                {
                    return null;
                }

                var previousBlock = _blocks.Values.OrderByDescending(b => b.Index).FirstOrDefault();
                var block = new Block
                {
                    Index = previousBlock?.Index + 1 ?? 0,
                    Timestamp = DateTime.UtcNow,
                    Transactions = transactions,
                    PreviousHash = previousBlock?.Hash ?? string.Empty,
                    Nonce = (ulong)_random.Next(),
                    MinerAddress = "0x0000000000000000000000000000000000000000",
                    Difficulty = 4
                };

                block.MerkleRoot = CalculateMerkleRoot(block.Transactions);
                block.Hash = CalculateBlockHash(block);

                _blocks.TryAdd(block.Hash, block);
                _blockQueue.Enqueue(block);

                return block;
            }
            finally
            {
                _miningSemaphore.Release();
            }
        }

        public async Task<Block> GetLatestBlockAsync(CancellationToken cancellationToken = default)
        {
            return _blocks.Values.OrderByDescending(b => b.Index).FirstOrDefault();
        }

        public async Task<Transaction> GetTransactionAsync(string transactionId, CancellationToken cancellationToken = default)
        {
            if (string.IsNullOrWhiteSpace(transactionId))
            {
                throw new ArgumentException("Transaction ID cannot be null or empty", nameof(transactionId));
            }

            if (_pendingTransactions.TryGetValue(transactionId, out var transaction))
            {
                return transaction;
            }

            foreach (var block in _blocks.Values)
            {
                var tx = block.Transactions.FirstOrDefault(t => t.Id == transactionId);
                if (tx != null)
                {
                    return tx;
                }
            }

            return null;
        }

        public async Task<TransactionReceipt> GetTransactionReceiptAsync(string transactionId, CancellationToken cancellationToken = default)
        {
            if (string.IsNullOrWhiteSpace(transactionId))
            {
                throw new ArgumentException("Transaction ID cannot be null or empty", nameof(transactionId));
            }

            if (_transactionReceipts.TryGetValue(transactionId, out var receipt))
            {
                return receipt;
            }

            return null;
        }

        public async Task<Wallet> GetWalletAsync(string address, CancellationToken cancellationToken = default)
        {
            if (string.IsNullOrWhiteSpace(address))
            {
                throw new ArgumentException("Address cannot be null or empty", nameof(address));
            }

            if (_wallets.TryGetValue(address, out var wallet))
            {
                return wallet;
            }

            return null;
        }

        public async Task<Token> GetTokenAsync(string symbol, CancellationToken cancellationToken = default)
        {
            if (string.IsNullOrWhiteSpace(symbol))
            {
                throw new ArgumentException("Symbol cannot be null or empty", nameof(symbol));
            }

            if (_tokens.TryGetValue(symbol, out var token))
            {
                return token;
            }

            return null;
        }

        public async Task<NodeStats> GetNodeStatsAsync(CancellationToken cancellationToken = default)
        {
            return _nodeStats;
        }

        private async Task MiningLoopAsync(CancellationToken cancellationToken)
        {
            while (!cancellationToken.IsCancellationRequested)
            {
                try
                {
                    var block = await MineBlockAsync(cancellationToken);
                    if (block != null)
                    {
                        _nodeStats.ChainHeight = block.Index;
                        _nodeStats.PendingTransactions = _pendingTransactions.Count;
                    }
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"Error in mining loop: {ex.Message}");
                }

                await Task.Delay(1000, cancellationToken);
            }
        }

        private async Task BlockLoopAsync(CancellationToken cancellationToken)
        {
            while (!cancellationToken.IsCancellationRequested)
            {
                try
                {
                    if (_blockQueue.TryDequeue(out var block))
                    {
                        await ProcessBlockAsync(block, cancellationToken);
                    }
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"Error in block loop: {ex.Message}");
                }

                await Task.Delay(1000, cancellationToken);
            }
        }

        private async Task ProcessBlockAsync(Block block, CancellationToken cancellationToken)
        {
            await _blockSemaphore.WaitAsync(cancellationToken);

            try
            {
                foreach (var transaction in block.Transactions)
                {
                    if (transaction.Status == TransactionStatus.Pending)
                    {
                        transaction.Status = TransactionStatus.Confirmed;
                        _pendingTransactions.TryRemove(transaction.Id, out _);
                    }

                    var receipt = new TransactionReceipt
                    {
                        TransactionId = transaction.Id,
                        BlockIndex = block.Index,
                        BlockHash = block.Hash,
                        Status = transaction.Status,
                        Timestamp = DateTime.UtcNow,
                        ExecutionMessage = "Transaction confirmed in block"
                    };

                    _transactionReceipts.AddOrUpdate(transaction.Id, receipt, (key, oldValue) => receipt);
                }
            }
            finally
            {
                _blockSemaphore.Release();
            }
        }

        private async Task WalletLoopAsync(CancellationToken cancellationToken)
        {
            while (!cancellationToken.IsCancellationRequested)
            {
                try
                {
                    await UpdateWalletBalancesAsync(cancellationToken);
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"Error in wallet loop: {ex.Message}");
                }

                await Task.Delay(5000, cancellationToken);
            }
        }

        private async Task UpdateWalletBalancesAsync(CancellationToken cancellationToken)
        {
            await _walletSemaphore.WaitAsync(cancellationToken);

            try
            {
                foreach (var wallet in _wallets.Values)
                {
                    wallet.Balance = 0;
                    wallet.TokenBalances.Clear();

                    foreach (var block in _blocks.Values)
                    {
                        foreach (var transaction in block.Transactions)
                        {
                            if (transaction.Sender == wallet.Address)
                            {
                                wallet.Balance -= transaction.Amount + transaction.Fee;
                            }

                            if (transaction.Recipient == wallet.Address)
                            {
                                wallet.Balance += transaction.Amount;
                            }

                            if (!string.IsNullOrWhiteSpace(transaction.TokenSymbol))
                            {
                                if (transaction.Sender == wallet.Address)
                                {
                                    if (wallet.TokenBalances.TryGetValue(transaction.TokenSymbol, out var balance))
                                    {
                                        wallet.TokenBalances[transaction.TokenSymbol] = balance - transaction.Amount;
                                    }
                                }

                                if (transaction.Recipient == wallet.Address)
                                {
                                    if (wallet.TokenBalances.TryGetValue(transaction.TokenSymbol, out var balance))
                                    {
                                        wallet.TokenBalances[transaction.TokenSymbol] = balance + transaction.Amount;
                                    }
                                    else
                                    {
                                        wallet.TokenBalances[transaction.TokenSymbol] = transaction.Amount;
                                    }
                                }
                            }
                        }
                    }
                }
            }
            finally
            {
                _walletSemaphore.Release();
            }
        }

        private async Task TokenLoopAsync(CancellationToken cancellationToken)
        {
            while (!cancellationToken.IsCancellationRequested)
            {
                try
                {
                    await UpdateTokenSupplyAsync(cancellationToken);
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"Error in token loop: {ex.Message}");
                }

                await Task.Delay(5000, cancellationToken);
            }
        }

        private async Task UpdateTokenSupplyAsync(CancellationToken cancellationToken)
        {
            await _tokenSemaphore.WaitAsync(cancellationToken);

            try
            {
                foreach (var token in _tokens.Values)
                {
                    token.TotalSupply = 0;

                    foreach (var block in _blocks.Values)
                    {
                        foreach (var transaction in block.Transactions)
                        {
                            if (transaction.TokenSymbol == token.Symbol)
                            {
                                token.TotalSupply += transaction.Amount;
                            }
                        }
                    }
                }
            }
            finally
            {
                _tokenSemaphore.Release();
            }
        }

        private string CalculateMerkleRoot(List<Transaction> transactions)
        {
            if (transactions == null || transactions.Count == 0)
            {
                return string.Empty;
            }

            var hashes = transactions.Select(t => CalculateTransactionHash(t)).ToList();

            while (hashes.Count > 1)
            {
                var newHashes = new List<string>();

                for (int i = 0; i < hashes.Count; i += 2)
                {
                    if (i + 1 < hashes.Count)
                    {
                        newHashes.Add(CalculateHash(hashes[i] + hashes[i + 1]));
                    }
                    else
                    {
                        newHashes.Add(hashes[i]);
                    }
                }

                hashes = newHashes;
            }

            return hashes[0];
        }

        private string CalculateTransactionHash(Transaction transaction)
        {
            return CalculateHash(transaction.ToString());
        }

        private string CalculateBlockHash(Block block)
        {
            return CalculateHash($"{block.Index}:{block.Timestamp:O}:{block.PreviousHash}:{block.MerkleRoot}:{block.Nonce}");
        }

        private string CalculateHash(string input)
        {
            var bytes = Encoding.UTF8.GetBytes(input);
            var hashBytes = _sha256.ComputeHash(bytes);
            return BitConverter.ToString(hashBytes).Replace("-", "").ToLower();
        }
    }
}