using System;\
using System.Collections.Generic;\
using System.Threading.Tasks;\
using System.Threading;\
using System.Security.Cryptography;\
using System.Text;\
using Microsoft.Extensions.Logging;\
\
namespace MagnumOpus.Backend\
{\
    public enum TransactionStatus { Pending, Confirmed, Failed }\
\
    public class Transaction\
    {\
        public string Id { get; set; }\
        public string From { get; set; }\
        public string To { get; set; }\
        public decimal Amount { get; set; }\
        public string Token { get; set; }\
        public DateTime Timestamp { get; set; }\
        public TransactionStatus Status { get; set; }\
        public string Hash { get; set; }\
    }\
\
    public interface ITransactionStore\
    {\
        Task SaveAsync(Transaction tx);\
        Task<Transaction?> GetAsync(string id);\
        Task UpdateStatusAsync(string id, TransactionStatus status);\
    }\
\
    public class InMemoryTransactionStore : ITransactionStore\
    {\
        private readonly Dictionary<string, Transaction> _store = new();\
        private readonly SemaphoreSlim _sem = new(1,1);\
\
        public async Task SaveAsync(Transaction tx)\
        {\
            await _sem.WaitAsync();\
            try { _store[tx.Id] = tx; }\
            finally { _sem.Release(); }\
        }\
\
        public async Task<Transaction?> GetAsync(string id)\
        {\
            await _sem.WaitAsync();\
            try { _store.TryGetValue(id, out var tx); return tx; }\
            finally { _sem.Release(); }\
        }\
\
        public async Task UpdateStatusAsync(string id, TransactionStatus status)\
        {\
            await _sem.WaitAsync();\
            try { if(_store.TryGetValue(id, out var tx)) tx.Status = status; }\
            finally { _sem.Release(); }\
        }\
    }\
\
    public class TransactionProcessor\
    {\
        private readonly ITransactionStore _store;\
        private readonly ILogger<TransactionProcessor> _logger;\
        private readonly TimeSpan _confirmationTimeout = TimeSpan.FromSeconds(30);\
        private readonly Random _rnd = new();\
\
        public TransactionProcessor(ITransactionStore store, ILogger<TransactionProcessor> logger)\
        {\
            _store = store;\
            _logger = logger;\
        }\
\
        public async Task<string> SubmitAsync(string from, string to, decimal amount, string token)\
        {\
            var tx = new Transaction\
            {\
                Id = Guid.NewGuid().ToString(),\
                From = from,\
                To = to,\
                Amount = amount,\
                Token = token,\
                Timestamp = DateTime.UtcNow,\
                Status = TransactionStatus.Pending,\
                Hash = ComputeHash(from, to, amount, token, DateTime.UtcNow)\
            };\
\
            await _store.SaveAsync(tx);\
            _logger.LogInformation("Transaction {Id} submitted\