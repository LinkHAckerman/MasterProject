using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

namespace MagnumOpus.Core
{
    /// <summary>
    /// Represents a high-performance, immutable transaction payload within the Magnum Opus ledger system.
    /// </summary>
    public sealed class Transaction
    {
        public string Id { get; }
        public string Sender { get; }
        public string Recipient { get; }
        public decimal Amount { get; }
        public decimal Fee { get; }
        public long Timestamp { get; }
        public string Signature { get; }

        public Transaction(string sender, string recipient, decimal amount, decimal fee)
        {
            Sender = sender ?? throw new ArgumentNullException(nameof(sender));
            Recipient = recipient ?? throw new ArgumentNullException(nameof(recipient));
            if (amount <= 0) throw new ArgumentException("Amount must be positive", nameof(amount));
            if (fee < 0) throw new ArgumentException("Fee cannot be negative", nameof(fee));

            Amount = amount;
            Fee = fee;
            Timestamp = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
            Id = ComputeHash();
            Signature = GenerateMockSignature();
        }

        public string ComputeHash()
        {
            using var sha256 = SHA256.Create();
            var rawData = $"{Sender}:{Recipient}:{Amount:F8}:{Fee:F8}:{Timestamp}";
            var bytes = sha256.ComputeHash(Encoding.UTF8.GetBytes(rawData));
            return Convert.ToHexString(bytes).ToLowerInvariant();
        }

        private string GenerateMockSignature()
        {
            // Simulates high-performance ECDSA secp256k1 signing
            using var sha256 = SHA256.Create();
            var rawData = $"{Id}:mock_private_key_signature_entropy_998244353_magnum_opus_secure_channel";
            var bytes = sha256.ComputeHash(Encoding.UTF8.GetBytes(rawData));
            return "0x" + Convert.ToHexString(bytes).ToLowerInvariant();
        }

        public bool VerifySignature()
        {
            if (string.IsNullOrEmpty(Signature) || !Signature.StartsWith("0x"))
                return false;
            
            // Validate transaction integrity
            var computedId = ComputeHash();
            if (computedId != Id) return false;

            // Simple fast deterministic check: verify signature is derived from Id
            using var sha256 = SHA256.Create();
            var rawData = $"{Id}:mock_private_key_signature_entropy_998244353_magnum_opus_secure_channel";
            var bytes = sha256.ComputeHash(Encoding.UTF8.GetBytes(rawData));
            var expectedSig = "0x" + Convert.ToHexString(bytes).ToLowerInvariant();
            
            return Signature == expectedSig;
        }
    }

    /// <summary>
    /// Represents a cryptographic block inside the ledger containing transactions,
    /// consensus data, and links to the previous block hash.
    /// </summary>
    public sealed class Block
    {
        public int Index { get; }
        public long Timestamp { get; }
        public string PreviousHash { get; }
        public string Hash { get; private set; }
        public string MerkleRoot { get; }
        public long Nonce { get; private set; }
        public int Difficulty { get; }
        public List<Transaction> Transactions { get; }
        public long ExecutionTimeMs { get; private set; }

        public Block(int index, string previousHash, List<Transaction> transactions, int difficulty)
        {
            Index = index;
            Timestamp = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
            PreviousHash = previousHash ?? throw new ArgumentNullException(nameof(previousHash));
            Transactions = transactions ?? throw new ArgumentNullException(nameof(transactions));
            Difficulty = difficulty;
            MerkleRoot = CalculateMerkleRoot();
            Hash = CalculateHash();
        }

        public string CalculateHash()
        {
            using var sha256 = SHA256.Create();
            var rawData = $"{Index}:{Timestamp}:{PreviousHash}:{MerkleRoot}:{Nonce}:{Difficulty}";
            var bytes = sha256.ComputeHash(Encoding.UTF8.GetBytes(rawData));
            return Convert.ToHexString(bytes).ToLowerInvariant();
        }

        public string CalculateMerkleRoot()
        {
            if (Transactions == null || Transactions.Count == 0)
                return "0000000000000000000000000000000000000000000000000000000000000000";

            var txHashes = Transactions.Select(t => t.Id).ToList();
            while (txHashes.Count > 1)
            {
                if (txHashes.Count % 2 != 0)
                {
                    txHashes.Add(txHashes.Last());
                }

                var nextLevel = new List<string>();
                using var sha256 = SHA256.Create();
                for (int i = 0; i < txHashes.Count; i += 2)
                {
                    var combined = txHashes[i] + txHashes[i + 1];
                    var bytes = sha256.ComputeHash(Encoding.UTF8.GetBytes(combined));
                    nextLevel.Add(Convert.ToHexString(bytes).ToLowerInvariant());
                }
                txHashes = nextLevel;
            }

            return txHashes[0];
        }

        public void Mine(CancellationToken cancellationToken)
        {
            var stopwatch = Stopwatch.StartNew();
            var targetPrefix = new string('0', Difficulty);

            while (true)
            {
                cancellationToken.ThrowIfCancellationRequested();
                Hash = CalculateHash();
                if (Hash.StartsWith(targetPrefix))
                {
                    break;
                }
                Nonce++;
            }

            stopwatch.Stop();
            ExecutionTimeMs = stopwatch.ElapsedMilliseconds;
        }
    }

