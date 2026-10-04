using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using Nethereum.Signer;
using Nethereum.Util;

namespace MagnumOpus.Core
{
    public class Transaction
    {
        public string From { get; set; }
        public string To { get; set; }
        public decimal Amount { get; set; }
        public ulong Nonce { get; set; }
        public string Data { get; set; }
        public string Signature { get; set; }
    }

    public class TransactionResult
    {
        public bool Success { get; set; }
        public string TxHash { get; set; }
        public string ErrorMessage { get; set; }
    }

    public class TransactionProcessor
    {
        private readonly ITransactionRepository _repo;
        private readonly IBlockchainGateway _gateway;

        public TransactionProcessor(ITransactionRepository repo, IBlockchainGateway gateway)
        {
            _repo = repo;
            _gateway = gateway;
        }

        public async Task<TransactionResult> ProcessAsync(Transaction tx)
        {
            var validation = Validate(tx);
            if (!validation.Success)
                return validation;

            if (!VerifySignature(tx))
                return new TransactionResult { Success = false, ErrorMessage = "Invalid signature" };

            var expectedNonce = await _repo.GetNextNonceAsync(tx.From);
            if (tx.Nonce != expectedNonce)
                return new TransactionResult { Success = false, ErrorMessage = $"Invalid nonce. Expected {expectedNonce}" };

            var raw = $"{tx.From}|{tx.To}|{tx.Amount}|{tx.Nonce}|{tx.Data}";
            var txHash = Sha256.ComputeHash(raw);

            var broadcastResult = await _gateway.BroadcastTransactionAsync(txHash, tx);
            if (!broadcastResult.Success)
                return new TransactionResult { Success = false, ErrorMessage = broadcastResult.ErrorMessage };

            await _repo.SaveTransactionAsync(txHash, tx);

            return new TransactionResult { Success = true, TxHash = txHash };
        }

        private TransactionResult Validate(Transaction tx)
        {
            if (string.IsNullOrWhiteSpace(tx.From) ||
                string.IsNullOrWhiteSpace(tx.To) ||
                tx.Amount <= 0 ||
                string.IsNullOrWhiteSpace(tx.Signature))
            {
                return new TransactionResult { Success = false, ErrorMessage = "Missing required fields" };
            }
            return new TransactionResult { Success = true };
        }

        private bool VerifySignature(Transaction tx)
        {
            try
            {
                var signer = new EthereumMessageSigner();
                var message = $"{tx.From}{tx.To}{tx.Amount}{tx.Nonce}{tx.Data}";
                var recovered = signer.EncodeUTF8AndEcRecover(message, tx.Signature);
                return string.Equals(recovered, tx.From, StringComparison.OrdinalIgnoreCase);
            }
            catch
            {
                return false;
            }
        }
    }

    public interface ITransactionRepository
    {
        Task<ulong> GetNextNonceAsync(string address);
        Task SaveTransactionAsync(string txHash, Transaction tx);
    }

    public interface IBlockchainGateway
    {
        Task<(bool Success, string ErrorMessage)> BroadcastTransactionAsync(string txHash, Transaction tx);
    }

    public static class Sha256
    {
        public static string ComputeHash(string input)
        {
            var keccak = new Sha3Keccack();
            var hash = keccak.CalculateHash(input);
            return "0x" + hash;
        }
    }
}