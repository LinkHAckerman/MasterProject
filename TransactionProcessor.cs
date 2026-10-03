using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Linq;
using System.Numerics;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Threading.Channels;
using System.Threading.Tasks;

namespace MagnumOpus.Engine.Backend
{
    public enum TransactionStatus
    {
        Pending,
        Mempool,
        Included,
        Confirmed,
        Failed,
        Reverted
    }

    public enum OrderType
    {
        Limit,
        Market,
        StopLoss,
        TakeProfit
    }

    public enum OrderSide
    {
        Buy,
        Sell
    }

    public class Transaction
    {
        public string Hash { get; set; } = string.Empty;
        public string FromAddress { get; set; } = string.Empty;
        public string ToAddress { get; set; } = string.Empty;
        public BigInteger Value { get; set; }
        public ulong Nonce { get; set; }
        public decimal GasPriceGwei { get; set; }
        public ulong GasLimit { get; set; }
        public string PayloadHex { get; set; } = "0x";
        public string Signature { get; set; } = string.Empty;
        public TransactionStatus Status { get; set; } = TransactionStatus.Pending;
        public DateTime SubmittedAt { get; set; } = DateTime.UtcNow;
        public ulong BlockNumber { get; set; }
    }

    public class Order
    {
        public string OrderId { get; set; } = Guid.NewGuid().ToString("N");
        public string TraderAddress { get; set; } = string.Empty;
        public string Pair { get; set; } = "ETH/USDT";
        public OrderType Type { get; set; }
        public OrderSide Side { get; set; }
        public decimal Price { get; set; }
        public decimal Amount { get; set; }
        public decimal ExecutedAmount { get; set; }
        public bool IsFilled => ExecutedAmount >= Amount;
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    }

    public class GasEstimator
    {
        private readonly ConcurrentQueue<decimal> _recentGasPrices = new ConcurrentQueue<decimal>();
        private readonly int _maxSamples = 50;

        public void RecordGasPrice(decimal gwei)
        {
            _recentGasPrices.Enqueue(gwei);
            while (_recentGasPrices.Count > _maxSamples)
            {
                _recentGasPrices.TryDequeue(out _);
            }
        }

        public (decimal Slow, decimal Standard, decimal Fast, decimal Instant) EstimateFees()
        {
            if (_recentGasPrices.IsEmpty)
            {
                return (12.5m, 18.0m, 25.0m, 35.0m);
            }

            var prices = _recentGasPrices.ToList();
            prices.Sort();

            decimal baseFee = prices[(int)(prices.Count * 0.5)];
            return (
                Math.Max(5.0m, baseFee * 0.85m),
                baseFee,
                baseFee * 1.25m,
                baseFee * 1.60m
            );
        }
    }

    public class MempoolManager
    {
        private readonly ConcurrentDictionary<string, Transaction> _mempool = new ConcurrentDictionary<string, Transaction>();
        private readonly ConcurrentDictionary<string, ulong> _accountNonces = new ConcurrentDictionary<string, ulong>();
        private readonly Channel<Transaction> _txChannel = Channel.CreateUnbounded<Transaction>(new UnboundedChannelOptions { SingleReader = false, SingleWriter = false });

        public ChannelWriter<Transaction> Writer => _txChannel.Writer;
        public ChannelReader<Transaction> Reader => _txChannel.Reader;

        public bool SubmitTransaction(Transaction tx, out string error)
        {
            error = string.Empty;

            if (string.IsNullOrEmpty(tx.Hash))
            {
                tx.Hash = ComputeTransactionHash(tx);
            }

            ulong currentNonce = _accountNonces.GetOrAdd(tx.FromAddress, 0);
            if (tx.Nonce < currentNonce)
            {
                error = $"Nonce too low. Expected {currentNonce}, got {tx.Nonce}";
                tx.Status = TransactionStatus.Failed;
                return false;
            }

            tx.Status = TransactionStatus.Mempool;
            if (_mempool.TryAdd(tx.Hash, tx))
            {
                _accountNonces[tx.FromAddress] = tx.Nonce + 1;
                _txChannel.Writer.TryWrite(tx);
                return true;
            }

            error = "Transaction already exists in mempool";
            return false;
        }

        public List<Transaction> GetPendingTransactions(int maxCount)
        {
            return _mempool.Values
                .OrderByDescending(t => t.GasPriceGwei)
                .ThenBy(t => t.SubmittedAt)
                .Take(maxCount)
                .ToList();
        }

        public void RemoveTransaction(string hash)
        {
            _mempool.TryRemove(hash, out _);
        }

        private static string ComputeTransactionHash(Transaction tx)
        {
            string raw = $"{tx.FromAddress}:{tx.ToAddress}:{tx.Value}:{tx.Nonce}:{tx.GasPriceGwei}:{tx.PayloadHex}";
            using (var sha256 = SHA256.Create())
            {
                byte[] hashBytes = sha256.ComputeHash(Encoding.UTF8.GetBytes(raw));
                StringBuilder builder = new StringBuilder("0x");
                foreach (byte b in hashBytes)
                {
                    builder.Append(b.ToString("x2"));
                }
                return builder.ToString();
            }
        }
    }

