using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using Microsoft.Extensions.Logging;

namespace MagnumOpus.Backend
{
    public record Transaction(string Id, string From, string To, decimal Amount, string Token, DateTime Timestamp);

    public interface ITransactionRepository
    {
        Task AddAsync(Transaction tx);
        Task<IReadOnlyCollection<Transaction>> GetRecentAsync(int count);
    }

    public interface IBlockchainGateway
    {
        Task<string> BroadcastAsync(Transaction tx);
        Task<bool> VerifyAsync(string txHash);
    }

    public class TransactionProcessor
    {
        private readonly ITransactionRepository _repo;
        private readonly IBlockchainGateway _gateway;
        private readonly ILogger<TransactionProcessor> _logger;

        public TransactionProcessor(ITransactionRepository repo, IBlockchainGateway gateway, ILogger<TransactionProcessor> logger)
        {
            _repo = repo ?? throw new ArgumentNullException(nameof(repo));
            _gateway = gateway ?? throw new ArgumentNullException(nameof(gateway));
            _logger = logger ?? throw new ArgumentNullException(nameof(logger));
        }

        public async Task<string> ProcessAsync(Transaction tx)
        {
            if (tx == null) throw new ArgumentNullException(nameof(tx));
            Validate(tx);

            _logger.LogInformation("Processing transaction {TxId} from {From} to {To} amount {Amount} {Token}", tx.Id, tx.From, tx.To, tx.Amount, tx.Token);

            // Persist locally first
            await _repo.AddAsync(tx);

            // Broadcast to blockchain
            var txHash = await _gateway.BroadcastAsync(tx);
            _logger.LogInformation("Broadcasted transaction {TxId} with hash {Hash}", tx.Id, txHash);

            // Verify inclusion (simple retry)
            const int maxAttempts = 3;
            for (int attempt = 1; attempt <= maxAttempts; attempt++)
            {
                var verified = await _gateway.VerifyAsync(txHash);
                if (verified)
                {
                    _logger.LogInformation("Transaction {TxId} verified on attempt {Attempt}", tx.Id, attempt);
                    return txHash;
                }

                _logger.LogWarning("Verification failed for {TxId} attempt {Attempt}", tx.Id, attempt);
                await Task.Delay(TimeSpan.FromSeconds(2));
            }

            _logger.LogError("Transaction {TxId} could not be verified after {MaxAttempts} attempts", tx.Id, maxAttempts);
            throw new InvalidOperationException($"Transaction {tx.Id} verification failed.");
        }

        private static void Validate(Transaction tx)
        {
            if (string.IsNullOrWhiteSpace(tx.Id)) throw new ArgumentException("Transaction Id is required.");
            if (string.IsNullOrWhiteSpace(tx.From)) throw new ArgumentException("Sender address is required.");
            if (string.IsNullOrWhiteSpace(tx.To)) throw new ArgumentException("Recipient address is required.");
            if (tx.Amount <= 0) throw new ArgumentException("Amount must be positive.");
            if (string.IsNullOrWhiteSpace(tx.Token)) throw new ArgumentException("Token symbol is required.");
        }
    }
}
