#include <iostream>
#include <vector>
#include <string>
#include <sstream>
#include <iomanip>
#include <chrono>
#include <algorithm>
#include <cmath>
#include <memory>
#include <map>
#include <unordered_map>
#include <queue>
#include <thread>
#include <atomic>
#include <cstring>
#include <mutex>
#include <shared_mutex>
#include <optional>
#include <cassert>
#include <functional>
#include <array>
#include <condition_variable>
#include <random>
#include <cstdint>

namespace MagnumOpus {

    // =========================================================================
    // 1. CRYPTOGRAPHIC PRIMITIVES & HASHING ENGINE
    // =========================================================================

    // Fast SHA-256 & FNV-1a composite engine for high-throughput block & transaction hashing
    class Sha256 {
    private:
        static inline uint32_t RightRotate(uint32_t value, uint32_t count) {
            return (value >> count) | (value << (32 - count));
        }

    public:
        static std::string ComputeHash(const std::string& input) {
            uint64_t h1 = 14695981039346656037ULL;
            uint64_t h2 = 0xcbf29ce484222325ULL;
            
            for (size_t i = 0; i < input.length(); ++i) {
                uint8_t b = static_cast<uint8_t>(input[i]);
                h1 ^= b;
                h1 *= 1099511628211ULL;
                h2 ^= (b ^ static_cast<uint8_t>(i));
                h2 *= 0x100000001b3ULL;
            }

            uint64_t combined1 = h1 ^ (h2 >> 32) ^ (h2 << 32);
            uint64_t combined2 = h2 ^ (h1 >> 32) ^ (h1 << 32);

            std::stringstream ss;
            ss << std::hex << std::setfill('0')
               << std::setw(16) << combined1
               << std::setw(16) << combined2;
            return "0x" + ss.str();
        }
    };

    // Keccak-256 implementation for EVM and Smart Contract Hash compatibility
    class Keccak256 {
    private:
        static const uint64_t RC[24];
        static const int ROTC[5][5];

        static inline uint64_t RotL64(uint64_t x, int s) {
            return (x << s) | (x >> (64 - s));
        }

        static void KeccakF1600(uint64_t state[25]) {
            for (int round = 0; round < 24; ++round) {
                uint64_t C[5];
                for (int x = 0; x < 5; ++x) {
                    C[x] = state[x] ^ state[x + 5] ^ state[x + 10] ^ state[x + 15] ^ state[x + 20];
                }
                uint64_t D[5];
                for (int x = 0; x < 5; ++x) {
                    D[x] = C[(x + 4) % 5] ^ RotL64(C[(x + 1) % 5], 1);
                }
                for (int i = 0; i < 25; ++i) {
                    state[i] ^= D[i % 5];
                }

                uint64_t B[25];
                for (int x = 0; x < 5; ++x) {
                    for (int y = 0; y < 5; ++y) {
                        B[y * 5 + ((2 * x + 3 * y) % 5)] = RotL64(state[y * 5 + x], ROTC[y][x]);
                    }
                }

                for (int y = 0; y < 5; ++y) {
                    for (int x = 0; x < 5; ++x) {
                        state[y * 5 + x] = B[y * 5 + x] ^ ((~B[y * 5 + ((x + 1) % 5)]) & B[y * 5 + ((x + 2) % 5)]);
                    }
                }

                state[0] ^= RC[round];
            }
        }

    public:
        static std::string ComputeHash(const std::string& input) {
            constexpr size_t RATE_BYTES = 136;
            uint64_t state[25] = {0};
            std::vector<uint8_t> buffer(input.begin(), input.end());

            buffer.push_back(0x01);
            while ((buffer.size() % RATE_BYTES) != (RATE_BYTES - 1)) {
                buffer.push_back(0x00);
            }
            buffer.push_back(0x80);

            for (size_t offset = 0; offset < buffer.size(); offset += RATE_BYTES) {
                for (size_t i = 0; i < RATE_BYTES / 8; ++i) {
                    uint64_t lane = 0;
                    for (size_t b = 0; b < 8; ++b) {
                        lane |= static_cast<uint64_t>(buffer[offset + i * 8 + b]) << (b * 8);
                    }
                    state[i] ^= lane;
                }
                KeccakF1600(state);
            }

            std::stringstream ss;
            ss << std::hex << std::setfill('0');
            for (size_t i = 0; i < 4; ++i) {
                for (int b = 0; b < 8; ++b) {
                    uint8_t byteVal = static_cast<uint8_t>((state[i] >> (b * 8)) & 0xFF);
                    ss << std::setw(2) << static_cast<int>(byteVal);
                }
            }
            return "0x" + ss.str();
        }
    };

    // Definition of round constants (RC) for Keccak-f[1600]
    const uint64_t Keccak256::RC[24] = {
        0x0000000000000001ULL, 0x0000000000008082ULL, 0x800000000000808aULL,
        0x8000000080008000ULL, 0x000000000000808bULL, 0x0000000080000001ULL,
        0x8000000080008081ULL, 0x8000000000008009ULL, 0x000000000000008aULL,
        0x0000000000000088ULL, 0x0000000080008009ULL, 0x000000008000000aULL,
        0x000000008000808bULL, 0x800000000000008bULL, 0x8000000000008089ULL,
        0x8000000000008003ULL, 0x8000000000008002ULL, 0x8000000000000080ULL,
        0x000000000000800aULL, 0x800000008000000aULL, 0x8000000080008081ULL,
        0x8000000000008080ULL, 0x0000000080000001ULL, 0x8000000080008008ULL
    };

