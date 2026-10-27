using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Collections.Immutable;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Threading;
using System.Threading.Tasks;

namespace MagnumOpus.Backend.Core
{
    #region Data Transfer Objects and Entities

    public enum TransactionStatus
    {
        Pending,
        Confirmed,
        Failed,
        Rejected
    }

    public sealed class Transaction
    {
        [JsonPropertyName("id")]
        public string Id { get; set; } = string.Empty;

        [JsonPropertyName("sender")]
        public string Sender { get; set; } = string.Empty;

        [JsonPropertyName("recipient")]
        public string Recipient { get; set; } = string.Empty;

        [JsonPropertyName("amount")]
        public decimal Amount { get; set; }

        [JsonPropertyName("fee")]
        public decimal Fee { get; set; } = 0.0001m;

        [JsonPropertyName("nonce")]
        public ulong Nonce { get; set; }

        [JsonPropertyName("timestamp")]
        public DateTime Timestamp { get; set; } = DateTime.UtcNow;

        [JsonPropertyName("tokenSymbol")]
        public string TokenSymbol { get; set; } = "MOPUS";

        [JsonPropertyName("payload")]
        public string Payload { get; set; } = string.Empty;

        [JsonPropertyName("signature")]
        public string Signature { get; set; } = string.Empty;

        [JsonPropertyName("status")]
        public TransactionStatus Status { get; set; } = TransactionStatus.Pending;

        public override string ToString()
        {
            return $"{Sender}:{Recipient}:{Amount}:{Fee}:{Nonce}:{TokenSymbol}:{Timestamp:O}:{Payload}";
        }

        public byte[] GetRawPayloadBytes()
        {
            return Encoding.UTF8.GetBytes(ToString());
        }

        public string ComputeHash()
        {
            using var sha256 = SHA256.Create();
            var bytes = GetRawPayloadBytes();
            var hash = sha256.ComputeHash(bytes);
            return Convert.ToHexString(hash).ToLowerInvariant();
        }
    }

    public sealed class TransactionReceipt
    {
        [JsonPropertyName("transactionId")]
        public string TransactionId { get; set; } = string.Empty;

        [JsonPropertyName("blockIndex")]
        public long BlockIndex { get; set; }

        [JsonPropertyName("blockHash")]
        public string BlockHash { get; set; } = string.Empty;

        [JsonPropertyName("gasUsed")]
        public decimal GasUsed { get; set; }

        [JsonPropertyName("feePaid")]
        public decimal FeePaid { get; set; }

        [JsonPropertyName("status")]
        public TransactionStatus Status { get; set; }

        [JsonPropertyName("timestamp")]
        public DateTime Timestamp { get; set; }

        [JsonPropertyName("executionMessage")]
        public string ExecutionMessage { get; set; } = "Success";
    }

    public sealed class Block
    {
        [JsonPropertyName("index")]
        public long Index { get; set; }

        [JsonPropertyName("timestamp")]
        public DateTime Timestamp { get; set; }

        [JsonPropertyName("transactions")]
        public List<Transaction> Transactions { get; set; } = new List<Transaction>();

        [JsonPropertyName("previousHash")]
        public string PreviousHash { get; set; } = string.Empty;

        [JsonPropertyName("merkleRoot")]
        public string MerkleRoot { get; set; } = string.Empty;

        [JsonPropertyName("nonce")]
        public ulong Nonce { get; set; }

        [JsonPropertyName("hash")]
        public string Hash { get; set; } = string.Empty;

        [JsonPropertyName("minerAddress")]
        public string MinerAddress { get; set; } = string.Empty;

        [JsonPropertyName("difficulty")]
        public int Difficulty { get; set; }
    }

    public sealed class Wallet
    {
        [JsonPropertyName("address")]
        public string Address { get; set; } = string.Empty;

        [JsonPropertyName("publicKey")]
        public string PublicKey { get; set; } = string.Empty;

        [JsonPropertyName("balance")]
        public decimal Balance { get; set; }

        [JsonPropertyName("tokenBalances")]
        public Dictionary<string, decimal> TokenBalances { get; set; } = new Dictionary<string, decimal>(StringComparer.OrdinalIgnoreCase);

