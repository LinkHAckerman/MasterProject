using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Numerics;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Threading;
using System.Threading.Channels;
using System.Threading.Tasks;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace MagnumOpus.Core.Blockchain;

/// <summary>
/// High-performance, multi-chain transaction processor with MEV protection,
/// gas optimization, and event-driven architecture.
/// </summary>
public sealed class TransactionProcessor : IAsyncDisposable
{
    private readonly ILogger<TransactionProcessor> _logger;
    private readonly TransactionProcessorOptions _options;
    private readonly ConcurrentDictionary<string, ChainClient> _chainClients;
    private readonly Channel<TransactionRequest> _submissionQueue;
    private readonly Channel<ProcessedTransaction> _completionChannel;
    private readonly ConcurrentDictionary<string, TransactionState> _pendingTransactions;
    private readonly Timer _gasPriceRefreshTimer;
    private readonly Timer _stuckTransactionTimer;
    private readonly SemaphoreSlim _nonceLock = new(1, 1);
    private readonly ConcurrentDictionary<ulong, NonceState> _nonceTracker = new();
    private readonly CancellationTokenSource _cancellationTokenSource = new();
    private readonly Task _processingTask;
    private readonly Task _confirmationTask;
    private readonly Task _gasOptimizationTask;
    private long _processedCount;
    private long _failedCount;
    private long _totalGasSaved;

    public TransactionProcessor(
        ILogger<TransactionProcessor> logger,
        IOptions<TransactionProcessorOptions> options,
        IEnumerable<ChainClient> chainClients)
    {
        _logger = logger ?? throw new ArgumentNullException(nameof(logger));
        _options = options?.Value ?? throw new ArgumentNullException(nameof(options));
        
        _chainClients = new ConcurrentDictionary<string, ChainClient>(
            chainClients?.ToDictionary(c => c.ChainId, c => c) 
                ?? throw new ArgumentNullException(nameof(chainClients)));
        
        _submissionQueue = Channel.CreateBounded<TransactionRequest>(new BoundedChannelOptions(_options.MaxQueueSize)
        {
            FullMode = BoundedChannelFullMode.Wait,
            SingleReader = true,
            SingleWriter = false
        });
        
        _completionChannel = Channel.CreateUnbounded<ProcessedTransaction>(new UnboundedChannelOptions
        {
            SingleReader = false,
            SingleWriter = true
        });
        
        _pendingTransactions = new ConcurrentDictionary<string, TransactionState>();
        
        _gasPriceRefreshTimer = new Timer(async _ => await RefreshGasPricesAsync(), null, 
            TimeSpan.Zero, _options.GasPriceRefreshInterval);
        
        _stuckTransactionTimer = new Timer(async _ => await HandleStuckTransactionsAsync(), null,
            _options.StuckTransactionCheckInterval, _options.StuckTransactionCheckInterval);
        
        _processingTask = ProcessQueueAsync(_cancellationTokenSource.Token);
        _confirmationTask = MonitorConfirmationsAsync(_cancellationTokenSource.Token);
        _gasOptimizationTask = OptimizeGasPricesAsync(_cancellationTokenSource.Token);
        
        _logger.LogInformation("TransactionProcessor initialized with {ChainCount} chains", _chainClients.Count);
    }

    /// <summary>
    /// Submits a transaction for processing with priority and MEV protection options.
    /// </summary>
    public async ValueTask<TransactionSubmissionResult> SubmitTransactionAsync(
        TransactionRequest request,
        CancellationToken cancellationToken = default)
    {
        if (request == null) throw new ArgumentNullException(nameof(request));
        
        var validationResult = ValidateRequest(request);
        if (!validationResult.IsValid)
        {
            return new TransactionSubmissionResult
            {
                Success = false,
                ErrorCode = validationResult.ErrorCode,
                ErrorMessage = validationResult.ErrorMessage
            };
        }

        // Apply MEV protection if requested
        if (request.MevProtection != MevProtectionLevel.None)
        {
            request = await ApplyMevProtectionAsync(request, cancellationToken);
        }

        // Optimize gas if enabled
        if (_options.EnableGasOptimization && request.GasPrice == null)
        {
            request = await OptimizeGasPriceAsync(request, cancellationToken);
        }

        // Assign nonce
        request = await AssignNonceAsync(request, cancellationToken);

        var txId = GenerateTransactionId(request);
        var state = new TransactionState
        {
            Id = txId,
            Request = request,
            Status = TransactionStatus.Queued,
            CreatedAt = DateTimeOffset.UtcNow,
            ChainId = request.ChainId,
            RetryCount = 0
        };

        _pendingTransactions[txId] = state;
        
        await _submissionQueue.Writer.WriteAsync(request with { Id = txId }, cancellationToken);
        
        Interlocked.Increment(ref _processedCount);
        
        _logger.LogDebug("Transaction {TxId} queued for chain {ChainId}", txId, request.ChainId);
        
        return new TransactionSubmissionResult
        {
            Success = true,
            TransactionId = txId,
            EstimatedConfirmationTime = EstimateConfirmationTime(request.ChainId, request.Priority)
        };
    }