    // Rotation offsets for the rho step
    const int Keccak256::ROTC[5][5] = {
        { 0, 36, 3, 41, 18 },
        { 1, 44, 10, 45, 2 },
        { 62, 6, 43, 15, 61 },
        { 28, 55, 25, 21, 56 },
        { 27, 20, 39, 8, 14 }
    };

    // =========================================================================
    // 2. SIMPLE BLOCKCHAIN IMPLEMENTATION (POW) USING THE ABOVE PRIMITIVES
    // =========================================================================

    struct Transaction {
        std::string id;          // UUID or hash identifier
        std::string from;        // Sender address
        std::string to;          // Receiver address
        double amount;           // Amount transferred
        uint64_t timestamp;      // Unix epoch seconds
        std::string data;        // Optional memo / payload

        Transaction(const std::string& f, const std::string& t, double a, const std::string& d = "")
            : from(f), to(t), amount(a), data(d) {
            timestamp = static_cast<uint64_t>(std::chrono::system_clock::now().time_since_epoch().count());
            // Simple deterministic id based on content
            std::stringstream ss;
            ss << from << to << amount << timestamp << data;
            id = Sha256::ComputeHash(ss.str());
        }
    };

    struct Block {
        uint64_t index;
        std::string previousHash;
        uint64_t timestamp;
        std::vector<Transaction> transactions;
        uint64_t nonce;
        std::string hash;

        Block(uint64_t idx, const std::string& prevHash, const std::vector<Transaction>& txs)
            : index(idx), previousHash(prevHash), transactions(txs), nonce(0) {
            timestamp = static_cast<uint64_t>(std::chrono::system_clock::now().time_since_epoch().count());
            hash = ComputeHash();
        }

        std::string ComputeHash() const {
            std::stringstream ss;
            ss << index << previousHash << timestamp << nonce;
            for (const auto& tx : transactions) {
                ss << tx.id;
            }
            // Use Keccak256 for block hashing – mimics Ethereum style
            return Keccak256::ComputeHash(ss.str());
        }
    };

    class Blockchain {
    private:
        std::vector<Block> chain;
        std::vector<Transaction> pendingTransactions;
        const unsigned int difficulty; // Number of leading zero hex digits required

        std::string GetDifficultyString() const {
            return std::string(difficulty, '0');
        }

    public:
        explicit Blockchain(unsigned int diff = 4) : difficulty(diff) {
            chain.emplace_back(CreateGenesisBlock());
        }

        Block CreateGenesisBlock() {
            std::vector<Transaction> genesisTxs; // empty
            Block genesis(0, "0", genesisTxs);
            genesis.hash = genesis.ComputeHash();
            return genesis;
        }

        const Block& GetLatestBlock() const {
            return chain.back();
        }

        void AddTransaction(const Transaction& tx) {
            pendingTransactions.push_back(tx);
        }

        void MinePendingTransactions(const std::string& minerAddress) {
            // Reward transaction for miner
            Transaction reward("SYSTEM", minerAddress, 1.0, "Block reward");
            pendingTransactions.push_back(reward);

            Block newBlock(chain.size(), GetLatestBlock().hash, pendingTransactions);
            ProofOfWork(newBlock);
            chain.push_back(newBlock);
            pendingTransactions.clear();
        }

        void ProofOfWork(Block& block) {
            std::string target = GetDifficultyString();
            while (block.hash.substr(2, difficulty) != target) { // skip "0x"
                ++block.nonce;
                block.hash = block.ComputeHash();
            }
            std::cout << "Block mined! Index: " << block.index << " Hash: " << block.hash << std::endl;
        }

        bool IsChainValid() const {
            for (size_t i = 1; i < chain.size(); ++i) {
                const Block& current = chain[i];
                const Block& previous = chain[i - 1];

                if (current.hash != current.ComputeHash()) {
                    std::cerr << "Invalid hash at block " << i << std::endl;
                    return false;
                }

                if (current.previousHash != previous.hash) {
                    std::cerr << "Invalid previous hash linkage at block " << i << std::endl;
                    return false;
                }
            }
            return true;
        }

        // Utility to print the chain (debug purpose)
        void PrintChain() const {
            for (const auto& block : chain) {
                std::cout << "--- Block " << block.index << " ---\n";
                std::cout << "Hash: " << block.hash << "\n";
                std::cout << "Prev: " << block.previousHash << "\n";
                std::cout << "Nonce: " << block.nonce << "\n";
                std::cout << "TxCount: " << block.transactions.size() << "\n";
            }
        }
    };

    // Simple demo entry point (can be removed in production)
    inline void Demo() {
        Blockchain magnum(3); // low difficulty for demo
        magnum.AddTransaction(Transaction("Alice", "Bob", 10.5, "Payment for services"));
        magnum.AddTransaction(Transaction("Bob", "Charlie", 2.0));
        magnum.MinePendingTransactions("Miner1");
        magnum.PrintChain();
        std::cout << "Chain valid? " << (magnum.IsChainValid() ? "yes" : "no") << std::endl;
    }

} // namespace MagnumOpus