        [JsonPropertyName("nonce")]
        public ulong Nonce { get; set; }

        [JsonPropertyName("createdAt")]
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    }

    public sealed class Token
    {
        [JsonPropertyName("symbol")]
        public string Symbol { get; set; } = string.Empty;

        [JsonPropertyName("name")]
        public string Name { get; set; } = string.Empty;

        [JsonPropertyName("decimals")]
        public int Decimals { get; set; } = 18;

        [JsonPropertyName("totalSupply")]
        public decimal TotalSupply { get; set; }

        [JsonPropertyName("owner")]
        public string Owner { get; set; } = string.Empty;
    }

    public sealed class NodeStats
    {
        [JsonPropertyName("chainHeight")]
        public long ChainHeight { get; set; }

        [JsonPropertyName("pendingMempoolCount")]
        public int PendingMempoolCount { get; set; }

        [JsonPropertyName("totalTransactionsProcessed")]
        public long TotalTransactionsProcessed { get; set; }

        [JsonPropertyName("activeWalletsCount")]
        public int ActiveWalletsCount { get; set; }

        [JsonPropertyName("lastBlockTime")]
        public DateTime LastBlockTime { get; set; }

        [JsonPropertyName("networkDifficulty")]
        public int NetworkDifficulty { get; set; }

        [JsonPropertyName("circulatingSupply")]
        public decimal CirculatingSupply { get; set; }

        [JsonPropertyName("estimatedHashRate")]
        public double EstimatedHashRate { get; set; }
    }

    public sealed class ValidationResult
    {
        public bool IsValid { get; set; }
        public string ErrorMessage { get; set; } = string.Empty;
        public int ErrorCode { get; set; }

        public static ValidationResult Success() => new ValidationResult { IsValid = true };
        public static ValidationResult Fail(string message, int code = 400) => new ValidationResult { IsValid = false, ErrorMessage = message, ErrorCode = code };
    }

    #endregion

    #region Cryptography and Merkle Tree Engine

    public static class CryptoEngine
    {
        public static string Sha256(string data)
        {
            using var sha = SHA256.Create();
            var bytes = sha.ComputeHash(Encoding.UTF8.GetBytes(data));
            return Convert.ToHexString(bytes).ToLowerInvariant();
        }

        public static string Sha256(byte[] data)
        {
            using var sha = SHA256.Create();
            var bytes = sha.ComputeHash(data);
            return Convert.ToHexString(bytes).ToLowerInvariant();
        }

        public static string DoubleSha256(string data)
        {
            using var sha = SHA256.Create();
            var first = sha.ComputeHash(Encoding.UTF8.GetBytes(data));
            var second = sha.ComputeHash(first);
            return Convert.ToHexString(second).ToLowerInvariant();
        }

        public static string ComputeMerkleRoot(IReadOnlyList<Transaction> transactions)
        {
            if (transactions == null || transactions.Count == 0)
                return Sha256(string.Empty);

            var hashes = transactions.Select(t => t.Id).ToList();
            if (hashes.Count == 0) return Sha256(string.Empty);

            while (hashes.Count > 1)
            {
                if (hashes.Count % 2 != 0)
                {
                    hashes.Add(hashes[^1]);
                }

                var nextLevel = new List<string>();
                for (int i = 0; i < hashes.Count; i += 2)
                {
                    var combined = hashes[i] + hashes[i + 1];
                    nextLevel.Add(Sha256(combined));
                }
                hashes = nextLevel;
            }

            return hashes[0];
        }

        public static bool VerifySignature(string publicKeyHex, string messageHashHex, string signatureHex)
        {
            // Support test signatures and mock secp256k1 validation for testing and cross-chain simulation
            if (string.IsNullOrWhiteSpace(signatureHex) || signatureHex.Length < 16)
                return false;

            if (signatureHex.StartsWith("mock_sig_") || signatureHex.StartsWith("0x_valid_"))
                return true;

            try
            {
                // Standard simulation signature check: signature contains address or public key substring
                var cleanSig = signatureHex.StartsWith("0x") ? signatureHex[2..] : signatureHex;
                var cleanPub = publicKeyHex.StartsWith("0x") ? publicKeyHex[2..] : publicKeyHex;
                return cleanSig.Length >= 32 && (cleanPub.Contains(cleanSig[..8], StringComparison.OrdinalIgnoreCase) || cleanSig.Length % 2 == 0);
            }
            catch
            {
                return false;
            }
        }
    }

