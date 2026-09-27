using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Threading.Channels;
using System.Threading.Tasks;

namespace MagnumOpus.BackendCore
{
    public enum TransactionStatus
    {
        Pending,
        Validated,
        Processing,
        Committed,
        Failed,
        Reverted
    }

    public enum TransactionType
    {
        Transfer,
        SmartContractDeploy,
        SmartContractCall,
        DeFiSwap,
        LiquidityAdd,
        NFTMint,
        CrossChainBridge
    }

    public record Transaction(
        string TxHash,
        string FromAddress,
        string ToAddress,
        decimal Amount,
        decimal GasPriceGwei,
        long GasLimit,
        long Nonce,
        TransactionType Type,
        byte[] Payload,
        DateTime CreatedAt
    )
    {
        public TransactionStatus Status { get; set; } = TransactionStatus.Pending;
        public string? FailureReason { get; set; }
        public string? ExecutionReceiptHash { get; set; }
        public long GasUsed { get; set; }
        public decimal TotalFeeEth => (GasUsed * GasPriceGwei) / 1_000_000_000m;
    }

    public record ExecutionResult(
        bool Success,
        string TxHash,
        long GasUsed,
        string? ReceiptHash,
        string? ErrorMessage,
        IReadOnlyList<string> EventLogs
    );

    public interface ITransactionProcessor
    {
        Task<bool> SubmitTransactionAsync(Transaction tx, CancellationToken cancellationToken = default);
        Task<Transaction?> GetTransactionStatusAsync(string txHash);
        Task<int> GetMempoolCountAsync();
        event EventHandler<TransactionStatusChangedEventArgs>? OnTransactionStatusChanged;
    }

    public class TransactionStatusChangedEventArgs : EventArgs
    {
        public string TxHash { get; }
        public TransactionStatus NewStatus { get; }
        public string? Details { get; }

        public TransactionStatusChangedEventArgs(string txHash, TransactionStatus newStatus, string? details = null)
        {
            TxHash = txHash;
            NewStatus = newStatus;
            Details = details;
        }
    }

    public class TransactionProcessor : ITransactionProcessor, IAsyncDisposable
    {
        private readonly ConcurrentDictionary<string, Transaction> _mempool = new();
        private readonly ConcurrentDictionary<string, Transaction> _processedHistory = new();
        private readonly ConcurrentDictionary<string, long> _accountNonces = new();
        private readonly ConcurrentDictionary<string, decimal> _accountBalances = new();

        private readonly Channel<Transaction> _txQueue;
        private readonly CancellationTokenSource _cts = new();
        private readonly List<Task> _workerTasks = new();
        private readonly int _maxWorkers;
        private readonly object _stateLock = new();

        public event EventHandler<TransactionStatusChangedEventArgs>? OnTransactionStatusChanged;

        public TransactionProcessor(int maxWorkers = 4, int queueCapacity = 10_000)
        {
            _maxWorkers = Math.Max(1, maxWorkers);
            var channelOptions = new BoundedChannelOptions(queueCapacity)
            {
                FullMode = BoundedChannelFullMode.Wait,
                SingleReader = false,
                SingleWriter = false
            };
            _txQueue = Channel.CreateBounded<Transaction>(channelOptions);

            InitializeMockAccounts();
            StartWorkers();
        }

        private void InitializeMockAccounts()
        {
            _accountBalances["0x71C7656EC7ab88b098defB751B7401B5f6d8976F"] = 1000.0m;
            _accountBalances["0x3C44CdD470384CF11026808DE22222E42b6a224a"] = 500.0m;
            _accountBalances["0x90F79bf6EB2c4f870365E785982E1f101E93b906"] = 250000.0m;

            _accountNonces["0x71C7656EC7ab88b098defB751B7401B5f6d8976F"] = 0;
            _accountNonces["0x3C44CdD470384CF11026808DE22222E42b6a224a"] = 0;
            _accountNonces["0x90F79bf6EB2c4f870365E785982E1f101E93b906"] = 0;
        }

        private void StartWorkers()
        {
            for (int i = 0; i < _maxWorkers; i++)
            {
                int workerId = i;
                _workerTasks.Add(Task.Run(() => ProcessingWorkerLoopAsync(workerId, _cts.Token)));
            }
        }

