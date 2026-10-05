using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace MagnumOpus.Backend.Core
{
    public class TransactionProcessor
    {
        private readonly Dictionary<string, Wallet> _wallets;
        private readonly Dictionary<string, Token> _tokens;
        private readonly Dictionary<string, SmartContract> _contracts;
        private readonly List<Transaction> _pendingTransactions;
        private readonly List<Block> _blockchain;
        private readonly int _difficulty;
        private readonly int _blockTime;
        private readonly object _lock = new object();

        public TransactionProcessor(int difficulty = 4, int blockTime = 10)
        {
            _wallets = new Dictionary<string, Wallet>();
            _tokens = new Dictionary<string, Token>();
            _contracts = new Dictionary<string, SmartContract>();
            _pendingTransactions = new List<Transaction>();
            _blockchain = new List<Block>();
            _difficulty = difficulty;
            _blockTime = blockTime;

            // Initialize with genesis block
            var genesisBlock = new Block
            {
                Index = 0,
                Timestamp = DateTime.UtcNow,
                Transactions = new List<Transaction>(),
                PreviousHash = "0",
                Nonce = 0,
                Hash = CalculateHash(new Block
                {
                    Index = 0,
                    Timestamp = DateTime.UtcNow,
                    Transactions = new List<Transaction>(),
                    PreviousHash = "0",
                    Nonce = 0
                })
            };
            _blockchain.Add(genesisBlock);
        }

        public async Task<string> CreateWallet(string publicKey)
        {
            var wallet = new Wallet
            {
                Address = publicKey,
                Balance = 0,
                Nonce = 0,
                Tokens = new Dictionary<string, decimal>()
            };

            lock (_lock)
            {
                _wallets[publicKey] = wallet;
            }

            return publicKey;
        }

        public async Task<decimal> GetBalance(string address)
        {
            lock (_lock)
            {
                if (_wallets.TryGetValue(address, out var wallet))
                {
                    return wallet.Balance;
                }
            }

            return 0;
        }

        public async Task<Dictionary<string, decimal>> GetTokenBalances(string address)
        {
            lock (_lock)
            {
                if (_wallets.TryGetValue(address, out var wallet))
                {
                    return wallet.Tokens;
                }
            }

            return new Dictionary<string, decimal>();
        }

        public async Task<string> CreateToken(string name, string symbol, decimal totalSupply, string ownerAddress)
        {
            var tokenId = Guid.NewGuid().ToString();
            var token = new Token
            {
                Id = tokenId,
                Name = name,
                Symbol = symbol,
                TotalSupply = totalSupply,
                OwnerAddress = ownerAddress
            };

            lock (_lock)
            {
                _tokens[tokenId] = token;
                if (_wallets.TryGetValue(ownerAddress, out var wallet))
                {
                    wallet.Tokens[tokenId] = totalSupply;
                }
            }

            return tokenId;
        }

        public async Task<string> CreateSmartContract(string contractAddress, string ownerAddress, string bytecode)
        {
            var contractId = Guid.NewGuid().ToString();
            var contract = new SmartContract
            {
                Id = contractId,
                Address = contractAddress,
                OwnerAddress = ownerAddress,
                Bytecode = bytecode,
                Storage = new Dictionary<string, string>()
            };

            lock (_lock)
            {
                _contracts[contractId] = contract;
            }

            return contractId;
        }

        public async Task<string> SendTransaction(Transaction transaction)
        {
            var transactionId = Guid.NewGuid().ToString();
            transaction.Id = transactionId;
            transaction.Timestamp = DateTime.UtcNow;

            lock (_lock)
            {
                _pendingTransactions.Add(transaction);
            }

            return transactionId;
        }

        public async Task<Block> MineBlock()
        {
            List<Transaction> blockTransactions;
            string previousHash;

            lock (_lock)
            {
                blockTransactions = _pendingTransactions.Take(10).ToList();
                _pendingTransactions.RemoveRange(0, blockTransactions.Count);
                previousHash = _blockchain.Last().Hash;
            }

            var block = new Block
            {
                Index = _blockchain.Count,
                Timestamp = DateTime.UtcNow,
                Transactions = blockTransactions,
                PreviousHash = previousHash,
                Nonce = 0
            };

            block.Hash = MineBlock(block);

            lock (_lock)
            {
                _blockchain.Add(block);
                ProcessTransactions(blockTransactions);
            }

            return block;
        }

        private string MineBlock(Block block)
        {
            var target = new string('0', _difficulty);
            var hash = CalculateHash(block);

            while (!hash.StartsWith(target))
            {
                block.Nonce++;
                hash = CalculateHash(block);
            }

            return hash;
        }

        private string CalculateHash(Block block)
        {
            var blockData = JsonSerializer.Serialize(block);
            using var sha256 = SHA256.Create();
            var hashBytes = sha256.ComputeHash(Encoding.UTF8.GetBytes(blockData));
            return BitConverter.ToString(hashBytes).Replace("-", "").ToLower();
        }

        private void ProcessTransactions(List<Transaction> transactions)
        {
            foreach (var transaction in transactions)
            {
                if (transaction.Type == TransactionType.Transfer)
                {
                    ProcessTransfer(transaction);
                }
                else if (transaction.Type == TransactionType.TokenTransfer)
                {
                    ProcessTokenTransfer(transaction);
                }
                else if (transaction.Type == TransactionType.ContractCall)
                {
                    ProcessContractCall(transaction);
                }
            }
        }

        private void ProcessTransfer(Transaction transaction)
        {
            if (_wallets.TryGetValue(transaction.From, out var fromWallet) &&
                _wallets.TryGetValue(transaction.To, out var toWallet))
            {
                if (fromWallet.Balance >= transaction.Amount)
                {
                    fromWallet.Balance -= transaction.Amount;
                    toWallet.Balance += transaction.Amount;
                    fromWallet.Nonce++;
                }
            }
        }

        private void ProcessTokenTransfer(Transaction transaction)
        {
            if (_wallets.TryGetValue(transaction.From, out var fromWallet) &&
                _wallets.TryGetValue(transaction.To, out var toWallet) &&
                _tokens.TryGetValue(transaction.TokenId, out var token))
            {
                if (fromWallet.Tokens.TryGetValue(transaction.TokenId, out var fromBalance) &&
                    fromBalance >= transaction.Amount)
                {
                    fromWallet.Tokens[transaction.TokenId] -= transaction.Amount;
                    if (!toWallet.Tokens.ContainsKey(transaction.TokenId))
                    {
                        toWallet.Tokens[transaction.TokenId] = 0;
                    }
                    toWallet.Tokens[transaction.TokenId] += transaction.Amount;
                    fromWallet.Nonce++;
                }
            }
        }

        private void ProcessContractCall(Transaction transaction)
        {
            if (_contracts.TryGetValue(transaction.ContractId, out var contract))
            {
                // Simulate contract execution
                contract.Storage[transaction.Data] = transaction.Data;
            }
        }
    }

    public class Wallet
    {
        public string Address { get; set; }
        public decimal Balance { get; set; }
        public int Nonce { get; set; }
        public Dictionary<string, decimal> Tokens { get; set; }
    }

    public class Token
    {
        public string Id { get; set; }
        public string Name { get; set; }
        public string Symbol { get; set; }
        public decimal TotalSupply { get; set; }
        public string OwnerAddress { get; set; }
    }

    public class SmartContract
    {
        public string Id { get; set; }
        public string Address { get; set; }
        public string OwnerAddress { get; set; }
        public string Bytecode { get; set; }
        public Dictionary<string, string> Storage { get; set; }
    }

    public class Transaction
    {
        public string Id { get; set; }
        public string From { get; set; }
        public string To { get; set; }
        public decimal Amount { get; set; }
        public string TokenId { get; set; }
        public string ContractId { get; set; }
        public string Data { get; set; }
        public TransactionType Type { get; set; }
        public DateTime Timestamp { get; set; }
    }

    public enum TransactionType
    {
        Transfer,
        TokenTransfer,
        ContractCall
    }

    public class Block
    {
        public int Index { get; set; }
        public DateTime Timestamp { get; set; }
        public List<Transaction> Transactions { get; set; }
        public string PreviousHash { get; set; }
        public int Nonce { get; set; }
        public string Hash { get; set; }
    }
}