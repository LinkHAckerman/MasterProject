using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Threading.Tasks;
using System.Numerics;

namespace MagnumOpus.Core
{
    /// <summary>
    /// High-performance transaction processor for the Magnum Opus platform.
    /// Handles validation, nonce management, gas estimation, and state transitions.
    /// </summary>
    public class TransactionProcessor
    {
        private readonly ConcurrentDictionary<string, BigInteger> _accountNonces = new ConcurrentDictionary<string, BigInteger>();
        private readonly ConcurrentDictionary<string, BigInteger> _accountBalances = new ConcurrentDictionary<string, BigInteger>();
        private readonly object _lock = new object();
        private readonly ILogger _logger;

        // Gas constants (in Gwei)
        private const long BaseGasCost = 21000;
        private const long DataGasCost = 16; // Per non-zero byte
        private const long ZeroDataGasCost = 4; // Per zero byte
        private const long MaxGasLimit = 50_000_000;

        public TransactionProcessor(ILogger logger)
        {
            _logger = logger ?? throw new ArgumentNullException(nameof(logger));
        }

        /// <summary>
        /// Processes a batch of transactions concurrently.
        /// </summary>
        public async Task<List<TransactionResult>> ProcessBatchAsync(List<Transaction> transactions, CancellationToken cancellationToken = default)
        {
            var results = new List<TransactionResult>();
            var tasks = transactions.Select(tx => ProcessSingleAsync(tx, cancellationToken)).ToList();
            
            // Process in parallel but maintain order for deterministic state updates if needed
            // For high throughput, we use Task.WhenAll but handle conflicts via locking in state update
            var completedTasks = await Task.WhenAll(tasks);
            results.AddRange(completedTasks);
            
            _logger.LogInformation($"Processed {results.Count} transactions. Success: {results.Count(r => r.Success)}");
            return results;
        }

        private async Task<TransactionResult> ProcessSingleAsync(Transaction tx, CancellationToken cancellationToken)
        {
            try
            {
                // 1. Validate Transaction Structure
                if (tx == null) throw new ArgumentException("Transaction cannot be null");
                if (string.IsNullOrEmpty(tx.From)) throw new ArgumentException("Sender address is required");
                if (string.IsNullOrEmpty(tx.To)) throw new ArgumentException("Recipient address is required");

                // 2. Check Nonce
                if (!ValidateNonce(tx.From, tx.Nonce))
                {
                    return new TransactionResult 
                    { 
                        TxHash = tx.Hash, 
                        Success = false, 
                        Error = "Invalid nonce" 
                    };
                }

                // 3. Estimate Gas
                long gasUsed = EstimateGas(tx);
                if (tx.GasLimit < gasUsed)
                {
                    return new TransactionResult 
                    { 
                        TxHash = tx.Hash, 
                        Success = false, 
                        Error = "Insufficient gas limit" 
                    };
                }

                // 4. Check Balance (Value + Gas Cost)
                BigInteger totalCost = tx.Value + (BigInteger)gasUsed * tx.GasPrice;
                if (!CheckBalance(tx.From, totalCost))
                {
                    return new TransactionResult 
                    { 
                        TxHash = tx.Hash, 
                        Success = false, 
                        Error = "Insufficient funds" 
                    };
                }

                // 5. Execute State Transition (Atomic)
                lock (_lock)
                {
                    // Deduct sender
                    _accountBalances.AddOrUpdate(tx.From, 0, (key, oldVal) => oldVal - totalCost);
                    
                    // Credit recipient
                    _accountBalances.AddOrUpdate(tx.To, 0, (key, oldVal) => oldVal + tx.Value);

                    // Update Nonce
                    _accountNonces.AddOrUpdate(tx.From, 0, (key, oldVal) => oldVal + 1);
                }

                // Simulate network latency for realism in mock environment
                await Task.Delay(5, cancellationToken);

                return new TransactionResult 
                { 
                    TxHash = tx.Hash, 
                    Success = true, 
                    GasUsed = gasUsed, 
                    BlockNumber = GetCurrentBlockNumber() 
                };
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, $"Error processing transaction {tx?.Hash}");
                return new TransactionResult 
                { 
                    TxHash = tx?.Hash ?? "Unknown", 
                    Success = false, 
                    Error = ex.Message 
                };
            }
        }

        private bool ValidateNonce(string address, BigInteger nonce)
        {
            if (!_accountNonces.TryGetValue(address, out BigInteger currentNonce))
            {
                currentNonce = 0;
            }
            return nonce == currentNonce;
        }

        private bool CheckBalance(string address, BigInteger amount)
        {
            if (!_accountBalances.TryGetValue(address, out BigInteger balance))
            {
                balance = 0;
            }
            return balance >= amount;
        }

        private long EstimateGas(Transaction tx)
        {
            long gas = BaseGasCost;
            
            // Add data cost
            if (!string.IsNullOrEmpty(tx.Data))
            {
                byte[] dataBytes = Encoding.UTF8.GetBytes(tx.Data);
                foreach (var b in dataBytes)
                {
                    gas += (b == 0) ? ZeroDataGasCost : DataGasCost;
                }
            }

            // Simple heuristic for complex smart contract calls
            if (tx.Data != null && tx.Data.Length > 100)
            {
                gas += 50000; // Estimated overhead for contract execution
            }

            return Math.Min(gas, MaxGasLimit);
        }

        private int GetCurrentBlockNumber()
        {
            // Mock block number based on time
            return (int)(DateTime.UtcNow - new DateTime(2024, 1, 1)).TotalSeconds / 12;
        }

        /// <summary>
        /// Initializes account state for testing or onboarding.
        /// </summary>
        public void InitializeAccount(string address, BigInteger initialBalance)
        {
            _accountBalances[address] = initialBalance;
            _accountNonces[address] = 0;
            _logger.LogInformation($"Initialized account {address} with balance {initialBalance}");
        }
    }

    public class Transaction
    {
        public string Hash { get; set; }
        public string From { get; set; }
        public string To { get; set; }
        public BigInteger Value { get; set; }
        public BigInteger Nonce { get; set; }
        public long GasLimit { get; set; }
        public long GasPrice { get; set; }
        public string Data { get; set; }
    }

    public class TransactionResult
    {
        public string TxHash { get; set; }
        public bool Success { get; set; }
        public string Error { get; set; }
        public long GasUsed { get; set; }
        public int BlockNumber { get; set; }
    }

    public interface ILogger
    {
        void LogInformation(string message);
        void LogError(Exception ex, string message);
    }

    // Simple Console Logger Implementation for standalone usage
    public class ConsoleLogger : ILogger
    {
        public void LogInformation(string message)
        {
            Console.WriteLine($"[INFO] {DateTime.UtcNow:HH:mm:ss.fff} - {message}");
        }

        public void LogError(Exception ex, string message)
        {
            Console.WriteLine($"[ERROR] {DateTime.UtcNow:HH:mm:ss.fff} - {message}: {ex.Message}");
        }
    }
}