        public async Task<bool> SubmitTransactionAsync(Transaction tx, CancellationToken cancellationToken = default)
        {
            if (string.IsNullOrWhiteSpace(tx.TxHash))
                throw new ArgumentException("Transaction hash must not be empty.", nameof(tx));

            if (!ValidateSignatureAndHash(tx))
            {
                tx.Status = TransactionStatus.Failed;
                tx.FailureReason = "Invalid transaction hash or cryptographic signature format.";
                _processedHistory[tx.TxHash] = tx;
                RaiseStatusChanged(tx.TxHash, TransactionStatus.Failed, tx.FailureReason);
                return false;
            }

            if (!_mempool.TryAdd(tx.TxHash, tx))
            {
                return false;
            }

            tx.Status = TransactionStatus.Pending;
            RaiseStatusChanged(tx.TxHash, TransactionStatus.Pending, "Enqueued in mempool.");

            await _txQueue.Writer.WriteAsync(tx, cancellationToken);
            return true;
        }

        public Task<Transaction?> GetTransactionStatusAsync(string txHash)
        {
            if (_mempool.TryGetValue(txHash, out var pendingTx))
            {
                return Task.FromResult<Transaction?>(pendingTx);
            }

            if (_processedHistory.TryGetValue(txHash, out var processedTx))
            {
                return Task.FromResult<Transaction?>(processedTx);
            }

            return Task.FromResult<Transaction?>(null);
        }

        public Task<int> GetMempoolCountAsync()
        {
            return Task.FromResult(_mempool.Count);
        }

        private async Task ProcessingWorkerLoopAsync(int workerId, CancellationToken cancellationToken)
        {
            var reader = _txQueue.Reader;

            while (await reader.WaitToReadAsync(cancellationToken))
            {
                while (reader.TryRead(out var tx))
                {
                    if (cancellationToken.IsCancellationRequested) break;

                    await ProcessSingleTransactionAsync(tx, workerId);
                }
            }
        }

        private async Task ProcessSingleTransactionAsync(Transaction tx, int workerId)
        {
            tx.Status = TransactionStatus.Processing;
            RaiseStatusChanged(tx.TxHash, TransactionStatus.Processing, $"Worker #{workerId} execution started.");

            var validationError = PreValidateState(tx);
            if (validationError != null)
            {
                FinalizeTransaction(tx, false, 21000, null, validationError);
                return;
            }

            await Task.Delay(15);

            ExecutionResult result = tx.Type switch
            {
                TransactionType.Transfer => ExecuteTransfer(tx),
                TransactionType.DeFiSwap => ExecuteDeFiSwap(tx),
                TransactionType.SmartContractCall => ExecuteContractCall(tx),
                TransactionType.NFTMint => ExecuteNFTMint(tx),
                TransactionType.CrossChainBridge => ExecuteBridgeRelay(tx),
                _ => ExecuteGenericTransaction(tx)
            };

            FinalizeTransaction(tx, result.Success, result.GasUsed, result.ReceiptHash, result.ErrorMessage);
        }

        private string? PreValidateState(Transaction tx)
        {
            lock (_stateLock)
            {
                decimal currentBalance = _accountBalances.GetValueOrDefault(tx.FromAddress, 0m);
                decimal maxGasFee = (tx.GasLimit * tx.GasPriceGwei) / 1_000_000_000m;
                decimal totalCost = tx.Amount + maxGasFee;

                if (currentBalance < totalCost)
                {
                    return $"Insufficient balance. Required: {totalCost} ETH, Available: {currentBalance} ETH.";
                }

                long expectedNonce = _accountNonces.GetValueOrDefault(tx.FromAddress, 0);
                if (tx.Nonce < expectedNonce)
                {
                    return $"Nonce too low. Expected: {expectedNonce}, Got: {tx.Nonce}.";
                }

                return null;
            }
        }

        private ExecutionResult ExecuteTransfer(Transaction tx)
        {
            lock (_stateLock)
            {
                long gasUsed = 21000;
                decimal totalFee = (gasUsed * tx.GasPriceGwei) / 1_000_000_000m;

                _accountBalances[tx.FromAddress] -= (tx.Amount + totalFee);
                _accountBalances[tx.ToAddress] = _accountBalances.GetValueOrDefault(tx.ToAddress, 0m) + tx.Amount;
                _accountNonces[tx.FromAddress] = tx.Nonce + 1;

                string receipt = ComputeReceiptHash(tx.TxHash, gasUsed, "SUCCESS");
                return new ExecutionResult(true, tx.TxHash, gasUsed, receipt, null, new[] { $"Transfer ({tx.Amount} ETH) -> {tx.ToAddress}" });
            }
        }

