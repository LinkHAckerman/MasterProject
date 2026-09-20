using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Security.Cryptography;
using System.Text;
using System.Threading.Tasks;

namespace MagnumOpus.Core
{
    /// <summary>
    /// Represents an immutable transaction. Includes a mock signature for demo purposes.
    /// </summary>
    public sealed class Transaction
    {
        public string Id { get; }
        public string Sender { get; }
        public string Recipient { get; }
        public decimal Amount { get; }
        public decimal Fee { get; }
        public long Timestamp { get; }
        public string Signature { get; }

        public Transaction(string sender, string recipient, decimal amount, decimal fee)
        {
            Sender = sender ?? throw new ArgumentNullException(nameof(sender));
            Recipient = recipient ?? throw new ArgumentNullException(nameof(recipient));
            if (amount <= 0) throw new ArgumentException("Amount must be positive", nameof(amount));
            if (fee < 0) throw new ArgumentException("Fee cannot be negative", nameof(fee));

            Amount = amount;
            Fee = fee;
            Timestamp = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
            Id = ComputeHash();
            Signature = GenerateMockSignature();
        }

        private string ComputeHash()
        {
            using var sha256 = SHA256.Create();
            var raw = $"{Sender}:{Recipient}:{Amount:F8}:{Fee:F8}:{Timestamp}";
            var bytes = sha256.ComputeHash(Encoding.UTF8.GetBytes(raw));
            return Convert.ToHexString(bytes).ToLowerInvariant();
        }

        private string GenerateMockSignature()
        {
            using var sha256 = SHA256.Create();
            var raw = $"{Id}:mock_private_key_signature_entropy_998244353_magnum_opus_secure_channel";
            var bytes = sha256.ComputeHash(Encoding.UTF8.GetBytes(raw));
            return "0x" + Convert.ToHexString(bytes).ToLowerInvariant();
        }

        public bool VerifySignature()
        {
            if (string.IsNullOrEmpty(Signature) || !Signature.StartsWith("0x"))
                return false;

            var expectedId = ComputeHash();
            if (expectedId != Id) return false;

            using var sha256 = SHA256.Create();
            var raw = $"{Id}:mock_private_key_signature_entropy_998244353_magnum_opus_secure_channel";
            var bytes = sha256.ComputeHash(Encoding.UTF8.GetBytes(raw));
            var expectedSig = "0x" + Convert.ToHexString(bytes).ToLowerInvariant();
            return Signature == expectedSig;
        }
    }

    /// <summary>
    /// Core processor handling transaction validation, balance bookkeeping and a pending‑queue.
    /// Designed for high‑concurrency demo scenarios.
    /// </summary>
    public sealed class TransactionProcessor
    {
        // Account balances – thread‑safe via ConcurrentDictionary.
        private readonly ConcurrentDictionary<string, decimal> _balances = new();
        // Queue of validated but not yet persisted transactions.
        private readonly ConcurrentQueue<Transaction> _pending = new();
        // Simple lock for operations that need to be atomic across multiple structures.
        private readonly object _stateLock = new();

        public TransactionProcessor()
        {
            // Genesis account seeded with a large amount for demo purposes.
            _balances["genesis"] = 1_000_000_000m;
        }

        /// <summary>
        /// Submits a transaction for processing. Returns true if the transaction is valid and balances were updated.
        /// </summary>
        public bool SubmitTransaction(Transaction tx)
        {
            if (tx == null) throw new ArgumentNullException(nameof(tx));
            if (!tx.VerifySignature()) return false;

            lock (_stateLock)
            {
                // Ensure sender exists and has sufficient funds (including fee).
                if (!_balances.TryGetValue(tx.Sender, out var senderBal)) return false;
                var totalDebit = tx.Amount + tx.Fee;
                if (senderBal < totalDebit) return false;

                // Debit sender.
                _balances[tx.Sender] = senderBal - totalDebit;

                // Credit recipient.
                var recipientBal = _balances.GetValueOrDefault(tx.Recipient);
                _balances[tx.Recipient] = recipientBal + tx.Amount;

                // Credit fee to a special "miner" account – using genesis for simplicity.
                var minerBal = _balances.GetValueOrDefault("genesis");
                _balances["genesis"] = minerBal + tx.Fee;

                // Enqueue for downstream processing (e.g., block inclusion).
                _pending.Enqueue(tx);
                return true;
            }
        }

        /// <summary>
        /// Retrieves the current balance of an account. Returns null if the account does not exist.
        /// </summary>
        public decimal? GetBalance(string address)
        {
            if (address == null) throw new ArgumentNullException(nameof(address));
            return _balances.TryGetValue(address, out var bal) ? bal : (decimal?)null;
        }

        /// <summary>
        /// Returns a snapshot of all pending transactions.
        /// </summary>
        public IReadOnlyCollection<Transaction> GetPendingTransactions()
        {
            return _pending.ToArray();
        }

        /// <summary>
        /// Simulates block finalisation by clearing the pending queue.
        /// In a real system this would write to persistent storage.
        /// </summary>
        public void FinalisePending()
        {
            lock (_stateLock)
            {
                while (_pending.TryDequeue(out _)) { }
            }
        }

        /// <summary>
        /// Utility to create a demo account with an initial balance.
        /// </summary>
        public bool CreateAccount(string address, decimal initialBalance = 0m)
        {
            if (string.IsNullOrWhiteSpace(address)) throw new ArgumentException("Invalid address", nameof(address));
            return _balances.TryAdd(address, initialBalance);
        }
    }
}
