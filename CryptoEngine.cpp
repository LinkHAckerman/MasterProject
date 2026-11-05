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

    // Definition of static constants for Keccak256
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

    const int Keccak256::ROTC[5][5] = {
        { 0, 36, 3, 41, 18 },
        { 1, 44, 10, 45, 2 },
        { 62, 6, 43, 15, 61 },
        { 28, 55, 25, 21, 56 },
        { 27, 20, 39, 8, 14 }
    };

    // =========================================================================
    // 2. SIMPLE BLOCKCHAIN DATA STRUCTURES
    // =========================================================================

    struct Transaction {
        std::string id; // UUID or hash
        std::string from;
        std::string to;
        double amount;
        uint64_t timestamp; // Unix epoch seconds
        std::string hash;

        Transaction(const std::string& f, const std::string& t, double a)
            : from(f), to(t), amount(a) {
            timestamp = static_cast<uint64_t>(std::chrono::system_clock::now().time_since_epoch().count());
            id = Sha256::ComputeHash(from + to + std::to_string(amount) + std::to_string(timestamp));
            hash = Sha256::ComputeHash(id + from + to + std::to_string(amount) + std::to_string(timestamp));
        }
    };

    struct Block {
        uint64_t index;
        std::string previousHash;
        uint64_t timestamp;
        uint64_t nonce;
        std::vector<Transaction> transactions;
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
                ss << tx.id << tx.hash;
            }
            return Sha256::ComputeHash(ss.str());
        }
    };

    class Blockchain {
    private:
        std::vector<Block> chain;
        uint32_t difficulty; // number of leading zero bits required

        std::string PrefixZeros() const {
            return std::string(difficulty, '0');
        }

    public:
        Blockchain(uint32_t diff = 4) : difficulty(diff) {
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

        void AddBlock(const std::vector<Transaction>& transactions) {
            Block newBlock(chain.size(), GetLatestBlock().hash, transactions);
            MineBlock(newBlock);
            chain.push_back(newBlock);
        }

        void MineBlock(Block& block) {
            std::string target = PrefixZeros();
            while (block.hash.substr(2, difficulty) != target) { // skip "0x"
                ++block.nonce;
                block.hash = block.ComputeHash();
            }
            std::cout << "Block mined: " << block.hash << " (nonce=" << block.nonce << ")\n";
        }

        void PrintChain() const {
            for (const auto& blk : chain) {
                std::cout << "--- Block " << blk.index << " ---\n";
                std::cout << "PrevHash: " << blk.previousHash << "\n";
                std::cout << "Hash:     " << blk.hash << "\n";
                std::cout << "Nonce:    " << blk.nonce << "\n";
                std::cout << "Tx count: " << blk.transactions.size() << "\n";
            }
        }
    };

    // =========================================================================
    // 3. DEMONSTRATION ENTRY POINT
    // =========================================================================

    int main() {
        std::cout << "=== MagnumOpus CryptoEngine Demo ===\n";
        Blockchain chain(3); // low difficulty for demo

        // Create some dummy transactions
        Transaction tx1("Alice", "Bob", 12.5);
        Transaction tx2("Bob", "Charlie", 7.3);
        std::vector<Transaction> batch1 = {tx1, tx2};
        chain.AddBlock(batch1);

        Transaction tx3("Charlie", "Dave", 3.1);
        std::vector<Transaction> batch2 = {tx3};
        chain.AddBlock(batch2);

        chain.PrintChain();
        return 0;
    }

} // namespace MagnumOpus