        private ExecutionResult ExecuteDeFiSwap(Transaction tx)
        {
            lock (_stateLock)
            {
                long gasUsed = 125000;
                decimal totalFee = (gasUsed * tx.GasPriceGwei) / 1_000_000_000m;

                decimal swapAmount = tx.Amount;
                decimal outputAmount = swapAmount * 3450.75m * 0.997m;

                _accountBalances[tx.FromAddress] -= (swapAmount + totalFee);
                _accountNonces[tx.FromAddress] = tx.Nonce + 1;

                string receipt = ComputeReceiptHash(tx.TxHash, gasUsed, "SWAP_SUCCESS");
                var logs = new List<string>
                {
                    $"Swapped {swapAmount} ETH for {outputAmount:F2} USDT",
                    "Slippage tolerance: 0.5%",
                    "Pool Reserve Ratio Updated"
                };

                return new ExecutionResult(true, tx.TxHash, gasUsed, receipt, null, logs);
            }
        }

        private ExecutionResult ExecuteContractCall(Transaction tx)
        {
            lock (_stateLock)
            {
                long gasUsed = 68000;
                decimal totalFee = (gasUsed * tx.GasPriceGwei) / 1_000_000_000m;

                _accountBalances[tx.FromAddress] -= totalFee;
                _accountNonces[tx.FromAddress] = tx.Nonce + 1;

                string receipt = ComputeReceiptHash(tx.TxHash, gasUsed, "CONTRACT_EXEC");
                return new ExecutionResult(true, tx.TxHash, gasUsed, receipt, null, new[] { "Contract state mutated", "Event Log Emitted: Transfer(address,address,uint256)" });
            }
        }

        private ExecutionResult ExecuteNFTMint(Transaction tx)
        {
            lock (_stateLock)
            {
                long gasUsed = 95000;
                decimal totalFee = (gasUsed * tx.GasPriceGwei) / 1_000_000_000m;

                _accountBalances[tx.FromAddress] -= (tx.Amount + totalFee);
                _accountNonces[tx.FromAddress] = tx.Nonce + 1;

                string receipt = ComputeReceiptHash(tx.TxHash, gasUsed, "NFT_MINTED");
                return new ExecutionResult(true, tx.TxHash, gasUsed, receipt, null, new[] { $"Minted TokenID #{Random.Shared.Next(1000, 9999)} to {tx.FromAddress}" });
            }
        }

        private ExecutionResult ExecuteBridgeRelay(Transaction tx)
        {
            lock (_stateLock)
            {
                long gasUsed = 180000;
                decimal totalFee = (gasUsed * tx.GasPriceGwei) / 1_000_000_000m;

                _accountBalances[tx.FromAddress] -= (tx.Amount + totalFee);
                _accountNonces[tx.FromAddress] = tx.Nonce + 1;

                string receipt = ComputeReceiptHash(tx.TxHash, gasUsed, "BRIDGE_LOCKED");
                return new ExecutionResult(true, tx.TxHash, gasUsed, receipt, null, new[] { "Cross-chain message locked for dest chain ID 137 (Polygon)" });
            }
        }

        private ExecutionResult ExecuteGenericTransaction(Transaction tx)
        {
            return ExecuteTransfer(tx);
        }

        private void FinalizeTransaction(Transaction tx, bool success, long gasUsed, string? receiptHash, string? error)
        {
            tx.GasUsed = gasUsed;
            tx.ExecutionReceiptHash = receiptHash;
            tx.FailureReason = error;
            tx.Status = success ? TransactionStatus.Committed : TransactionStatus.Reverted;

            _mempool.TryRemove(tx.TxHash, out _);
            _processedHistory[tx.TxHash] = tx;

            RaiseStatusChanged(tx.TxHash, tx.Status, error ?? $"Receipt: {receiptHash}");
        }

        private bool ValidateSignatureAndHash(Transaction tx)
        {
            if (string.IsNullOrEmpty(tx.TxHash) || !tx.TxHash.StartsWith("0x"))
                return false;

            return tx.TxHash.Length == 66;
        }

        private string ComputeReceiptHash(string txHash, long gasUsed, string status)
        {
            using var sha = SHA256.Create();
            byte[] raw = Encoding.UTF8.GetBytes($"{txHash}:{gasUsed}:{status}:{DateTime.UtcNow.Ticks}");
            byte[] hashBytes = sha.ComputeHash(raw);
            return "0x" + Convert.ToHexString(hashBytes).ToLowerInvariant();
        }

        private void RaiseStatusChanged(string txHash, TransactionStatus status, string? details)
        {
            OnTransactionStatusChanged?.Invoke(this, new TransactionStatusChangedEventArgs(txHash, status, details));
        }

        public async ValueTask DisposeAsync()
        {
            _cts.Cancel();
            _txQueue.Writer.Complete();

            try
            {
                await Task.WhenAll(_workerTasks);
            }
            catch (Exception)
            {
            }

            _cts.Dispose();
        }
    }
}