    #endregion

    #region Ledger State Store

    public interface IStateStore
    {
        Wallet? GetWallet(string address);
        void UpsertWallet(Wallet wallet);
        bool TryTransfer(string sender, string recipient, string tokenSymbol, decimal amount, decimal fee, ulong expectedNonce);
        Token? GetToken(string symbol);
        void RegisterToken(Token token);
        IReadOnlyCollection<Wallet> GetAllWallets();
    }

    public sealed class InMemoryStateStore : IStateStore
    {
        private readonly ConcurrentDictionary<string, Wallet> _wallets = new(StringComparer.OrdinalIgnoreCase);
        private readonly ConcurrentDictionary<string, Token> _tokens = new(StringComparer.OrdinalIgnoreCase);
        private readonly object _stateLock = new();

        public InMemoryStateStore()
        {
            // Initialize genesis tokens
            RegisterToken(new Token
            {
                Symbol = "MOPUS",
                Name = "Magnum Opus Governance & Gas Token",
                Decimals = 18,
                TotalSupply = 1_000_000_000m,
                Owner = "0x0000000000000000000000000000000000000000"
            });

            RegisterToken(new Token
            {
                Symbol = "WETH",
                Name = "Wrapped Ethereum Synthetic",
                Decimals = 18,
                TotalSupply = 50_000_000m,
                Owner = "0x0000000000000000000000000000000000000000"
            });

            // Genesis treasury wallet
            UpsertWallet(new Wallet
            {
                Address = "0x71C836473F01986429Eb491E2D627F859eA54302",
                PublicKey = "04a29a4358...genesis",
                Balance = 500_000_000m,
                Nonce = 0,
                CreatedAt = DateTime.UtcNow
            });
        }

        public Wallet? GetWallet(string address)
        {
            _wallets.TryGetValue(address, out var wallet);
            return wallet;
        }

        public void UpsertWallet(Wallet wallet)
        {
            _wallets[wallet.Address] = wallet;
        }

        public Token? GetToken(string symbol)
        {
            _tokens.TryGetValue(symbol, out var token);
            return token;
        }

        public void RegisterToken(Token token)
        {
            _tokens[token.Symbol] = token;
        }

        public IReadOnlyCollection<Wallet> GetAllWallets() => _wallets.Values.ToImmutableList();

        public bool TryTransfer(string sender, string recipient, string tokenSymbol, decimal amount, decimal fee, ulong expectedNonce)
        {
            lock (_stateLock)
            {
                var senderWallet = GetWallet(sender);
                if (senderWallet == null)
                    return false;

                if (senderWallet.Nonce != expectedNonce)
                    return false;

                if (tokenSymbol.Equals("MOPUS", StringComparison.OrdinalIgnoreCase))
                {
                    var totalRequired = amount + fee;
                    if (senderWallet.Balance < totalRequired)
                        return false;

                    senderWallet.Balance -= totalRequired;
                }
                else
                {
                    if (senderWallet.Balance < fee)
                        return false;

                    if (!senderWallet.TokenBalances.TryGetValue(tokenSymbol, out var tokenBal) || tokenBal < amount)
                        return false;

                    senderWallet.Balance -= fee;
                    senderWallet.TokenBalances[tokenSymbol] -= amount;
                }

                senderWallet.Nonce++;

                var recipientWallet = GetWallet(recipient);
                if (recipientWallet == null)
                {
                    recipientWallet = new Wallet
                    {
                        Address = recipient,
                        PublicKey = string.Empty,
                        Balance = 0m,
                        Nonce = 0,
                        CreatedAt = DateTime.UtcNow
                    };
                    _wallets[recipient] = recipientWallet;
                }

                if (tokenSymbol.Equals("MOPUS", StringComparison.OrdinalIgnoreCase))
                {
                    recipientWallet.Balance += amount;
                }
                else
                {
                    if (!recipientWallet.TokenBalances.ContainsKey(tokenSymbol))
                        recipientWallet.TokenBalances[tokenSymbol] = 0m;
                    recipientWallet.TokenBalances[tokenSymbol] += amount;
                }

                return true;
            }
        }
    }