    /// <summary>
    /// Gets real-time transaction status.
    /// </summary>
    public TransactionStatusInfo GetTransactionStatus(string transactionId)
    {
        if (_pendingTransactions.TryGetValue(transactionId, out var state))
        {
            return new TransactionStatusInfo
            {
                TransactionId = state.Id,
                Status = state.Status,
                ChainId = state.ChainId,
                SubmittedAt = state.SubmittedAt,
                ConfirmedAt = state.ConfirmedAt,
                BlockNumber = state.BlockNumber,
                TransactionHash = state.TransactionHash,
                GasUsed = state.GasUsed,
                EffectiveGasPrice = state.EffectiveGasPrice,
                ErrorMessage = state.ErrorMessage,
                RetryCount = state.RetryCount
            };
        }

        return new TransactionStatusInfo { TransactionId = transactionId, Status = TransactionStatus.NotFound };
    }

    /// <summary>
    /// Subscribes to transaction completion events.
    /// </summary>
    public IAsyncEnumerable<ProcessedTransaction> SubscribeToCompletions(CancellationToken cancellationToken = default)
    {
        return _completionChannel.Reader.ReadAllAsync(cancellationToken);
    }

    /// <summary>
    /// Gets processor metrics.
    /// </summary>
    public ProcessorMetrics GetMetrics()
    {
        return new ProcessorMetrics
        {
            ProcessedCount = Interlocked.Read(ref _processedCount),
            FailedCount = Interlocked.Read(ref _failedCount),
            PendingCount = _pendingTransactions.Count,
            QueueDepth = _submissionQueue.Reader.Count,
            TotalGasSaved = Interlocked.Read(ref _totalGasSaved),
            AverageConfirmationTimeMs = CalculateAverageConfirmationTime(),
            ChainMetrics = _chainClients.Values.Select(c => c.GetMetrics()).ToList()
        };
    }

    /// <summary>
    /// Cancels a pending transaction by sending a replacement with higher gas.
    /// </summary>
    public async ValueTask<CancellationResult> CancelTransactionAsync(string transactionId, CancellationToken cancellationToken = default)
    {
        if (!_pendingTransactions.TryGetValue(transactionId, out var state))
        {
            return new CancellationResult { Success = false, ErrorMessage = "Transaction not found" };
        }

        if (state.Status is TransactionStatus.Confirmed or TransactionStatus.Finalized)
        {
            return new CancellationResult { Success = false, ErrorMessage = "Transaction already confirmed" };
        }

        var cancelRequest = new TransactionRequest
        {
            ChainId = state.Request.ChainId,
            From = state.Request.From,
            To = state.Request.From, // Self-transfer to cancel
            Value = BigInteger.Zero,
            Data = Array.Empty<byte>(),
            GasLimit = 21000,
            GasPrice = (ulong?)(state.Request.GasPrice * 1.5), // 50% increase
            Priority = TransactionPriority.High,
            Nonce = state.Request.Nonce,
            Type = TransactionType.Cancellation
        };

        var result = await SubmitTransactionAsync(cancelRequest, cancellationToken);
        
        if (result.Success)
        {
            state.Status = TransactionStatus.Cancelling;
            state.CancellationTxId = result.TransactionId;
        }

        return new CancellationResult { Success = result.Success, CancellationTransactionId = result.TransactionId };
    }

    /// <summary>
    /// Speeds up a pending transaction by replacing with higher gas price.
    /// </summary>
    public async ValueTask<SpeedUpResult> SpeedUpTransactionAsync(string transactionId, double gasPriceMultiplier = 1.25, CancellationToken cancellationToken = default)
    {
        if (!_pendingTransactions.TryGetValue(transactionId, out var state))
        {
            return new SpeedUpResult { Success = false, ErrorMessage = "Transaction not found" };
        }

        if (state.Status is TransactionStatus.Confirmed or TransactionStatus.Finalized)
        {
            return new SpeedUpResult { Success = false, ErrorMessage = "Transaction already confirmed" };
        }

        if (gasPriceMultiplier <= 1.0)
        {
            return new SpeedUpResult { Success = false, ErrorMessage = "Multiplier must be > 1.0" };
        }

        var newGasPrice = (ulong)(state.Request.GasPrice * gasPriceMultiplier);
        var speedUpRequest = state.Request with
        {
            GasPrice = newGasPrice,
            Priority = TransactionPriority.High
        };

        var result = await SubmitTransactionAsync(speedUpRequest, cancellationToken);
        
        if (result.Success)
        {
            state.Status = TransactionStatus.SpeedingUp;
            state.SpeedUpTxId = result.TransactionId;
        }

        return new SpeedUpResult { Success = result.Success, NewTransactionId = result.TransactionId, NewGasPrice = newGasPrice };
    }

    private async Task ProcessQueueAsync(CancellationToken cancellationToken)
    {
        await foreach (var request in _submissionQueue.Reader.ReadAllAsync(cancellationToken))
        {
            try
            {
                await ProcessTransactionAsync(request, cancellationToken);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error processing transaction {TxId}", request.Id);
                await HandleTransactionFailureAsync(request.Id, ex, cancellationToken);
            }
        }
    }

    private async Task ProcessTransactionAsync(TransactionRequest request, CancellationToken cancellationToken)
    {
        var stopwatch = Stopwatch.StartNew();
        
        if (!_pendingTransactions.TryGetValue(request.Id, out var state))
        {
            _logger.LogWarning("Transaction {TxId} not found in pending state", request.Id);
            return;
        }

        state.Status = TransactionStatus.Signing;
        state.SubmittedAt = DateTimeOffset.UtcNow;

        if (!_chainClients.TryGetValue(request.ChainId, out var client))
        {
            throw new InvalidOperationException($