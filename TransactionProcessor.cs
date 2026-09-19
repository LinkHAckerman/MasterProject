using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Security.Cryptography;
using System.Text;
using System.Threading.Tasks;

namespace MagnumOpus.Core
{
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

        public string ComputeHash()
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
            return \"0x\" + Convert.ToHexString(bytes).ToLowerInvariant();
        }

        public bool VerifySignature()
        {
            if (string.IsNullOrEmpty(Signature) || !Signature.StartsWith(\"0x\"))
                return false;

            var computedId = ComputeHash();
            if (computedId != Id) return false;

            using var sha256 = SHA256.Create();
            var raw = $"{Id}:mock_private_key_signature_entropy_998244353_magnum_opus_secure_channel";
            var bytes = sha256.ComputeHash(Encoding.UTF8.GetBytes(raw));
            var expected = \"0x\" + Convert.ToHexString(bytes).ToLowerInvariant();
            return Signature == expected;
        }
    }

    public sealed class TransactionProcessor
    {
        private readonly ConcurrentDictionary<string, decimal> _balances = new();
        private readonly ConcurrentQueue<Transaction> _pending = new();
        private readonly object _stateLock = new();

        public TransactionProcessor()
        {
            // Genesis account for demo purposes
            _balances[\"genesis\"] = 1_000_000_000m;
        }

        public bool SubmitTransaction(Transaction tx)
        {
            if (tx == null) throw new ArgumentNullException(nameof(tx));
            if (!tx.VerifySignature()) return false;

            lock (_stateLock)
            {
                var senderBalance = GetBalanceInternal(tx.Sender);
                if (senderBalance < tx.Amount + tx.Fee) return false;
            }

            _pending.Enqueue(tx);
            return true;
        }

        public async Task ProcessPendingAsync()
        {
            while (_pending.TryDequeue(out var tx))
            {
                await ProcessSingleAsync(tx);
            }
        }

        private Task ProcessSingleAsync(Transaction tx)
        {
            return Task.Run(() =>
            {
                lock (_stateLock)
                {
                    var senderBal = GetBalanceInternal(tx.Sender);
                    var totalDebit = tx.Amount + tx.Fee;
                    if (senderBal < totalDebit) return; // insufficient funds, drop

                    // Debit sender
                    _balances[tx.Sender] = senderBal - totalDebit;

                    // Credit recipient
                    var recipientBal = GetBalanceInternal(tx.Recipient);
                    _balances[tx.Recipient] = recipientBal + tx.Amount;

                    // Fee goes to fee pool
                    var feeBal = GetBalanceInternal(\"fee_pool\");
                    _balances[\"fee_pool\"] = feeBal + tx.Fee;
                }
            });
        }

        private decimal GetBalanceInternal(string address)
        {
            return _balances.TryGetValue(address, out var bal) ? bal : 0m;
        }

        public decimal GetBalance(string address)
        {
            if (address == null) throw new ArgumentNullException(nameof(address));
            return GetBalanceInternal(address);
        }

        public IEnumerable<(string Address, decimal Balance)> GetAllBalances()
        {
            foreach (var kvp in _balances)
                yield return (kvp.Key, kvp.Value);
        }
    }
}
