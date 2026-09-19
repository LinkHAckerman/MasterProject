using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

namespace MagnumOpus.Core
{
    /// <summary>
    /// Represents a high-performance transaction payload within the Magnum Opus ledger system.
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
            Amount = amount;
            Fee = fee;
            Timestamp = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
            Id = ComputeHash();
            Signature = GenerateMockSignature();
        }

        private string ComputeHash()
        {
            using var sha256 = SHA256.Create();
            var rawData = $"{Sender}:{Recipient}:{Amount}:{Fee}:{Timestamp}";
            var bytes = sha256.ComputeHash(Encoding.UTF8.GetBytes(rawData));
            return Convert.ToHexString(bytes).ToLower();
        }

        private string GenerateMockSignature()
        {
            // Simulates high-performance ECDSA secp256k1 signing
            using var sha256 = SHA256.Create();
            var rawData = $"{Id}:mock_private_key_signature_entropy_998244353";
            var bytes = sha256.ComputeHash(Encoding.UTF8.GetBytes(rawData));
            return "0x" + Convert.ToHexString(bytes).ToLower();
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
            MerkleRoot = MerkleTree.ComputeRoot(transactions);
            Hash = string.Empty;
        }

        /// <summary>
        /// Executes high-performance mining using multi-threaded nonce space exploration.
        /// </summary>
        public void Mine(CancellationToken cancellationToken)
        {
            var sw = Stopwatch.StartNew();
            var targetPrefix = new string('0', Difficulty);
            var isMined = false;
            long sharedNonce = 0;
            string finalHash = string.Empty;

            // Utilize Parallel processing to simulate ASIC/GPU parallel miners
            Parallel.For(0, Environment.ProcessorCount, (threadId, state) =>
            {
                using var sha256 = SHA256.Create();
                // Partition nonce range per core
                long localNonce = threadId * 10_000_000_000L;

                while (!isMined && !state.ShouldExitCurrentIteration() && !cancellationToken.IsCancellationRequested)
                {
                    localNonce++;
                    var header = $"{Index}:{Timestamp}:{PreviousHash}:{MerkleRoot}:{localNonce}";
                    var bytes = sha256.ComputeHash(Encoding.UTF8.GetBytes(header));
                    var hashHex = Convert.ToHexString(bytes);

                    if (hashHex.StartsWith(targetPrefix))
                    {
                        isMined = true;
                        sharedNonce = localNonce;
                        finalHash = hashHex.ToLower();
                        state.Stop();
                    }
                }
            });

            if (cancellationToken.IsCancellationRequested)
            {
                throw new OperationCanceledException("Mining aborted by consensus request.");
            }

            Nonce = sharedNonce;
            Hash = finalHash;
            sw.Stop();
            ExecutionTimeMs = sw.ElapsedMilliseconds;
        }
    }

    /// <summary>
    /// Cryptographically computes the Merkle Root for block transactional integrity verification.
    /// </summary>
    public static class MerkleTree
    {
        public static string ComputeRoot(List<Transaction> transactions)
        {
            if (transactions == null || transactions.Count == 0)
                return Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes("GENESIS_LEAF"))).ToLower();

            var leaves = transactions.Select(tx => tx.Id).ToList();
            return ComputeMerkleRoot(leaves);
        }

        private static string ComputeMerkleRoot(List<string> leaves)
        {
            using var sha256 = SHA256.Create();
            while (leaves.Count > 1)
            {
                if (leaves.Count % 2 != 0)
                {
                    leaves.Add(leaves.Last()); // Duplicate odd node
                }

                var nextLevel = new List<string>();
                for (int i = 0; i < leaves.Count; i += 2)
                {
                    var combined = leaves[i] + leaves[i + 1];
                    var hashBytes = sha256.ComputeHash(Encoding.UTF8.GetBytes(combined));
                    nextLevel.Add(Convert.ToHexString(hashBytes).ToLower());
                }
                leaves = nextLevel;
            }
            return leaves.First();
        }
    }

    /// <summary>
    /// Represents the full-stack transactional ledger. Coordinates mining, transaction ingestion, 
    /// difficulty adjustments, and telemetry stream updates.
    /// </summary>
    public sealed class LedgerManager
    {
        private readonly List<Block> _chain = new();
        private readonly ConcurrentQueue<Transaction> _mempool = new();
        private readonly int _miningDifficulty = 4; // Leading hex zeroes required
        private readonly object _lock = new();

        public IReadOnlyList<Block> Chain => _chain;
        public int MempoolSize => _mempool.Count;

        public event Action<string>? TelemetryLogged;

        public LedgerManager()
        {
            CreateGenesisBlock();
        }

        private void CreateGenesisBlock()
        {
            var genesisTx = new Transaction("SYSTEM_MINTER", "MAGNUM_CREATOR", 1000000.00m, 0);
            var genesisBlock = new Block(0, "0000000000000000000000000000000000000000000000000000000000000000", new List<Transaction> { genesisTx }, 2);
            
            Log("Initializing Magnum Opus Ledger Genesis...");
            genesisBlock.Mine(CancellationToken.None);
            _chain.Add(genesisBlock);
            Log($"Genesis Block successfully minted! Hash: {genesisBlock.Hash}");
        }

        public void SubmitTransaction(string sender, string recipient, decimal amount, decimal fee)
        {
            var tx = new Transaction(sender, recipient, amount, fee);
            _mempool.Enqueue(tx);
            Log($"[Mempool] Tx Received: {tx.Id.Substring(0, 8)}... ({amount} OPUS from {sender.Substring(0, 6)})");
        }

        /// <summary>
        /// Assembles pending transactions from mempool and mines them into a block.
        /// </summary>
        public Block? ProcessPendingTransactions(int maxBlockTransactions = 10)
        {
            var txsToMine = new List<Transaction>();
            while (txsToMine.Count < maxBlockTransactions && _mempool.TryDequeue(out var tx))
            {
                txsToMine.Add(tx);
            }

            if (txsToMine.Count == 0)
            {
                Log("[Consensus] Idle execution context: Mempool empty.");
                return null;
            }

            Block lastBlock;
            lock (_lock)
            {
                lastBlock = _chain[^1];
            }

            var nextIndex = lastBlock.Index + 1;
            var newBlock = new Block(nextIndex, lastBlock.Hash, txsToMine, _miningDifficulty);

            Log($"[Consensus Engine] Commencing Mining of Block #{nextIndex} containing {txsToMine.Count} transactions...");
            
            try
            {
                newBlock.Mine(CancellationToken.None);
                
                lock (_lock)
                {
                    // Validate state check before append
                    if (_chain[^1].Hash == newBlock.PreviousHash)
                    {
                        _chain.Add(newBlock);
                    }
                    else
                    {
                        throw new InvalidOperationException("Blockchain head updated during mining sequence. Block rejected.");
                    }
                }

                Log($"[Consensus Engine] Block #{newBlock.Index} successfully committed. Nonce: {newBlock.Nonce}. Hash: {newBlock.Hash.Substring(0, 16)}... execution time: {newBlock.ExecutionTimeMs}ms");
                return newBlock;
            }
            catch (Exception ex)
            {
                Log($"[Consensus Engine Error] Block mining rejected: {ex.Message}");
                // Refund transaction pool on fail
                foreach (var tx in txsToMine)
                {
                    _mempool.Enqueue(tx);
                }
                return null;
            }
        }

        /// <summary>
        /// Cryptographically validates the whole blockchain structure.
        /// </summary>
        public bool ValidateIntegrity()
        {
            lock (_lock)
            {
                for (int i = 1; i < _chain.Count; i++)
                {
                    var current = _chain[i];
                    var previous = _chain[i - 1];

                    if (current.PreviousHash != previous.Hash)
                    {
                        Log($"[Validation Error] Block #{current.Index} previous hash mismatch.");
                        return false;
                    }

                    // Verify Merkle structure
                    var computedMerkle = MerkleTree.ComputeRoot(current.Transactions);
                    if (current.MerkleRoot != computedMerkle)
                    {
                        Log($"[Validation Error] Block #{current.Index} transaction payload Merkle Tree root mismatch.");
                        return false;
                    }

                    // Check proof-of-work hash target
                    var expectedPrefix = new string('0', current.Difficulty);
                    if (!current.Hash.StartsWith(expectedPrefix))
                    {
                        Log($"[Validation Error] Block #{current.Index} Hash does not satisfy computational proof constraint.");
                        return false;
                    }
                }
            }
            Log("[Consensus Validation] Ledger cryptographic validation pass successful. Integrity is absolute.");
            return true;
        }

        private void Log(string msg)
        {
            var formatted = $"[{DateTime.UtcNow:HH:mm:ss.fff}] {msg}";
            TelemetryLogged?.Invoke(formatted);
            Console.WriteLine(formatted);
        }
    }
}