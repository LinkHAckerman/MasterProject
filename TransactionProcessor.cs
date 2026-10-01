using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using System.Numerics;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace MagnumOpus.Backend.Core
{
    public class TransactionProcessor
    {
        private readonly IBlockchainService _blockchainService;
        private readonly IWalletService _walletService;
        private readonly ILogger<TransactionProcessor> _logger;

        public TransactionProcessor(
            IBlockchainService blockchainService,
            IWalletService walletService,
            ILogger<TransactionProcessor> logger)
        {
            _blockchainService = blockchainService;
            _walletService = walletService;
            _logger = logger;
        }

        public async Task<TransactionResult> ProcessTransaction(TransactionRequest request)
        {
            try
            {
                // Validate transaction request
                if (!ValidateTransactionRequest(request))
                {
                    return new TransactionResult
                    {
                        Success = false,
                        ErrorMessage = "Invalid transaction request"
                    };
                }

                // Get sender wallet
                var senderWallet = await _walletService.GetWalletByAddress(request.FromAddress);
                if (senderWallet == null)
                {
                    return new TransactionResult
                    {
                        Success = false,
                        ErrorMessage = "Sender wallet not found"
                    };
                }

                // Verify sender has sufficient balance
                var balance = await _blockchainService.GetBalance(request.FromAddress);
                if (balance < request.Amount + request.GasFee)
                {
                    return new TransactionResult
                    {
                        Success = false,
                        ErrorMessage = "Insufficient balance"
                    };
                }

                // Create transaction object
                var transaction = new Transaction
                {
                    From = request.FromAddress,
                    To = request.ToAddress,
                    Amount = request.Amount,
                    GasFee = request.GasFee,
                    Nonce = await _blockchainService.GetNonce(request.FromAddress),
                    Timestamp = DateTimeOffset.UtcNow.ToUnixTimeSeconds(),
                    Data = request.Data
                };

                // Sign transaction
                var signature = _walletService.SignTransaction(transaction, senderWallet.PrivateKey);
                transaction.Signature = signature;

                // Submit transaction to blockchain
                var txHash = await _blockchainService.SubmitTransaction(transaction);

                // Log successful transaction
                _logger.LogInformation("Transaction processed successfully: {TxHash}", txHash);

                return new TransactionResult
                {
                    Success = true,
                    TransactionHash = txHash,
                    Transaction = transaction
                };
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error processing transaction");
                return new TransactionResult
                {
                    Success = false,
                    ErrorMessage = ex.Message
                };
            }
        }

        private bool ValidateTransactionRequest(TransactionRequest request)
        {
            if (string.IsNullOrWhiteSpace(request.FromAddress) ||
                string.IsNullOrWhiteSpace(request.ToAddress))
            {
                return false;
            }

            if (request.Amount <= 0 || request.GasFee < 0)
            {
                return false;
            }

            return true;
        }
    }

    public class TransactionRequest
    {
        public string FromAddress { get; set; }
        public string ToAddress { get; set; }
        public decimal Amount { get; set; }
        public decimal GasFee { get; set; }
        public string Data { get; set; }
    }

    public class TransactionResult
    {
        public bool Success { get; set; }
        public string ErrorMessage { get; set; }
        public string TransactionHash { get; set; }
        public Transaction Transaction { get; set; }
    }

    public class Transaction
    {
        public string From { get; set; }
        public string To { get; set; }
        public decimal Amount { get; set; }
        public decimal GasFee { get; set; }
        public long Nonce { get; set; }
        public long Timestamp { get; set; }
        public string Data { get; set; }
        public string Signature { get; set; }
    }

    public interface IBlockchainService
    {
        Task<decimal> GetBalance(string address);
        Task<long> GetNonce(string address);
        Task<string> SubmitTransaction(Transaction transaction);
    }

    public interface IWalletService
    {
        Task<Wallet> GetWalletByAddress(string address);
        string SignTransaction(Transaction transaction, string privateKey);
    }

    public class Wallet
    {
        public string Address { get; set; }
        public string PrivateKey { get; set; }
    }
}