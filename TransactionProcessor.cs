using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Extensions.Logging;

namespace MagnumOpus.Core
{
	public record Transaction
	{
		public Guid Id { get; init; } = Guid.NewGuid();
		public string FromAddress { get; init; } = string.Empty;
		public string ToAddress { get; init; } = string.Empty;
		public decimal Amount { get; init; }
		public string Currency { get; init; } = "ETH";
		public DateTime Timestamp { get; init; } = DateTime.UtcNow;
		public string? Signature { get; init; }
	}

	public class TransactionProcessor : IDisposable
	{
		private readonly ILogger<TransactionProcessor> _logger;
		private readonly ConcurrentQueue<Transaction> _queue = new();
		private readonly CancellationTokenSource _cts = new();
		private readonly Task _worker;

		public TransactionProcessor(ILogger<TransactionProcessor> logger)
		{
			_logger = logger ?? throw new ArgumentNullException(nameof(logger));
			_worker = Task.Run(ProcessQueueAsync);
		}

		public Task<bool> ValidateTransactionAsync(Transaction tx)
		{
			if (tx == null) throw new ArgumentNullException(nameof(tx));
			if (string.IsNullOrWhiteSpace(tx.FromAddress) || string.IsNullOrWhiteSpace(tx.ToAddress))
				return Task.FromResult(false);
			if (tx.Amount <= 0) return Task.FromResult(false);
			// Simple mock signature check – in real world use ECDSA verification
			if (string.IsNullOrWhiteSpace(tx.Signature))
				return Task.FromResult(false);
			return Task.FromResult(true);
		}

		public async Task EnqueueAsync(Transaction tx)
		{
			if (await ValidateTransactionAsync(tx) == false)
			{
				_logger.LogWarning("Transaction {Id} failed validation", tx.Id);
				return;
			}

			_queue.Enqueue(tx);
			_logger.LogInformation("Transaction {Id} enqueued", tx.Id);
		}

		private async Task ProcessQueueAsync()
		{
			while (!_cts.IsCancellationRequested)
			{
				if (_queue.TryDequeue(out var tx))
				{
					try
					{
						var hash = ComputeHash(tx);
						// Mock sending to blockchain – replace with real RPC call
						await SimulateBlockchainSubmitAsync(tx, hash);
						_logger.LogInformation("Transaction {Id} processed with hash {Hash}", tx.Id, hash);
					}
					catch (Exception ex)
					{
						_logger.LogError(ex, "Failed to process transaction {Id}", tx.Id);
					}
				}
				else
				{
					await Task.Delay(100, _cts.Token);
				}
			}
		}

		private static string ComputeHash(Transaction tx)
		{
			using var sha = SHA256.Create();
			var payload = $"{tx.Id}{tx.FromAddress}{tx.ToAddress}{tx.Amount}{tx.Currency}{tx.Timestamp:o}";
			var bytes = Encoding.UTF8.GetBytes(payload);
			var hash = sha.ComputeHash(bytes);
			return "0x" + BitConverter.ToString(hash).Replace("-", string.Empty).ToLowerInvariant();
		}

		private static async Task SimulateBlockchainSubmitAsync(Transaction tx, string hash)
		{
			// Simulate network latency
			await Task.Delay(TimeSpan.FromMilliseconds(new Random().Next(200, 800)));
			// In a real implementation you would call an RPC endpoint here.
		}

		public void Dispose()
		{
			_cts.Cancel();
			try
			{
				_worker.Wait(TimeSpan.FromSeconds(5));
			}
			catch { /* ignore */ }
			_cts.Dispose();
		}
	}
}