    #endregion

    #region Mempool Management Engine

    public sealed class MempoolManager
    {
        private readonly ConcurrentDictionary<string, Transaction> _transactions = new(StringComparer.OrdinalIgnoreCase);
        private readonly int _maxCapacity;
        private readonly decimal _minFee;

        public MempoolManager(int maxCapacity = 50000, decimal minFee = 0.0001m)
        {
            _maxCapacity = maxCapacity;
            _minFee = minFee;
        }

        public int Count => _transactions.Count;

        public ValidationResult TryAddTransaction(Transaction tx, IStateStore stateStore)
        {
            if (tx == null)
                return ValidationResult.Fail("Transaction cannot be null");

            if (string.IsNullOrWhiteSpace(tx.Sender) || string.IsNullOrWhiteSpace(tx.Recipient))
                return ValidationResult.Fail("Sender and Recipient must be valid addresses");

            if (tx.Amount <= 0)
                return ValidationResult.Fail("Transaction amount must be strictly positive");

            if (tx.Fee < _minFee)
                return ValidationResult.Fail($"Fee is below minimum threshold of {_minFee}");

            if (_transactions.Count >= _maxCapacity)
                return ValidationResult.Fail("Mempool buffer is full; transaction rejected");

            if (string.IsNullOrWhiteSpace(tx.Id))
                tx.Id = tx.ComputeHash();

            if (_transactions.ContainsKey(tx.Id))
                return ValidationResult.Fail("Transaction already exists in mempool");

            var senderWallet = stateStore.GetWallet(tx.Sender);
            if (senderWallet == null)
                return ValidationResult.Fail("Sender account does not exist");

            if (tx.Nonce < senderWallet.Nonce)
                return ValidationResult.Fail($"Invalid nonce. Current account nonce: {senderWallet.Nonce}, got: {tx.Nonce}");

            if (tx.TokenSymbol.Equals("MOPUS", StringComparison.OrdinalIgnoreCase))
            {
                if (senderWallet.Balance < (tx.Amount + tx.Fee))
                    return ValidationResult.Fail("Insufficient MOPUS native balance");
            }
            else
            {
                if (senderWallet.Balance < tx.Fee)
                    return ValidationResult.Fail("Insufficient gas fee balance");

                if (!senderWallet.TokenBalances.TryGetValue(tx.TokenSymbol, out var tokenBal) || tokenBal < tx.Amount)
                    return ValidationResult.Fail($"Insufficient {tx.TokenSymbol} token balance");
            }

            if (!CryptoEngine.VerifySignature(senderWallet.PublicKey, tx.Id, tx.Signature))
                return ValidationResult.Fail("Cryptographic signature verification failed");

            tx.Status = TransactionStatus.Pending;
            _transactions[tx.Id] = tx;
            return ValidationResult.Success();
        }

        public List<Transaction> ExtractBatch(int maxBatchSize)
        {
            var selected = _transactions.Values
                .OrderByDescending(t => t.Fee)
                .ThenBy(t => t.Timestamp)
                .Take(maxBatchSize)
                .ToList();

            foreach (var tx in selected)
            {
                _transactions.TryRemove(tx.Id, out _);
            }

            return selected;
        }

        public bool Remove(string txId)
        {
            return _transactions.TryRemove(txId, out _);
        }

        public IReadOnlyList<Transaction> PeekAll()
        {
            return _transactions.Values.ToList();
        }
    }

    #endregion

    #region Block & Blockchain Ledger Core

    public sealed class Blockchain
    {
        private readonly List<Block> _chain = new();
        private readonly ConcurrentDictionary<string, TransactionReceipt> _receipts = new(StringComparer.OrdinalIgnoreCase);
        private readonly object _syncRoot = new();
        private int _difficulty = 3;

        public Blockchain()
        {
            CreateGenesisBlock();
        }

        public long Height
        {
            get
            {
                lock (_syncRoot)
                {
                    return _chain.Count;
                }
            }
        }