    public class OrderBookMatchingEngine
    {
        private readonly ConcurrentBag<Order> _bids = new ConcurrentBag<Order>();
        private readonly ConcurrentBag<Order> _asks = new ConcurrentBag<Order>();
        private readonly object _lock = new object();

        public event Action<Order, Order, decimal, decimal>? OnTradeExecuted;

        public void PlaceOrder(Order order)
        {
            lock (_lock)
            {
                if (order.Side == OrderSide.Buy)
                {
                    MatchBuyOrder(order);
                }
                else
                {
                    MatchSellOrder(order);
                }
            }
        }

        private void MatchBuyOrder(Order buyOrder)
        {
            var sortedAsks = _asks.Where(a => !a.IsFilled && a.Price <= buyOrder.Price)
                                  .OrderBy(a => a.Price)
                                  .ThenBy(a => a.CreatedAt)
                                  .ToList();

            foreach (var ask in sortedAsks)
            {
                if (buyOrder.IsFilled) break;

                decimal fillAmount = Math.Min(buyOrder.Amount - buyOrder.ExecutedAmount, ask.Amount - ask.ExecutedAmount);
                decimal fillPrice = ask.Price;

                buyOrder.ExecutedAmount += fillAmount;
                ask.ExecutedAmount += fillAmount;

                OnTradeExecuted?.Invoke(buyOrder, ask, fillPrice, fillAmount);
            }

            if (!buyOrder.IsFilled && buyOrder.Type == OrderType.Limit)
            {
                _bids.Add(buyOrder);
            }
        }

        private void MatchSellOrder(Order sellOrder)
        {
            var sortedBids = _bids.Where(b => !b.IsFilled && b.Price >= sellOrder.Price)
                                  .OrderByDescending(b => b.Price)
                                  .ThenBy(b => b.CreatedAt)
                                  .ToList();

            foreach (var bid in sortedBids)
            {
                if (sellOrder.IsFilled) break;

                decimal fillAmount = Math.Min(sellOrder.Amount - sellOrder.ExecutedAmount, bid.Amount - bid.ExecutedAmount);
                decimal fillPrice = bid.Price;

                sellOrder.ExecutedAmount += fillAmount;
                bid.ExecutedAmount += fillAmount;

                OnTradeExecuted?.Invoke(bid, sellOrder, fillPrice, fillAmount);
            }

            if (!sellOrder.IsFilled && sellOrder.Type == OrderType.Limit)
            {
                _asks.Add(sellOrder);
            }
        }
    }

    public class TransactionProcessorService
    {
        private readonly MempoolManager _mempool;
        private readonly GasEstimator _gasEstimator;
        private readonly OrderBookMatchingEngine _matchingEngine;
        private ulong _currentBlockHeight = 18_500_000;
        private readonly CancellationTokenSource _cts = new CancellationTokenSource();

        public TransactionProcessorService()
        {
            _mempool = new MempoolManager();
            _gasEstimator = new GasEstimator();
            _matchingEngine = new OrderBookMatchingEngine();

            _matchingEngine.OnTradeExecuted += (buy, sell, price, amount) =>
            {
                Console.WriteLine($"[TRADE MATCHED] {amount} {buy.Pair} @ ${price:F2} | Buyer: {buy.TraderAddress[..8]}... Seller: {sell.TraderAddress[..8]}...");
            };
        }

        public void Start()
        {
            Task.Run(() => ProcessMempoolLoop(_cts.Token));
            Task.Run(() => BlockProductionLoop(_cts.Token));
            Console.WriteLine("[MAGNUM OPUS CORE] Transaction Engine & Matching Engine active.");
        }

        public void Stop()
        {
            _cts.Cancel();
        }

        private async Task ProcessMempoolLoop(CancellationToken token)
        {
            while (!token.IsCancellationRequested)
            {
                try
                {                    if (await _mempool.Reader.WaitToReadAsync(token))
                    {
                        while (_mempool.Reader.TryRead(out var tx))
                        {
                            _gasEstimator.RecordGasPrice(tx.GasPriceGwei);
                            Console.WriteLine($"[MEMPOOL INGEST] TxHash: {tx.Hash[..10]}... | Gas: {tx.GasPriceGwei} Gwei | From: {tx.FromAddress[..8]}...");
                        }
                    }
                }
                catch (OperationCanceledException) { break; }
                catch (Exception ex)
                {
                    Console.WriteLine($"[ENGINE ERROR] {ex.Message}");
                }
            }
        }

        private async Task BlockProductionLoop(CancellationToken token)
        {
            while (!token.IsCancellationRequested)
            {
                await Task.Delay(3000, token);
                _currentBlockHeight++;

                var txsToInclude = _mempool.GetPendingTransactions(25);
                foreach (var tx in txsToInclude)
                {
                    tx.Status = TransactionStatus.Confirmed;
                    tx.BlockNumber = _currentBlockHeight;
                    _mempool.RemoveTransaction(tx.Hash);
                }

                if (txsToInclude.Count > 0)
                {
                    Console.WriteLine($"[BLOCK #{_currentBlockHeight}] Produced block with {txsToInclude.Count} transactions.");
                }
            }
        }

        public MempoolManager Mempool => _mempool;
        public GasEstimator GasEstimator => _gasEstimator;
        public OrderBookMatchingEngine MatchingEngine => _matchingEngine;
    }
}