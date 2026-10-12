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

    public sealed class NodeStats
    {
        public long ChainHeight { get; set; }
        public int PendingTransactions { get; set; }
        public int ProcessedTransactions { get; set; }
        public DateTime LastBlockTimestamp { get; set; }
        public double HashRate { get; set; } // hashes per second
        public string NodeVersion { get; set; } = "1.0.0";
    }

    #endregion

    /// <summary>
    /// Core transaction processor that validates, queues, and mines transactions into blocks.
    /// Designed for high‑throughput demo environments; replace placeholder crypto with real libs for production.
    /// </summary>
    public class TransactionProcessor : IDisposable
    {
        private readonly ConcurrentQueue<Transaction> _pendingQueue = new();
        private readonly ConcurrentDictionary<string, TransactionReceipt> _receipts = new();
        private readonly TimeSpan _blockInterval = TimeSpan.FromSeconds(10);
        private readonly CancellationTokenSource _cts = new();
        private readonly Task _backgroundTask;
        private readonly object _blockLock = new();

        // Simple mutable state for demo purposes
        private long _currentBlockIndex = 0;
        private string _lastBlockHash = string.Empty;
        private DateTime _lastBlockTime = DateTime.UtcNow;
        private int _currentDifficulty = 2; // adjustable difficulty for PoW demo
        private string _minerAddress = "MAGNUM_MINER";

        public TransactionProcessor()
        {
            _backgroundTask = Task.Run(ProcessLoopAsync);
        }

        /// <summary>
        /// Submits a new transaction for processing. Performs basic validation, assigns a nonce if missing,
        /// and generates a placeholder signature.
        /// </summary>
        public async Task<string> SubmitTransactionAsync(Transaction tx)
        {
            var validation = ValidateTransaction(tx);
            if (!validation.IsValid)
                throw new InvalidOperationException(validation.ErrorMessage);

            if (tx.Nonce == 0)
                tx.Nonce = await GetNextNonceAsync(tx.Sender);

            tx.Signature = ComputeSignature(tx);
            _pendingQueue.Enqueue(tx);
            return tx.Id;
        }

        private async Task<ulong> GetNextNonceAsync(string address)
        {
            // In a real implementation this would query persistent storage.
            await Task.Yield();
            return (ulong)DateTimeOffset.UtcNow.ToUnixTimeSeconds();
        }

        private string ComputeSignature(Transaction tx)
        {
            // Placeholder: SHA‑256 hash of the raw payload.
            var payload = tx.GetRawPayloadBytes();
            using var sha = SHA256.Create();
            var hash = sha.ComputeHash(payload);
            return Convert.ToHexString(hash);
        }

        public (bool IsValid, string ErrorMessage) ValidateTransaction(Transaction tx)
        {
            if (string.IsNullOrWhiteSpace(tx.Id))
                return (false, "Transaction Id is required.");
            if (string.IsNullOrWhiteSpace(tx.Sender) || string.IsNullOrWhiteSpace(tx.Recipient))
                return (false, "Sender and recipient must be provided.");
            if (tx.Amount <= 0)
                return (false, "Amount must be greater than zero.");
            if (tx.Fee < 0)
                return (false, "Fee cannot be negative.");
            // Additional checks such as balance verification, signature validation, etc., can be added here.
            return (true, string.Empty);
        }

        private async Task ProcessLoopAsync()
        {
            while (!_cts.IsCancellationRequested)
            {
                var start = DateTime.UtcNow;
                await ProcessPendingTransactionsAsync();
                var elapsed = DateTime.UtcNow - start;
                var delay = _blockInterval - elapsed;
                if (delay > TimeSpan.Zero)
                    await Task.Delay(delay, _cts.Token);
            }
        }

        private async Task ProcessPendingTransactionsAsync()
        {
            var block = new Block
            {
                Index = Interlocked.Increment(ref _currentBlockIndex),
                Timestamp = DateTime.UtcNow,
                PreviousHash = _lastBlockHash,
                Difficulty = _currentDifficulty,
                MinerAddress = _minerAddress,
                Transactions = new List<Transaction>()
            };

            while (_pendingQueue.TryDequeue(out var tx))
            {
                // In a production system you would verify signatures, balances, etc.
                block.Transactions.Add(tx);
            }

            block.MerkleRoot = ComputeMerkleRoot(block.Transactions);
            block.Nonce = await MineBlockAsync(block);
            block.Hash = ComputeBlockHash(block);

            lock (_blockLock)
            {
                _lastBlockHash = block.Hash;
                _lastBlockTime = block.Timestamp;
            }

            foreach (var tx in block.Transactions)
            {
                var receipt = new TransactionReceipt
                {
                    TransactionId = tx.Id,
                    BlockIndex = block.Index,
                    BlockHash = block.Hash,
                    GasUsed = 21000, // placeholder gas usage
                    FeePaid = tx.Fee,
                    Status = TransactionStatus.Confirmed,
                    Timestamp = DateTime.UtcNow,
                    ExecutionMessage = "Executed successfully"
                };
                _receipts[tx.Id] = receipt;
                tx.Status = TransactionStatus.Confirmed;
            }

            // Simulate async persistence or event publishing.
            await Task.Yield();
        }

        private string ComputeMerkleRoot(List<Transaction> txs)
        {
            if (txs.Count == 0) return string.Empty;
            using var sha = SHA256.Create();
            var concatenated = string.Concat(txs.Select(t => t.Id));
            var hash = sha.ComputeHash(Encoding.UTF8.GetBytes(concatenated));
            return Convert.ToHexString(hash);
        }

        private async Task<ulong> MineBlockAsync(Block block)
        {
            // Very naive proof‑of‑work: find a hash with leading zeros equal to difficulty.
            ulong nonce = 0;
            using var sha = SHA256.Create();
            while (true)
            {
                block.Nonce = nonce;
                var hash = ComputeBlockHash(block);
                if (hash.StartsWith(new string('0', block.Difficulty)))
                    return nonce;
                nonce++;
                if (nonce % 1_000_000 == 0)
                    await Task.Yield(); // keep the thread cooperative
            }
        }

        private string ComputeBlockHash(Block block)
        {
            var sb = new StringBuilder();
            sb.Append(block.Index);
            sb.Append(block.Timestamp.ToString("O"));
            sb.Append(block.PreviousHash);
            sb.Append(block.MerkleRoot);
            sb.Append(block.Nonce);
            sb.Append(block.MinerAddress);
            sb.Append(block.Difficulty);
            using var sha = SHA256.Create();
            var hash = sha.ComputeHash(Encoding.UTF8.GetBytes(sb.ToString()));
            return Convert.ToHexString(hash);
        }

        public TransactionReceipt? GetReceipt(string transactionId)
        {
            _receipts.TryGetValue(transactionId, out var receipt);
            return receipt;
        }

        public void Stop()
        {
            _cts.Cancel();
            _backgroundTask.Wait();
        }

        public void Dispose()
        {
            Stop();
            _cts.Dispose();
        }
    }
}