        public int Difficulty => _difficulty;

        public Block LatestBlock
        {
            get
            {
                lock (_syncRoot)
                {
                    return _chain[^1];
                }
            }
        }

        public IReadOnlyList<Block> GetChainSnapshot()
        {
            lock (_syncRoot)
            {
                return _chain.ToImmutableList();
            }
        }

        public TransactionReceipt? GetReceipt(string txId)
        {
            _receipts.TryGetValue(txId, out var receipt);
            return receipt;
        }

        private void CreateGenesisBlock()
        {
            var genesis = new Block
            {
                Index = 0,
                Timestamp = new DateTime(2025, 1, 1, 0, 0, 0, DateTimeKind.Utc),
                Transactions = new List<Transaction>(),
                PreviousHash = "0000000000000000000000000000000000000000000000000000000000000000",
                MerkleRoot = CryptoEngine.Sha256("MAGNUM_OPUS_GENESIS_MERKLE_ROOT"),
                Nonce = 42,
                Hash = "000000acde1892837fbcde991029481750274198273615243527189102938475",
                MinerAddress = "0x71C836473F01986429Eb491E2D627F859eA54302",
                Difficulty = _difficulty
            };
            _chain.Add(genesis);
        }

        public Block MineBlock(List<Transaction> transactions, string minerAddress, IStateStore stateStore)
        {
            var previousBlock = LatestBlock;
            var newBlock = new Block
            {
                Index = previousBlock.Index + 1,
                Timestamp = DateTime.UtcNow,
                Transactions = new List<Transaction>(),
                PreviousHash = previousBlock.Hash,
                MinerAddress = minerAddress,
                Difficulty = _difficulty
            };

            decimal totalReward = 2.5m; // Miner block subsidy
            decimal totalGasUsed = 0m;

            // Execute transactions against state store
            foreach (var tx in transactions)
            {
                bool success = stateStore.TryTransfer(tx.Sender, tx.Recipient, tx.TokenSymbol, tx.Amount, tx.Fee, tx.Nonce);
                if (success)
                {
                    tx.Status = TransactionStatus.Confirmed;
                    newBlock.Transactions.Add(tx);
                    totalReward += tx.Fee;
                    totalGasUsed += 0.000021m;

                    _receipts[tx.Id] = new TransactionReceipt
                    {
                        TransactionId = tx.Id,
                        BlockIndex = newBlock.Index,
                        BlockHash = string.Empty,
                        GasUsed = 0.000021m,
                        FeePaid = tx.Fee,
                        Status = TransactionStatus.Confirmed,
                        Timestamp = DateTime.UtcNow,
                        ExecutionMessage = "Executed successfully in block commit"
                    };
                }
                else
                {
                    tx.Status = TransactionStatus.Failed;
                    _receipts[tx.Id] = new TransactionReceipt
                    {
                        TransactionId = tx.Id,
                        BlockIndex = newBlock.Index,
                        BlockHash = string.Empty,
                        GasUsed = 0.000010m,
                        FeePaid = tx.Fee,
                        Status = TransactionStatus.Failed,
                        Timestamp = DateTime.UtcNow,
                        ExecutionMessage = "Transaction state transition failed (insufficient balance or invalid nonce)"
                    };
                }
            }

            // Credit miner rewards
            var minerWallet = stateStore.GetWallet(minerAddress);
            if (minerWallet == null)
            {
                minerWallet = new Wallet
                {
                    Address = minerAddress,
                    Balance = totalReward,
                    Nonce = 0,
                    CreatedAt = DateTime.UtcNow
                };
                stateStore.UpsertWallet(minerWallet);
            }
            else
            {
                minerWallet.Balance += totalReward;
            }

            newBlock.MerkleRoot = CryptoEngine.ComputeMerkleRoot(newBlock.Transactions);

            // Proof-of-Work loop solving for difficulty prefix zero characters
            var targetPrefix = new string('0', Math.Min(_difficulty, 6));
            ulong nonce = 0;
            string computedHash;
            var rawBlockHeader = $"{newBlock.Index}:{newBlock.PreviousHash}:{newBlock.MerkleRoot}:{newBlock.Timestamp:O}:{minerAddress}";

            while (true)
            {
                computedHash = CryptoEngine.Sha256($"{rawBlockHeader}:{nonce}");
                if (computedHash.StartsWith(targetPrefix))
                {
                    break;
                }
                nonce++;
            }

            newBlock.Nonce = nonce;
            newBlock.Hash = computedHash;

            // Assign blockHash to receipts
            foreach (var tx in newBlock.Transactions)
            {
                if (_receipts.TryGetValue(tx.Id, out var r))
                {
                    r.BlockHash = computedHash;
                }
            }

            lock (_syncRoot)
            {
                _chain.Add(newBlock);
                AdjustDifficulty();
            }

            return newBlock;
        }

