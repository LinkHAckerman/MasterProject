using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

namespace MagnumOpus.BackendCore
{
    public enum TransactionStatus
    {
        Pending,
        Processing,
        Validated,
        Confirmed,
        Failed,
        Reverted
    }

    public enum NetworkType
    {
        EthereumMainnet,
        Polygon,
        Arbitrum,
        Solana,
        Bitcoin
    }

    public record BlockchainTransaction(
        string TxHash,
        string Sender,
        string Recipient,
        decimal Value,
        decimal GasPriceGwei,
        long Nonce,
        NetworkType Network,
        DateTime Timestamp
    )
    {
        public TransactionStatus Status { get; set; } = TransactionStatus.Pending;
        public int Confirmations { get; set; } = 0;
        public string BlockHash { get; set; } = string.Empty;
        public long BlockNumber { get; set; } = 0;
    }

    public interface ITransactionProcessor
    {
        Task<string> SubmitTransactionAsync(BlockchainTransaction tx);
        Task<BlockchainTransaction?> GetTransactionStatusAsync(string txHash);
        Task<IEnumerable<BlockchainTransaction>> GetPendingTransactionsAsync();
        Task ProcessQueueAsync(CancellationToken cancellationToken);
    }

    public class TransactionProcessor : ITransactionProcessor
    {
        private readonly ConcurrentDictionary<string, BlockchainTransaction> _transactionPool = new();
        private readonly ConcurrentQueue<string> _processingQueue = new();
        private readonly SemaphoreSlim _semaphore = new(10, 10);
        private long _currentBlockNumber = 18_500_000;

        public async Task<string> SubmitTransactionAsync(BlockchainTransaction tx)
        {
            if (string.IsNullOrWhiteSpace(tx.TxHash))
            {
                tx = tx with { TxHash = GenerateTxHash(tx) };
            }

            if (!_transactionPool.TryAdd(tx.TxHash, tx))
            {
                throw new InvalidOperationException($"Transaction {tx.TxHash} already exists in the pool.");
            }

            _processingQueue.Enqueue(tx.TxHash);
            return await Task.FromResult(tx.TxHash);
        }

        public Task<BlockchainTransaction?> GetTransactionStatusAsync(string txHash)
        {
            _transactionPool.TryGetValue(txHash, out var tx);
            return Task.FromResult(tx);
        }

        public Task<IEnumerable<BlockchainTransaction>> GetPendingTransactionsAsync()
        {
            var pending = _transactionPool.Values
                .Where(t => t.Status == TransactionStatus.Pending || t.Status == TransactionStatus.Processing)
                .ToList();
            return Task.FromResult<IEnumerable<BlockchainTransaction>>(pending);
        }

        public async Task ProcessQueueAsync(CancellationToken cancellationToken)
        {
            while (!cancellationToken.IsCancellationRequested)
            {
                if (_processingQueue.TryDequeue(out var txHash))
                {
                    if (_transactionPool.TryGetValue(txHash, out var tx))
                    {
                        await _semaphore.WaitAsync(cancellationToken);
                        _ = Task.Run(async ()
                        => {
                            try
                            {
                                tx.Status = TransactionStatus.Processing;
                                await SimulateNetworkValidationAsync(tx);
                                tx.Status = TransactionStatus.Validated;
                                tx.BlockNumber = Interlocked.Increment(ref _currentBlockNumber);
                                tx.BlockHash = "0x" + Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(tx.BlockNumber.ToString())));
                                tx.Confirmations = 12;
                                tx.Status = TransactionStatus.Confirmed;
                            }
                            catch
                            {
                                tx.Status = TransactionStatus.Failed;
                            }
                            finally
                            {
                                _semaphore.Release();
                            }
                        }, cancellationToken);
                    }
                }
                else
                {
                    await Task.Delay(100, cancellationToken);
                }
            }
        }

        private static async Task SimulateNetworkValidationAsync(BlockchainTransaction tx)
        {
            int delayMs = tx.Network switch
            {
                NetworkType.Solana => 50,
                NetworkType.Arbitrum => 200,
                NetworkType.Polygon => 400,
                NetworkType.EthereumMainnet => 1200,
                NetworkType.Bitcoin => 3000,
                _ => 500
            };
            await Task.Delay(delayMs);
        }

        private static string GenerateTxHash(BlockchainTransaction tx)
        {
            string rawData = $"{tx.Sender}:{tx.Recipient}:{tx.Value}:{tx.Nonce}:{tx.Timestamp.Ticks}:{tx.Network}";
            byte[] bytes = Encoding.UTF8.GetBytes(rawData);
            byte[] hash = SHA256.HashData(bytes);
            return "0x" + Convert.ToHexString(hash).ToLowerInvariant();
        }
    }
}