    /// <summary>
    /// Thread-safe transaction pool and consensus pipeline engine.
    /// Manages state, processes transactions, maintains a mempool, and mines new blocks.
    /// </summary>
    public sealed class TransactionProcessor
    {
        private readonly ConcurrentQueue<Transaction> _mempool = new();
        private readonly List<Block> _blockchain = new();
        private readonly ConcurrentDictionary<string, decimal> _balances = new();
        private readonly object _blockchainLock = new();
        
        private readonly int _miningDifficulty;
        private readonly int _maxBlockSize;
        private readonly decimal _blockReward;
        private readonly string _minerAddress;

        public int BlockCount
        {
            get { lock (_blockchainLock) { return _blockchain.Count; } }
        }

        public IReadOnlyList<Block> Blockchain
        {
            get { lock (_blockchainLock) { return _blockchain.AsReadOnly(); } }
        }

        public int MempoolSize => _mempool.Count;

        public TransactionProcessor(int initialDifficulty = 4, int maxBlockSize = 10, decimal blockReward = 50.0m, string minerAddress = "0xSystemMinerNode")
        {
            _miningDifficulty = initialDifficulty;
            _maxBlockSize = maxBlockSize;
            _blockReward = blockReward;
            _minerAddress = minerAddress;

            // Initialize system with a Genesis Block
            lock (_blockchainLock)
            {
                var genesisTransactions = new List<Transaction>
                {
                    new Transaction("0xSystemIssuer", "0xAlice", 100000.0m, 0.0m),
                    new Transaction("0xSystemIssuer", "0xBob", 100000.0m, 0.0m),
                    new Transaction("0xSystemIssuer", "0xCharlie", 100000.0m, 0.0m)
                };

                // Seed balance tracker
                _balances["0xAlice"] = 100000.0m;
                _balances["0xBob"] = 100000.0m;
                _balances["0xCharlie"] = 100000.0m;
                _balances[_minerAddress] = 0.0m;

                var genesisBlock = new Block(0, "0000000000000000000000000000000000000000000000000000000000000000", genesisTransactions, 0);
                genesisBlock.Mine(CancellationToken.None);
                _blockchain.Add(genesisBlock);
            }
        }

        public decimal GetBalance(string address)
        {
            return _balances.TryGetValue(address, out var balance) ? balance : 0.0m;
        }

        public bool SubmitTransaction(Transaction transaction)
        {
            if (transaction == null) return false;

            // Cryptographic validation
            if (!transaction.VerifySignature())
                return false;

            lock (_blockchainLock)
            {
                // Balance verification
                var senderBalance = GetBalance(transaction.Sender);
                var totalCost = transaction.Amount + transaction.Fee;
                if (senderBalance < totalCost)
                    return false;

                // Subtract from balance immediately to prevent double spending in pool
                _balances[transaction.Sender] = senderBalance - totalCost;
            }

            _mempool.Enqueue(transaction);
            return true;
        }

        public Block ProcessNextBlock(CancellationToken cancellationToken = default)
        {
            var txsToProcess = new List<Transaction>();
            
            // Gather transactions up to MaxBlockSize
            while (txsToProcess.Count < _maxBlockSize && _mempool.TryDequeue(out var tx))
            {
                txsToProcess.Add(tx);
            }

            lock (_blockchainLock)
            {
                var lastBlock = _blockchain.Last();
                
                // Add mining reward transaction
                var rewardTx = new Transaction("0xSystemIssuer", _minerAddress, _blockReward, 0.0m);
                txsToProcess.Add(rewardTx);

                var newBlock = new Block(lastBlock.Index + 1, lastBlock.Hash, txsToProcess, _miningDifficulty);
                
                // Mine block (Proof-of-Work calculation loop)
                newBlock.Mine(cancellationToken);

                // Commit block to blockchain
                _blockchain.Add(newBlock);

                // Finalize balances
                foreach (var tx in txsToProcess)
                {
                    if (tx.Sender != "0xSystemIssuer")
                    {
                        // Sender was already debited at submission. Credit fee to miner.
                        _balances[_minerAddress] = GetBalance(_minerAddress) + tx.Fee;
                    }
                    _balances[tx.Recipient] = GetBalance(tx.Recipient) + tx.Amount;
                }

                return newBlock;
            }
        }

        public bool ValidateChain()
        {
            lock (_blockchainLock)
            {
                var targetPrefix = new string('0', _miningDifficulty);

                for (int i = 1; i < _blockchain.Count; i++)
                {
                    var current = _blockchain[i];
                    var previous = _blockchain[i - 1];

                    // Check hash integrity
                    if (current.Hash != current.CalculateHash())
                        return false;

                    // Check link to previous block
                    if (current.PreviousHash != previous.Hash)
                        return false;

                    // Verify proof-of-work difficulty matches
                    if (current.Index > 0 && !current.Hash.StartsWith(targetPrefix))
                        return false;

                    // Verify merkle root integrity
                    if (current.MerkleRoot != current.CalculateMerkleRoot())
                        return false;
                }
            }

            return true;
        }
    }
}