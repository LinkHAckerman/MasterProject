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
        public long ChainHeight { get; set; }
        public int PendingTransactionCount { get; set; }
        public int KnownWalletsCount { get; set; }
        public int KnownTokensCount { get; set; }
        public int Difficulty { get; set; }
        public decimal MiningReward { get; set; }
        public string LatestBlockHash { get; set; } = string.Empty;
    }

    #endregion

    #region Core Engine

    public class TransactionProcessor
    {
        private readonly Dictionary<string, Wallet> _wallets;
        private readonly Dictionary<string, Token> _tokens;
        private readonly List<Transaction> _pendingTransactions;
        private readonly List<Block> _blockchain;
        private readonly ConcurrentDictionary<string, TransactionReceipt> _receipts;
        private readonly int _difficulty;
        private readonly decimal _miningReward;
        private readonly object _lock = new object();

        public const string NativeTokenSymbol = "MOPUS";
        public const string GenesisAddress = "0x0000000000000000000000000000000000000000";

        public TransactionProcessor(int difficulty = 4, decimal miningReward = 10.0m)
        {
            _difficulty = Math.Max(1, difficulty);
            _miningReward = miningReward;
            _wallets = new Dictionary<string, Wallet>(StringComparer.OrdinalIgnoreCase);
            _tokens = new Dictionary<string, Token>(StringComparer.OrdinalIgnoreCase);
            _pendingTransactions = new List<Transaction>();
            _blockchain = new List<Block>();
            _receipts = new ConcurrentDictionary<string, TransactionReceipt>();

            // Register native token
            _tokens[NativeTokenSymbol] = new Token
            {
                Symbol = NativeTokenSymbol,
                Name = "Magnum Opus Native Utility Token",
                Decimals = 18,
                TotalSupply = 1_000_000_000m,
                Owner = GenesisAddress
            };

            // Register genesis wallet
            _wallets[GenesisAddress] = new Wallet
            {
                Address = GenesisAddress,
                PublicKey = "GENESIS_PUBLIC_KEY",
                Balance = 1_000_000_000m,
                Nonce = 0
            };

            // Initialize with Genesis Block
            _blockchain.Add(CreateGenesisBlock());
        }

        #region Genesis & Hashing

        private Block CreateGenesisBlock()
        {
            var genesisTx = new Transaction
            {
                Id = ComputeSha256("genesis_initial_allocation"),
                Sender = GenesisAddress,
                Recipient = GenesisAddress,
                Amount = 0,
                Fee = 0,
                Nonce = 0,
                Timestamp = new DateTime(2025, 1, 1, 0, 0, 0, DateTimeKind.Utc),
                TokenSymbol = NativeTokenSymbol,
                Payload = "Magnum Opus: Inception of Next-Gen DeFi Engine",
                Signature = "genesis_signature",
                Status = TransactionStatus.Confirmed
            };

            var txList = new List<Transaction> { genesisTx };
            var merkleRoot = CalculateMerkleRoot(txList);
            var timestamp = new DateTime(2025, 1, 1, 0, 0, 0, DateTimeKind.Utc);
            var hash = CalculateHash(0, timestamp, txList, GenesisAddress, 0);

            var block = new Block
            {
                Index = 0,
                Timestamp = timestamp,
                Transactions = txList,
                PreviousHash = GenesisAddress,
                MerkleRoot = merkleRoot,
                Nonce = 0,
                Hash = hash,
                MinerAddress = GenesisAddress,
                Difficulty = _difficulty
            };

            _receipts[genesisTx.Id] = new TransactionReceipt
            {
                TransactionId = genesisTx.Id,
                BlockIndex = 0,
                BlockHash = hash,
                GasUsed = 0,
                FeePaid = 0,
                Status = TransactionStatus.Confirmed,
                Timestamp = timestamp,
                ExecutionMessage = "Genesis state established."
            };

            return block;
        }

        public static string ComputeSha256(string rawData)
        {
            using var sha256 = SHA256.Create();
            byte[] bytes = sha256.ComputeHash(Encoding.UTF8.GetBytes(rawData));
            var sb = new StringBuilder(bytes.Length * 2);
            foreach (byte b in bytes)
            {
                sb.Append(b.ToString("x2"));
            }
            return sb.ToString();
        }

        public string CalculateHash(long index, DateTime timestamp, List<Transaction> transactions, string previousHash, ulong nonce)
        {
            string merkle = CalculateMerkleRoot(transactions);
            string payload = $"{index}:{timestamp:yyyyMMddHHmmssfff}:{previousHash}:{merkle}:{nonce}";
            return ComputeSha256(payload);
        }

        public string CalculateMerkleRoot(IReadOnlyList<Transaction> transactions)
        {
            if (transactions == null || transactions.Count == 0)
                return ComputeSha256(string.Empty);

            var currentLevel = transactions.Select(t => !string.IsNullOrEmpty(t.Id) ? t.Id : ComputeSha256(t.ToString())).ToList();

            while (currentLevel.Count > 1)
            {
                if (currentLevel.Count % 2 != 0)
                {
                    currentLevel.Add(currentLevel[^1]);
                }

                var nextLevel = new List<string>(currentLevel.Count / 2);
                for (int i = 0; i < currentLevel.Count; i += 2)
                {
                    string combined = currentLevel[i] + currentLevel[i + 1];
                    nextLevel.Add(ComputeSha256(combined));
                }
                currentLevel = nextLevel;
            }

            return currentLevel[0];
        }

        #endregion

        #region Wallet & State Management

        public Wallet RegisterWallet(string address, string publicKey, decimal initialBalance = 0m)
        {
            if (string.IsNullOrWhiteSpace(address))
                throw new ArgumentException("Wallet address cannot be empty.", nameof(address));

            lock (_lock)
            {
                if (_wallets.TryGetValue(address, out var existing))
                {
                    return existing;
                }

                var wallet = new Wallet
                {
                    Address = address,
                    PublicKey = publicKey,
                    Balance = initialBalance,
                    Nonce = 0,
                    CreatedAt = DateTime.UtcNow
                };

                _wallets[address] = wallet;
                return wallet;
            }
        }

        public (string Address, string PublicKey, string PrivateKey) GenerateWalletKeys()
        {
            using var ecdsa = ECDsa.Create(ECCurve.NamedCurves.nistP256);
            string privateKey = Convert.ToBase64String(ecdsa.ExportECPrivateKey());
            string publicKey = Convert.ToBase64String(ecdsa.ExportSubjectPublicKeyInfo());
            
            using var sha256 = SHA256.Create();
            byte[] pubBytes = Encoding.UTF8.GetBytes(publicKey);
            byte[] hash = sha256.ComputeHash(pubBytes);
            string address = "0x" + BitConverter.ToString(hash, 0, 20).Replace("-", "").ToLowerInvariant();

            RegisterWallet(address, publicKey, 0m);
            return (address, publicKey, privateKey);
        }

        public Wallet? GetWallet(string address)
        {
            lock (_lock)
            {
                return _wallets.TryGetValue(address, out var wallet) ? wallet : null;
            }
        }

        public decimal GetBalance(string address, string tokenSymbol = NativeTokenSymbol)
        {
            lock (_lock)
            {
                if (!_wallets.TryGetValue(address, out var wallet))
                    return 0m;

                if (string.Equals(tokenSymbol, NativeTokenSymbol, StringComparison.OrdinalIgnoreCase))
                    return wallet.Balance;

                return wallet.TokenBalances.TryGetValue(tokenSymbol, out decimal balance) ? balance : 0m;
            }
        }

        public bool RegisterToken(Token token)
        {
            if (token == null || string.IsNullOrWhiteSpace(token.Symbol))
                return false;

            lock (_lock)
            {
                if (_tokens.ContainsKey(token.Symbol))
                    return false;

                _tokens[token.Symbol] = token;
                return true;
            }
        }

        public Token? GetToken(string symbol)
        {
            lock (_lock)
            {
                return _tokens.TryGetValue(symbol, out var token) ? token : null;
            }
        }

        #endregion

        #region Transaction Validation & Addition

        public string SignPayload(string payload, string base64PrivateKey)
        {
            using var ecdsa = ECDsa.Create();
            ecdsa.ImportECPrivateKey(Convert.FromBase64String(base64PrivateKey), out _);
            byte[] dataBytes = Encoding.UTF8.GetBytes(payload);
            byte[] signature = ecdsa.SignData(dataBytes, HashAlgorithmName.SHA256);
            return Convert.ToBase64String(signature);
        }

        public bool VerifySignature(Transaction transaction)
        {
            if (string.IsNullOrEmpty(transaction.Signature))
                return false;

            // Bypass for special protocol or genesis transactions
            if (transaction.Sender == GenesisAddress && (transaction.Signature == "genesis" || transaction.Signature == "genesis_signature"))
                return true;
            if (transaction.Signature == "mining_reward")
                return true;

            lock (_lock)
            {
                if (!_wallets.TryGetValue(transaction.Sender, out var wallet))
                    return false;

                if (string.IsNullOrEmpty(wallet.PublicKey))
                    return false;

                try
                {
                    using var ecdsa = ECDsa.Create();
                    ecdsa.ImportSubjectPublicKeyInfo(Convert.FromBase64String(wallet.PublicKey), out _);
                    byte[] dataBytes = transaction.GetRawPayloadBytes();
                    byte[] signatureBytes = Convert.FromBase64String(transaction.Signature);
                    return ecdsa.VerifyData(dataBytes, signatureBytes, HashAlgorithmName.SHA256);
                }
                catch
                {
                    return false;
                }
            }
        }

        public bool IsValidTransaction(Transaction transaction, out string failureReason)
        {
            failureReason = string.Empty;

            if (transaction == null)
            {
                failureReason = "Transaction cannot be null.";
                return false;
            }

            if (string.IsNullOrWhiteSpace(transaction.Sender) || string.IsNullOrWhiteSpace(transaction.Recipient))
            {
                failureReason = "Sender and Recipient must be defined.";
                return false;
            }

            if (transaction.Amount <= 0)
            {
                failureReason = "Transaction amount must be strictly greater than zero.";
                return false;
            }

            if (transaction.Fee < 0)
            {
                failureReason = "Fee cannot be negative.";
                return false;
            }

            // Mining rewards do not require sender balances or signatures
            if (transaction.Signature == "mining_reward")
            {
                return true;
            }

            // Verify Cryptographic Signature
            if (!VerifySignature(transaction))
            {
                failureReason = "Cryptographic signature verification failed.";
                return false;
            }

            lock (_lock)
            {
                if (!_wallets.TryGetValue(transaction.Sender, out var senderWallet))
                {
                    failureReason = $"Sender address '{transaction.Sender}' not found in state.";
                    return false;
                }

                if (transaction.Nonce <= senderWallet.Nonce)
                {
                    failureReason = $"Nonce {transaction.Nonce} is too low. Expected > {senderWallet.Nonce}.";
                    return false;
                }

                // Check fee balance in native currency
                if (senderWallet.Balance < transaction.Fee)
                {
                    failureReason = $"Insufficient native balance for gas fee {transaction.Fee}.";
                    return false;
                }

                if (string.Equals(transaction.TokenSymbol, NativeTokenSymbol, StringComparison.OrdinalIgnoreCase))
                {
                    decimal totalRequired = transaction.Amount + transaction.Fee;
                    if (senderWallet.Balance < totalRequired)
                    {
                        failureReason = $"Insufficient balance: requires {totalRequired} {NativeTokenSymbol}, has {senderWallet.Balance}.";
                        return false;
                    }
                }
                else
                {
                    if (!_tokens.ContainsKey(transaction.TokenSymbol))
                    {
                        failureReason = $"Token symbol '{transaction.TokenSymbol}' does not exist.";
                        return false;
                    }

                    senderWallet.TokenBalances.TryGetValue(transaction.TokenSymbol, out decimal tokenBal);
                    if (tokenBal < transaction.Amount)
                    {
                        failureReason = $"Insufficient token balance for {transaction.TokenSymbol}.";
                        return false;
                    }
                }
            }

            return true;
        }

        public bool AddTransaction(Transaction transaction, out string message)
        {
            if (transaction == null)
                throw new ArgumentNullException(nameof(transaction));

            if (string.IsNullOrEmpty(transaction.Id))
            {
                transaction.Id = ComputeSha256(transaction.ToString() + Guid.NewGuid().ToString("N"));
            }

            if (!IsValidTransaction(transaction, out message))
            {
                transaction.Status = TransactionStatus.Rejected;
                return false;
            }

            lock (_lock)
            {
                // Check for mempool duplicates
                if (_pendingTransactions.Any(t => t.Id == transaction.Id))
                {
                    message = "Transaction with this ID is already in the mempool.";
                    return false;
                }

                transaction.Status = TransactionStatus.Pending;
                _pendingTransactions.Add(transaction);
            }

            message = "Transaction successfully accepted into mempool.";
            return true;
        }

        #endregion

        #region Mining & Consensus Engine

        public static bool IsValidHash(string hash, int difficulty)
        {
            if (string.IsNullOrEmpty(hash) || hash.Length < difficulty)
                return false;

            for (int i = 0; i < difficulty; i++)
            {
                if (hash[i] != '0')
                    return false;
            }
            return true;
        }

        public Block GetLatestBlock()
        {
            lock (_lock)
            {
                return _blockchain[^1];
            }
        }

        public async Task<Block?> MinePendingTransactionsAsync(string minerAddress, CancellationToken cancellationToken = default)
        {
            if (string.IsNullOrWhiteSpace(minerAddress))
                throw new ArgumentException("Miner address cannot be empty.", nameof(minerAddress));

            List<Transaction> transactionsToMine;
            Block newBlock;

            lock (_lock)
            {
                // Ensure miner wallet exists
                if (!_wallets.ContainsKey(minerAddress))
                {
                    RegisterWallet(minerAddress, string.Empty, 0m);
                }

                // Order mempool by fee descending for optimal transaction selection
                transactionsToMine = _pendingTransactions
                    .OrderByDescending(t => t.Fee)
                    .Take(100)
                    .ToList();

                decimal aggregatedFees = transactionsToMine.Sum(t => t.Fee);

                var rewardTransaction = new Transaction
                {
                    Id = ComputeSha256($"reward:{_blockchain.Count}:{minerAddress}:{DateTime.UtcNow.Ticks}"),
                    Sender = GenesisAddress,
                    Recipient = minerAddress,
                    Amount = _miningReward + aggregatedFees,
                    Fee = 0,
                    Nonce = 0,
                    Timestamp = DateTime.UtcNow,
                    TokenSymbol = NativeTokenSymbol,
                    Payload = $"Block reward #{_blockchain.Count} + tx fees {aggregatedFees}",
                    Signature = "mining_reward",
                    Status = TransactionStatus.Pending
                };

                var blockTxs = new List<Transaction>(transactionsToMine) { rewardTransaction };

                newBlock = new Block
                {
                    Index = _blockchain.Count,
                    Timestamp = DateTime.UtcNow,
                    Transactions = blockTxs,
                    PreviousHash = GetLatestBlock().Hash,
                    MinerAddress = minerAddress,
                    Difficulty = _difficulty,
                    MerkleRoot = CalculateMerkleRoot(blockTxs)
                };
            }

            // Execute Proof of Work
            bool mined = await MineBlockAsync(newBlock, cancellationToken);
            if (!mined)
                return null;

            lock (_lock)
            {
                // Apply State Transitions
                ApplyBlockStateTransitions(newBlock);

                _blockchain.Add(newBlock);

                // Remove mined transactions from mempool
                var minedIds = new HashSet<string>(newBlock.Transactions.Select(t => t.Id));
                _pendingTransactions.RemoveAll(t => minedIds.Contains(t.Id));
            }

            return newBlock;
        }

        private async Task<bool> MineBlockAsync(Block block, CancellationToken cancellationToken)
        {
            block.Nonce = 0;
            block.Hash = CalculateHash(block.Index, block.Timestamp, block.Transactions, block.PreviousHash, block.Nonce);

            ulong counter = 0;
            while (!IsValidHash(block.Hash, block.Difficulty))
            {
                if (cancellationToken.IsCancellationRequested)
                    return false;

                block.Nonce++;
                counter++;

                if (counter % 50_000 == 0)
                {
                    await Task.Yield();
                }

                block.Hash = CalculateHash(block.Index, block.Timestamp, block.Transactions, block.PreviousHash, block.Nonce);
            }

            return true;
        }

        private void ApplyBlockStateTransitions(Block block)
        {
            foreach (var tx in block.Transactions)
            {
                if (tx.Signature == "mining_reward")
                {
                    if (!_wallets.TryGetValue(tx.Recipient, out var minerWallet))
                    {
                        minerWallet = new Wallet { Address = tx.Recipient };
                        _wallets[tx.Recipient] = minerWallet;
                    }
                    minerWallet.Balance += tx.Amount;
                    tx.Status = TransactionStatus.Confirmed;
                }
                else
                {
                    if (_wallets.TryGetValue(tx.Sender, out var senderWallet) &&
                        _wallets.TryGetValue(tx.Recipient, out var recipientWallet))
                    {
                        // Deduct gas fee
                        senderWallet.Balance -= tx.Fee;
                        senderWallet.Nonce = Math.Max(senderWallet.Nonce, tx.Nonce);

                        if (string.Equals(tx.TokenSymbol, NativeTokenSymbol, StringComparison.OrdinalIgnoreCase))
                        {
                            senderWallet.Balance -= tx.Amount;
                            recipientWallet.Balance += tx.Amount;
                        }
                        else
                        {
                            senderWallet.TokenBalances[tx.TokenSymbol] -= tx.Amount;
                            if (!recipientWallet.TokenBalances.ContainsKey(tx.TokenSymbol))
                                recipientWallet.TokenBalances[tx.TokenSymbol] = 0m;
                            recipientWallet.TokenBalances[tx.TokenSymbol] += tx.Amount;
                        }

                        tx.Status = TransactionStatus.Confirmed;
                    }
                    else
                    {
                        tx.Status = TransactionStatus.Failed;
                    }
                }

                _receipts[tx.Id] = new TransactionReceipt
                {
                    TransactionId = tx.Id,
                    BlockIndex = block.Index,
                    BlockHash = block.Hash,
                    GasUsed = tx.Fee,
                    FeePaid = tx.Fee,
                    Status = tx.Status,
                    Timestamp = block.Timestamp,
                    ExecutionMessage = tx.Status == TransactionStatus.Confirmed ? "Executed successfully" : "Execution failure: missing account"
                };
            }
        }

        #endregion

        #region Chain Verification & Auditing

        public bool VerifyChain(out string discrepancyReason)
        {
            discrepancyReason = string.Empty;

            lock (_lock)
            {
                if (_blockchain.Count == 0)
                {
                    discrepancyReason = "Chain is empty.";
                    return false;
                }

                for (int i = 1; i < _blockchain.Count; i++)
                {
                    var current = _blockchain[i];
                    var previous = _blockchain[i - 1];

                    if (current.PreviousHash != previous.Hash)
                    {
                        discrepancyReason = $"Block {i} previous hash mismatch. Expected {previous.Hash}, found {current.PreviousHash}.";
                        return false;
                    }

                    string recomputedHash = CalculateHash(current.Index, current.Timestamp, current.Transactions, current.PreviousHash, current.Nonce);
                    if (current.Hash != recomputedHash)
                    {
                        discrepancyReason = $"Block {i} hash corruption. Header hash != recomputed hash.";
                        return false;
                    }

                    string recomputedMerkle = CalculateMerkleRoot(current.Transactions);
                    if (current.MerkleRoot != recomputedMerkle)
                    {
                        discrepancyReason = $"Block {i} Merkle root invalid.";
                        return false;
                    }

                    if (!IsValidHash(current.Hash, current.Difficulty))
                    {
                        discrepancyReason = $"Block {i} fails difficulty criteria ({current.Difficulty}).";
                        return false;
                    }
                }
            }

            return true;
        }

        #endregion

        #region Queries and Observability

        public IReadOnlyList<Block> GetBlockchain()
        {
            lock (_lock)
            {
                return _blockchain.ToImmutableList();
            }
        }

        public IReadOnlyList<Transaction> GetPendingTransactions()
        {
            lock (_lock)
            {
                return _pendingTransactions.ToImmutableList();
            }
        }

        public TransactionReceipt? GetReceipt(string transactionId)
        {
            return _receipts.TryGetValue(transactionId, out var receipt) ? receipt : null;
        }

        public NodeStats GetStats()
        {
            lock (_lock)
            {
                return new NodeStats
                {
                    ChainHeight = _blockchain.Count,
                    PendingTransactionCount = _pendingTransactions.Count,
                    KnownWalletsCount = _wallets.Count,
                    KnownTokensCount = _tokens.Count,
                    Difficulty = _difficulty,
                    MiningReward = _miningReward,
                    LatestBlockHash = _blockchain[^1].Hash
                };
            }
        }

        public string ExportChainAsJson()
        {
            lock (_lock)
            {
                return JsonSerializer.Serialize(_blockchain, new JsonSerializerOptions
                {
                    WriteIndented = true
                });
            }
        }

        #endregion
    }

    #endregion
}
