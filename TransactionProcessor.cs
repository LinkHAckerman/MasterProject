using System;
using System.Collections.Generic;
using System.Numerics;
using System.Security.Cryptography;
using System.Text.Json;

namespace MagnumOpus
{
    public class Transaction
    {
        public string TxId { get; set; }
        public string FromAddress { get; set; }
        public string ToAddress { get; set; }
        public BigInteger Amount { get; set; }
        public byte[] Signature { get; set; }
        public DateTime Timestamp { get; set; }
    }

    public class Ledger
    {
        private readonly Dictionary<string, BigInteger> _balances = new();

        public BigInteger GetBalance(string address) => _balances.TryGetValue(address, out var bal) ? bal : BigInteger.Zero;

        public void Credit(string address, BigInteger amount)
        {
            if (!_balances.ContainsKey(address))
                _balances[address] = BigInteger.Zero;
            _balances[address] += amount;
        }

        public void Debit(string address, BigInteger amount)
        {
            if (!_balances.ContainsKey(address))
                throw new InvalidOperationException($"Insufficient funds for {address}");
            if (_balances[address] < amount)
                throw new InvalidOperationException($"Insufficient funds for {address}");
            _balances[address] -= amount;
        }
    }

    public class TransactionProcessor
    {
        private readonly Ledger _ledger;
        private readonly Dictionary<string, ECDsa> _publicKeys = new();

        public TransactionProcessor(Ledger ledger)
        {
            _ledger = ledger;
        }

        public void RegisterPublicKey(string address, ECDsa publicKey)
        {
            _publicKeys[address] = publicKey;
        }

        public bool ProcessTransaction(Transaction tx)
        {
            if (!VerifySignature(tx))
                return false;

            try
            {
                _ledger.Debit(tx.FromAddress, tx.Amount);
                _ledger.Credit(tx.ToAddress, tx.Amount);
                LogTransaction(tx);
                return true;
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine($"Transaction {tx.TxId} failed: {ex.Message}");
                return false;
            }
        }

        private bool VerifySignature(Transaction tx)
        {
            if (!_publicKeys.TryGetValue(tx.FromAddress, out var pubKey))
                return false;

            var data = $"{tx.TxId}{tx.FromAddress}{tx.ToAddress}{tx.Amount}{tx.Timestamp:O}";
            var hash = SHA256.HashData(System.Text.Encoding.UTF8.GetBytes(data));
            return pubKey.VerifyHash(hash, tx.Signature);
        }

        private void LogTransaction(Transaction tx)
        {
            var log = new
            {
                tx.TxId,
                tx.FromAddress,
                tx.ToAddress,
                Amount = tx.Amount.ToString(),
                Timestamp = tx.Timestamp,
                Status = "Success"
            };
            var json = JsonSerializer.Serialize(log);
            Console.WriteLine(json);
        }
    }
}