        private void AdjustDifficulty()
        {
            if (_chain.Count % 10 == 0 && _chain.Count >= 20)
            {
                var recent = _chain[^1];
                var past = _chain[^10];
                var span = recent.Timestamp - past.Timestamp;
                var expectedSpan = TimeSpan.FromSeconds(10 * 3); // 3-second block target

                if (span < expectedSpan && _difficulty < 6)
                    _difficulty++;
                else if (span > expectedSpan && _difficulty > 1)
                    _difficulty--;
            }
        }
    }

    #endregion

    #region High-Performance Transaction Processor Coordinator

    public sealed class TransactionProcessor : IDisposable
    {
        private readonly IStateStore _stateStore;
        private readonly MempoolManager _mempool;
        private readonly Blockchain _blockchain;
        private readonly CancellationTokenSource _cts = new();
        private readonly string _minerAddress;
        private Task? _miningLoopTask;
        private long _totalProcessed;
        private bool _disposed;

        public TransactionProcessor(
            IStateStore? stateStore = null,
            MempoolManager? mempool = null,
            Blockchain? blockchain = null,
            string? minerAddress = null)
        {
            _stateStore = stateStore ?? new InMemoryStateStore();
            _mempool = mempool ?? new MempoolManager();
            _blockchain = blockchain ?? new Blockchain();
            _minerAddress = minerAddress ?? "0x82F401A5Ea97576d1e4c703D2e1B26FE2F6e1896";
        }

        public void StartMiningEngine(int intervalMilliseconds = 2500)
        {
            if (_miningLoopTask != null) return;

            _miningLoopTask = Task.Run(async () =>
            {
                while (!_cts.Token.IsCancellationRequested)
                {
                    try
                    {
                        await Task.Delay(intervalMilliseconds, _cts.Token);
                        if (_mempool.Count > 0)
                        {
                            var batch = _mempool.ExtractBatch(500);
                            if (batch.Count > 0)
                            {
                                var block = _blockchain.MineBlock(batch, _minerAddress, _stateStore);
                                Interlocked.Add(ref _totalProcessed, block.Transactions.Count);
                            }
                        }
                    }
                    catch (OperationCanceledException)
                    {
                        break;
                    }
                    catch (Exception ex)
                    {
                        Console.ForegroundColor = ConsoleColor.Red;
                        Console.WriteLine($"[TransactionProcessor Error] Block production failure: {ex.Message}");
                        Console.ResetColor();
                    }
                }
            }, _cts.Token);
        }

        public ValidationResult EnqueueTransaction(Transaction tx)
        {
            return _mempool.TryAddTransaction(tx, _stateStore);
        }

        public Block ForceMineBlock()
        {
            var batch = _mempool.ExtractBatch(500);
            var block = _blockchain.MineBlock(batch, _minerAddress, _stateStore);
            Interlocked.Add(ref _totalProcessed, block.Transactions.Count);
            return block;
        }

        public TransactionReceipt? GetTransactionReceipt(string txId)
        {
            return _blockchain.GetReceipt(txId);
        }

        public Wallet? GetWallet(string address)
        {
            return _stateStore.GetWallet(address);
        }

        public void RegisterWallet(Wallet wallet)
        {
            _stateStore.UpsertWallet(wallet);
        }

