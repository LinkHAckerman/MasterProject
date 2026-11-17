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
            // Simple FNV-1a + SHA-256 placeholder implementation (for demo purposes)
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

    // Utility for Bitcoin‑style double SHA‑256 (used for block hashes)
    class DoubleSha256 {
    public:
        static std::string Compute(const std::string& input) {
            // First pass
            std::string first = Sha256::ComputeHash(input);
            // Convert hex string (skip "0x") to raw bytes
            std::vector<unsigned char> firstBytes;
            firstBytes.reserve(32);
            for (size_t i = 2; i < first.size(); i += 2) {
                unsigned int byte;
                std::sscanf(first.c_str() + i, "%02x", &byte);
                firstBytes.push_back(static_cast<unsigned char>(byte));
            }
            // Second pass on raw bytes
            std::string secondInput(reinterpret_cast<char*>(firstBytes.data()), firstBytes.size());
            return Sha256::ComputeHash(secondInput);
        }
    };

    // Keccak‑256 implementation for EVM and Smart Contract Hash compatibility
    class Keccak256 {
    private:
        static const std::array<uint64_t, 24> RC;
        static const std::array<std::array<int,5>,5> ROTC;

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

        static std::string BytesToHex(const unsigned char* data, size_t len) {
            std::ostringstream oss;
            oss << std::hex << std::setfill('0');
            for (size_t i = 0; i < len; ++i) {
                oss << std::setw(2) << static_cast<int>(data[i]);
            }
            return "0x" + oss.str();
        }

    public:
        static std::string ComputeHash(const std::string& input) {
            constexpr size_t RATE_BYTES = 136; // 1088 bits for Keccak‑256
            constexpr size_t CAPACITY_BYTES = 64; // 512 bits
            constexpr size_t OUTPUT_BYTES = 32; // 256‑bit output

            // 1. Absorb phase
            std::vector<uint8_t> buffer(input.begin(), input.end());
            // Padding per Keccak spec (simple 0x01 ... 0x80)
            buffer.push_back(0x01);
            while ((buffer.size() % RATE_BYTES) != (RATE_BYTES - 1)) {
                buffer.push_back(0x00);
            }
            buffer.push_back(0x80);

            uint64_t state[25] = {0};
            for (size_t offset = 0; offset < buffer.size(); offset += RATE_BYTES) {
                for (size_t i = 0; i < RATE_BYTES / 8; ++i) {
                    uint64_t lane = 0;
                    for (size_t b = 0; b < 8; ++b) {
                        lane |= static_cast<uint64_t>(buffer[offset + i * 8 + b]) << (8 * b);
                    }
                    state[i] ^= lane;
                }
                KeccakF1600(state);
            }

            // 2. Squeeze phase
            unsigned char out[OUTPUT_BYTES];
            size_t copied = 0;
            while (copied < OUTPUT_BYTES) {
                for (size_t i = 0; i < RATE_BYTES / 8 && copied < OUTPUT_BYTES; ++i) {
                    uint64_t lane = state[i];
                    for (size_t b = 0; b < 8 && copied < OUTPUT_BYTES; ++b) {
                        out[copied++] = static_cast<unsigned char>((lane >> (8 * b)) & 0xff);
                    }
                }
                if (copied < OUTPUT_BYTES) {
                    KeccakF1600(state);
                }
            }
            return BytesToHex(out, OUTPUT_BYTES);
        }
    };

    // ---------------------------------------------------------------------
    // 2. HIGH‑LEVEL DATA STRUCTURES (Transaction, Block, Blockchain)
    // ---------------------------------------------------------------------

    struct Transaction {
        std::string id;          // UUID or hash identifier
        std::string from;
        std::string to;
        double amount;           // Simple token amount for demo
        uint64_t timestamp;      // Unix epoch seconds

        Transaction() = default;
        Transaction(const std::string& f, const std::string& t, double a)
            : from(f), to(t), amount(a) {
            timestamp = static_cast<uint64_t>(std::chrono::system_clock::now().time_since_epoch().count());
            // Compute a deterministic id based on fields
            std::stringstream ss;
            ss << from << to << amount << timestamp;
            id = Sha256::ComputeHash(ss.str());
        }

        std::string hash() const {
            std::stringstream ss;
            ss << id << from << to << std::fixed << std::setprecision(8) << amount << timestamp;
            return Sha256::ComputeHash(ss.str());
        }
    };

    struct Block {
        uint64_t index;
        std::string previousHash;
        uint64_t timestamp;
        std::vector<Transaction> transactions;
        uint64_t nonce;
        std::string hash;

        Block() = default;
        Block(uint64_t idx, const std::string& prev, const std::vector<Transaction>& txs)
            : index(idx), previousHash(prev), transactions(txs), nonce(0) {
            timestamp = static_cast<uint64_t>(std::chrono::system_clock::now().time_since_epoch().count());
            hash = computeHash();
        }

        std::string computeHash() const {
            std::stringstream ss;
            ss << index << previousHash << timestamp << nonce;
            for (const auto& tx : transactions) {
                ss << tx.hash();
            }
            return DoubleSha256::Compute(ss.str());
        }
    };

    class Blockchain {
    private:
        std::vector<Block> chain;
        size_t difficulty; // Number of leading zero hex digits required

        std::string proofOfWork(const Block& block) const {
            Block mutableBlock = block; // copy to modify nonce
            std::string target(difficulty, '0');
            while (true) {
                mutableBlock.nonce++;
                std::string hash = mutableBlock.computeHash();
                if (hash.compare(0, difficulty, target) == 0) {
                    return hash;
                }
            }
        }

        bool isValidNewBlock(const Block& newBlock, const Block& previousBlock) const {
            if (previousBlock.index + 1 != newBlock.index) return false;
            if (previousBlock.hash != newBlock.previousHash) return false;
            if (newBlock.computeHash() != newBlock.hash) return false;
            std::string target(difficulty, '0');
            if (newBlock.hash.compare(0, difficulty, target) != 0) return false;
            return true;
        }

    public:
        explicit Blockchain(size_t diff = 4) : difficulty(diff) {
            // Genesis block
            Block genesis(0, "0", {});
            genesis.nonce = 0;
            genesis.hash = genesis.computeHash();
            chain.push_back(genesis);
        }

        const Block& latestBlock() const { return chain.back(); }

        bool addBlock(const std::vector<Transaction>& txs) {
            Block newBlock(chain.size(), latestBlock().hash, txs);
            newBlock.hash = proofOfWork(newBlock);
            if (isValidNewBlock(newBlock, latestBlock())) {
                chain.push_back(newBlock);
                return true;
            }
            return false;
        }

        const std::vector<Block>& getChain() const { return chain; }
    };

    // ---------------------------------------------------------------------
    // 3. TRANSACTION POOL & MINER (Thread‑Safe)
    // ---------------------------------------------------------------------

    class TransactionPool {
    private:
        std::queue<Transaction> pending;
        mutable std::mutex mtx;
        std::condition_variable cv;
    public:
        void push(const Transaction& tx) {
            {
                std::lock_guard<std::mutex> lock(mtx);
                pending.push(tx);
            }
            cv.notify_one();
        }

        // Waits until at least one transaction is available and returns a batch
        std::vector<Transaction> popBatch(size_t maxBatchSize) {
            std::unique_lock<std::mutex> lock(mtx);
            cv.wait(lock, [this]{ return !pending.empty(); });
            std::vector<Transaction> batch;
            while (!pending.empty() && batch.size() < maxBatchSize) {
                batch.push_back(pending.front());
                pending.pop();
            }
            return batch;
        }
    };

    class Miner {
    private:
        Blockchain& blockchain;
        TransactionPool& pool;
        std::atomic<bool> running{true};
        std::thread worker;
        size_t batchSize;
    public:
        Miner(Blockchain& bc, TransactionPool& tp, size_t batch = 5)
            : blockchain(bc), pool(tp), batchSize(batch) {}

        void start() {
            worker = std::thread([this](){ this->run(); });
        }

        void stop() {
            running = false;
            // Wake up the thread if it's waiting
            pool.push(Transaction("","",0.0)); // dummy transaction to unblock
            if (worker.joinable()) worker.join();
        }

        void run() {
            while (running) {
                auto txBatch = pool.popBatch(batchSize);
                // Remove possible dummy transaction inserted during stop
                if (!running) break;
                if (!txBatch.empty()) {
                    bool ok = blockchain.addBlock(txBatch);
                    if (ok) {
                        std::cout << "[Miner] Mined block " << blockchain.latestBlock().index
                                  << " with hash " << blockchain.latestBlock().hash << std::endl;
                    } else {
                        std::cerr << "[Miner] Failed to add block" << std::endl;
                    }
                }
            }
        }
    };

    // ---------------------------------------------------------------------
    // 4. DEMONSTRATION ENTRY POINT (optional for library use)
    // ---------------------------------------------------------------------

    inline void demo() {
        Blockchain chain(3); // low difficulty for quick demo
        TransactionPool pool;
        Miner miner(chain, pool, 3);
        miner.start();

        // Simulate incoming transactions
        for (int i = 0; i < 10; ++i) {
            Transaction tx("0xAlice", "0xBob", 1.0 + i * 0.1);
            pool.push(tx);
            std::this_thread::sleep_for(std::chrono::milliseconds(150));
        }

        // Allow some time for mining
        std::this_thread::sleep_for(std::chrono::seconds(5));
        miner.stop();

        std::cout << "Final blockchain length: " << chain.getChain().size() << std::endl;
    }

} // namespace MagnumOpus

// If compiled as a standalone program, run the demo.
#ifdef MAGNUM_OPUS_STANDALONE
int main() {
    MagnumOpus::demo();
    return 0;
}
#endif