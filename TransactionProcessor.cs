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
            _blockchain.Add(CreateGenesisBlock());
        }

        private Block CreateGenesisBlock()
        {
            var genesisBlock = new Block
            {
                Index = 0,
                Timestamp = DateTime.UtcNow,
                Transactions = new List<Transaction>(),
                PreviousHash = "0",
                Nonce = 0,
                Hash = ""
            };
            
            genesisBlock.Hash = CalculateHash(genesisBlock);
            return genesisBlock;
        }

        public string CreateWallet(string publicKey)
        {
            var wallet = new Wallet
            {
                Address = publicKey,
                Balance = 0,
                Nonce = 0
            };
            
            lock (_lock)
            {
                _wallets[publicKey] = wallet;
            }

            return publicKey;
        }

        public void CreateToken(string symbol, string name, ulong totalSupply, string ownerAddress)
        {
            var token = new Token
            {
                Symbol = symbol,
                Name = name,
                TotalSupply = totalSupply,
                OwnerAddress = ownerAddress
            };
            
            lock (_lock)
            {
                _tokens[symbol] = token;
                _wallets[ownerAddress].Balance += totalSupply;
            }
        }

        public void DeployContract(string contractAddress, string contractCode, string ownerAddress)
        {
            var contract = new SmartContract
            {
                Address = contractAddress,
                Code = contractCode,
                OwnerAddress = ownerAddress
            };
            
            lock (_lock)
            {
                _contracts[contractAddress] = contract;
            }
        }

        public string CreateTransaction(string fromAddress, string toAddress, ulong amount, string data = "")
        {
            var transaction = new Transaction
            {
                FromAddress = fromAddress,
                ToAddress = toAddress,
                Amount = amount,
                Data = data,
                Timestamp = DateTime.UtcNow,
                Nonce = _wallets[fromAddress].Nonce
            };
            
            transaction.Signature = SignTransaction(transaction, fromAddress);
            
            lock (_lock)
            {
                _pendingTransactions.Add(transaction);
                _wallets[fromAddress].Nonce++;
            }

            return transaction.Hash;
        }

        private string SignTransaction(Transaction transaction, string privateKey)
        {
            // In a real implementation, this would use proper cryptographic signing
            // For this example, we'll use a simple hash as a placeholder
            var transactionData = $"{transaction.FromAddress}{transaction.ToAddress}{transaction.Amount}{transaction.Data}{transaction.Timestamp}{transaction.Nonce}";
            return ComputeHash(transactionData);
        }

        public async Task MinePendingTransactions(string minerAddress)
        {
            var block = new Block
            {
                Index = _blockchain.Count,
                Timestamp = DateTime.UtcNow,
                Transactions = new List<Transaction>(),
                PreviousHash = _blockchain.Last().Hash,
                Nonce = 0
            };
            
            // Add pending transactions to the block
            lock (_lock)
            {
                block.Transactions.AddRange(_pendingTransactions.Take(10));
                _pendingTransactions.RemoveRange(0, Math.Min(10, _pendingTransactions.Count));
            }
            
            // Mine the block
            block.Hash = await MineBlock(block);
            
            // Add the block to the blockchain
            lock (_lock)
            {
                _blockchain.Add(block);
                _wallets[minerAddress].Balance += 10; // Reward for mining
            }
        }

        private async Task<string> MineBlock(Block block)
        {
            return await Task.Run(() =>
            {
                var target = new string('0', _difficulty);
                while (true)
                {
                    block.Hash = CalculateHash(block);
                    if (block.Hash.StartsWith(target))
                    {
                        break;
                    }
                    block.Nonce++;
                }
                return block.Hash;
            });
        }

        private string CalculateHash(Block block)
        {
            var blockData = $"{block.Index}{block.Timestamp}{block.PreviousHash}{block.Nonce}";
            foreach (var transaction in block.Transactions)
            {
                blockData += transaction.Hash;
            }
            return ComputeHash(blockData);
        }

        private string ComputeHash(string input)
        {
            using (var sha256 = SHA256.Create())
            {
                var bytes = Encoding.UTF8.GetBytes(input);
                var hashBytes = sha256.ComputeHash(bytes);
                return BitConverter.ToString(hashBytes).Replace("-", "").ToLower();
            }
        }

        public List<Block> GetBlockchain()
        {
            lock (_lock)
            {
                return new List<Block>(_blockchain);
            }
        }

        public List<Transaction> GetPendingTransactions()
        {
            lock (_lock)
            {
                return new List<Transaction>(_pendingTransactions);
            }
        }

        public Wallet GetWallet(string address)
        {
            lock (_lock)
            {
                return _wallets.ContainsKey(address) ? _wallets[address] : null;
            }
        }

        public Token GetToken(string symbol)
        {
            lock (_lock)
            {
                return _tokens.ContainsKey(symbol) ? _tokens[symbol] : null;
            }
        }

        public SmartContract GetContract(string address)
        {
            lock (_lock)
            {
                return _contracts.ContainsKey(address) ? _contracts[address] : null;
            }
        }
    }

    public class Wallet
    {
        public string Address { get; set; }
        public ulong Balance { get; set; }
        public int Nonce { get; set; }
    }

    public class Token
    {
        public string Symbol { get; set; }
        public string Name { get; set; }
        public ulong TotalSupply { get; set; }
        public string OwnerAddress { get; set; }
    }

    public class SmartContract
    {
        public string Address { get; set; }
        public string Code { get; set; }
        public string OwnerAddress { get; set; }
    }

    public class Transaction
    {
        public string FromAddress { get; set; }
        public string ToAddress { get; set; }
        public ulong Amount { get; set; }
        public string Data { get; set; }
        public DateTime Timestamp { get; set; }
        public int Nonce { get; set; }
        public string Signature { get; set; }

        public string Hash
        {
            get
            {
                var transactionData = $"{FromAddress}{ToAddress}{Amount}{Data}{Timestamp}{Nonce}";
                using (var sha256 = SHA256.Create())
                {
                    var bytes = Encoding.UTF8.GetBytes(transactionData);
                    var hashBytes = sha256.ComputeHash(bytes);
                    return BitConverter.ToString(hashBytes).Replace("-", "").ToLower();
                }
            }
        }
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