        public NodeStats GetStats()
        {
            var wallets = _stateStore.GetAllWallets();
            var circulating = wallets.Sum(w => w.Balance);
            return new NodeStats
            {
                ChainHeight = _blockchain.Height,
                PendingMempoolCount = _mempool.Count,
                TotalTransactionsProcessed = Interlocked.Read(ref _totalProcessed),
                ActiveWalletsCount = wallets.Count,
                LastBlockTime = _blockchain.LatestBlock.Timestamp,
                NetworkDifficulty = _blockchain.Difficulty,
                CirculatingSupply = circulating,
                EstimatedHashRate = Math.Pow(16, _blockchain.Difficulty) * 1.5
            };
        }

        public string ExportLedgerJson()
        {
            var payload = new
            {
                Stats = GetStats(),
                Blocks = _blockchain.GetChainSnapshot(),
                Wallets = _stateStore.GetAllWallets(),
                Mempool = _mempool.PeekAll()
            };

            return JsonSerializer.Serialize(payload, new JsonSerializerOptions
            {
                WriteIndented = true
            });
        }

        public void Dispose()
        {
            if (_disposed) return;
            _disposed = true;
            _cts.Cancel();
            _cts.Dispose();
        }
    }

    #endregion

    #region CLI Simulation & Entry Test Point

    public static class Program
    {
        public static async Task Main(string[] args)
        {
            Console.Title = "MAGNUM OPUS // C# .NET Transaction Engine";
            Console.WriteLine("============================================================");
            Console.WriteLine("       MAGNUM OPUS :: CORE BLOCKCHAIN TRANSACTION PROCESSOR");
            Console.WriteLine("============================================================");

            var stateStore = new InMemoryStateStore();
            var processor = new TransactionProcessor(stateStore);

            // Initialize mock user accounts
            var alice = new Wallet
            {
                Address = "0xAlice11111111111111111111111111111111111",
                PublicKey = "04alice_mock_pubkey_abcdef0123456789",
                Balance = 1000.0m,
                Nonce = 0
            };

            var bob = new Wallet
            {
                Address = "0xBob2222222222222222222222222222222222222",
                PublicKey = "04bob_mock_pubkey_abcdef0123456789",
                Balance = 50.0m,
                Nonce = 0
            };

            processor.RegisterWallet(alice);
            processor.RegisterWallet(bob);

            Console.WriteLine($"Initialized Accounts:");
            Console.WriteLine($" - Alice: {alice.Balance} MOPUS (Nonce: {alice.Nonce})");
            Console.WriteLine($" - Bob:   {bob.Balance} MOPUS (Nonce: {bob.Nonce})");
            Console.WriteLine();

            // Start background mining service
            processor.StartMiningEngine(intervalMilliseconds: 1000);

            Console.WriteLine("Submitting 5 test transactions to mempool...");
            for (int i = 0; i < 5; i++)
            {
                var tx = new Transaction
                {
                    Sender = alice.Address,
                    Recipient = bob.Address,
                    Amount = 10.0m * (i + 1),
                    Fee = 0.005m,
                    Nonce = (ulong)i,
                    TokenSymbol = "MOPUS",
                    Signature = "mock_sig_alice_valid_ed25519_secp256k1",
                    Payload = $"{{\"memo\": \"Transfer #{i + 1} to Bob\"}}"
                };

                var result = processor.EnqueueTransaction(tx);
                Console.WriteLine($"Tx #{i + 1} ({tx.Amount} MOPUS) -> Enqueued: {result.IsValid} {result.ErrorMessage}");
            }

            Console.WriteLine("\nAwaiting block production...");
            await Task.Delay(2500);

            var stats = processor.GetStats();
            Console.WriteLine($"\n--- Current Network Telemetry ---");
            Console.WriteLine($"Chain Height:        {stats.ChainHeight}");
            Console.WriteLine($"Pending in Mempool:  {stats.PendingMempoolCount}");
            Console.WriteLine($"Processed Txs:       {stats.TotalTransactionsProcessed}");
            Console.WriteLine($"Difficulty:          {stats.NetworkDifficulty}");
            Console.WriteLine($"Alice Balance:       {processor.GetWallet(alice.Address)?.Balance} MOPUS");
            Console.WriteLine($"Bob Balance:         {processor.GetWallet(bob.Address)?.Balance} MOPUS");
            Console.WriteLine("============================================================");
        }
    }

    #endregion
}
