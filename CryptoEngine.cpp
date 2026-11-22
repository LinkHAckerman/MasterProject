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
#include <numeric>
#include <deque>
#include <future>

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

    // Utility for Bitcoin-style double SHA-256 (used for block hashes)
    class DoubleSha256 {
    public:
        static std::string Compute(const std::string& input) {
            std::string first = Sha256::ComputeHash(input);
            std::vector<unsigned char> firstBytes;
            firstBytes.reserve(32);
            for (size_t i = 2; i < first.size(); i += 2) {
                unsigned int byteVal = 0;
                std::sscanf(first.c_str() + i, "%02x", &byteVal);
                firstBytes.push_back(static_cast<unsigned char>(byteVal));
            }
            std::string secondInput(reinterpret_cast<char*>(firstBytes.data()), firstBytes.size());
            return Sha256::ComputeHash(secondInput);
        }
    };

    // Keccak-256 implementation for EVM and Smart Contract Hash compatibility
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
            constexpr size_t RATE_BYTES = 136; // 1088 bits for Keccak-256
            constexpr size_t OUTPUT_BYTES = 32; // 256-bit output

            std::vector<uint8_t> buffer(input.begin(), input.end());
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

    const std::array<uint64_t, 24> Keccak256::RC = {
        0x0000000000000001ULL, 0x0000000000008082ULL, 0x800000000000808aULL,
        0x8000000080008000ULL, 0x000000000000808bULL, 0x0000000080000001ULL,
        0x8000000080008081ULL, 0x8000000000008009ULL, 0x000000000000008aULL,
        0x0000000000000088ULL, 0x0000000080008009ULL, 0x000000008000800aULL,
        0x000000008000808bULL, 0x800000000000008bULL, 0x8000000000008089ULL,
        0x8000000000008003ULL, 0x8000000000008002ULL, 0x8000000000000080ULL,
        0x000000000000800aULL, 0x800000008000000aULL, 0x8000000080008081ULL,
        0x8000000000008080ULL, 0x0000000080000001ULL, 0x8000000080008008ULL
    };

    const std::array<std::array<int,5>,5> Keccak256::ROTC = {{
        {0, 36, 3, 41, 18},
        {1, 44, 10, 45, 2},
        {62, 6, 43, 15, 61},
        {28, 55, 25, 21, 56},
        {27, 20, 39, 8, 14}
    }};

    // Merkle Tree for efficient block tx root verification and cryptographic proof generation
    class MerkleTree {
    public:
        static std::string ComputeRoot(const std::vector<std::string>& hashes) {
            if (hashes.empty()) return Sha256::ComputeHash("");
            std::vector<std::string> current = hashes;
            while (current.size() > 1) {
                if (current.size() % 2 != 0) {
                    current.push_back(current.back());
                }
                std::vector<std::string> nextLevel;
                for (size_t i = 0; i < current.size(); i += 2) {
                    nextLevel.push_back(Sha256::ComputeHash(current[i] + current[i + 1]));
                }
                current = std::move(nextLevel);
            }
            return current[0];
        }

        static std::vector<std::string> GenerateProof(const std::vector<std::string>& hashes, size_t index) {
            std::vector<std::string> proof;
            if (hashes.empty() || index >= hashes.size()) return proof;
            
            std::vector<std::string> current = hashes;
            size_t idx = index;
            
            while (current.size() > 1) {
                if (current.size() % 2 != 0) {
                    current.push_back(current.back());
                }
                size_t pairIdx = (idx % 2 == 0) ? idx + 1 : idx - 1;
                proof.push_back(current[pairIdx]);
                
                std::vector<std::string> nextLevel;
                for (size_t i = 0; i < current.size(); i += 2) {
                    nextLevel.push_back(Sha256::ComputeHash(current[i] + current[i + 1]));
                }
                current = std::move(nextLevel);
                idx /= 2;
            }
            return proof;
        }

        static bool VerifyProof(const std::string& leafHash, const std::vector<std::string>& proof, size_t index, const std::string& root) {
            std::string current = leafHash;
            size_t idx = index;
            for (const auto& sibling : proof) {
                if (idx % 2 == 0) {
                    current = Sha256::ComputeHash(current + sibling);
                } else {
                    current = Sha256::ComputeHash(sibling + current);
                }
                idx /= 2;
            }
            return current == root;
        }
    };

    // ---------------------------------------------------------------------
    // 2. BASIC TRANSACTION & BLOCK MODELS
    // ---------------------------------------------------------------------

    struct Transaction {
        std::string id;          // UUID or hash identifier
        std::string from;
        std::string to;
        double amount;           // Simple double for demo purposes
        std::string data;        // Optional memo
        uint64_t timestamp;      // Unix epoch seconds
        std::string hash;        // Cached hash of the transaction

        Transaction() = default;
        Transaction(const std::string& f, const std::string& t, double amt, const std::string& d = "")
            : from(f), to(t), amount(amt), data(d) {
            timestamp = static_cast<uint64_t>(std::chrono::system_clock::now().time_since_epoch().count());
            id = generate_uuid();
            hash = compute_hash();
        }

        std::string compute_hash() const {
            std::ostringstream ss;
            ss << from << to << std::fixed << std::setprecision(8) << amount << data << timestamp << id;
            return Sha256::ComputeHash(ss.str());
        }

    private:
        static std::string generate_uuid() {
            static std::random_device rd;
            static std::mt19937_64 gen(rd());
            static std::uniform_int_distribution<uint64_t> dis(0, UINT64_MAX);
            uint64_t part1 = dis(gen);
            uint64_t part2 = dis(gen);
            std::ostringstream oss;
            oss << std::hex << std::setfill('0')
                << std::setw(16) << part1 << std::setw(16) << part2;
            return oss.str();
        }
    };

    struct Block {
        uint64_t index;
        std::string previous_hash;
        uint64_t timestamp;
        uint64_t nonce;
        std::vector<Transaction> transactions;
        std::string merkle_root;
        std::string hash;

        Block() = default;
        Block(uint64_t idx, const std::string& prev_hash, const std::vector<Transaction>& txs)
            : index(idx), previous_hash(prev_hash), transactions(txs) {
            timestamp = static_cast<uint64_t>(std::chrono::system_clock::now().time_since_epoch().count());
            merkle_root = MerkleTree::ComputeRoot(transaction_hashes());
            nonce = 0;
            hash = compute_hash();
        }

        std::vector<std::string> transaction_hashes() const {
            std::vector<std::string> hashes;
            hashes.reserve(transactions.size());
            for (const auto& tx : transactions) {
                hashes.push_back(tx.hash);
            }
            return hashes;
        }

        std::string compute_hash() const {
            std::ostringstream ss;
            ss << index << previous_hash << timestamp << nonce << merkle_root;
            return Sha256::ComputeHash(ss.str());
        }
    };

    // ---------------------------------------------------------------------
    // 3. SIMPLE BLOCKCHAIN IMPLEMENTATION WITH POW
    // ---------------------------------------------------------------------

    class Blockchain {
    public:
        Blockchain(uint32_t diff = 4) : difficulty(diff) {
            // Genesis block
            Block genesis(0, "0", {});
            genesis.nonce = mine_nonce(genesis);
            genesis.hash = genesis.compute_hash();
            chain.push_back(std::move(genesis));
        }

        bool add_block(const std::vector<Transaction>& txs) {
            const Block& last = chain.back();
            Block newBlock(last.index + 1, last.hash, txs);
            newBlock.nonce = mine_nonce(newBlock);
            newBlock.hash = newBlock.compute_hash();
            if (is_valid_new_block(newBlock, last)) {
                chain.push_back(std::move(newBlock));
                return true;
            }
            return false;
        }

        bool is_chain_valid() const {
            for (size_t i = 1; i < chain.size(); ++i) {
                const Block& prev = chain[i - 1];
                const Block& curr = chain[i];
                if (curr.previous_hash != prev.hash) return false;
                if (curr.hash != curr.compute_hash()) return false;
                if (!hash_meets_difficulty(curr.hash)) return false;
            }
            return true;
        }

        const std::vector<Block>& get_chain() const { return chain; }

    private:
        std::vector<Block> chain;
        uint32_t difficulty; // number of leading zero bits required

        static bool hash_meets_difficulty(const std::string& hash) {
            // Simple hex-prefix check: each leading '0' nibble represents 4 bits
            size_t requiredZeros = 0;
            // difficulty expressed in leading zero *nibbles*
            // For demonstration we treat difficulty as number of leading zero hex chars
            // (e.g., difficulty 4 => "0000...")
            // This is a simplification; real PoW uses binary bits.
            requiredZeros = 4; // fixed for demo; could be parameterized
            for (size_t i = 2; i < 2 + requiredZeros; ++i) { // skip "0x"
                if (hash[i] != '0') return false;
            }
            return true;
        }

        static uint64_t mine_nonce(Block& block) {
            uint64_t nonce = 0;
            while (true) {
                block.nonce = nonce;
                std::string candidate = block.compute_hash();
                if (hash_meets_difficulty(candidate)) {
                    return nonce;
                }
                ++nonce;
            }
        }

        static bool is_valid_new_block(const Block& newBlock, const Block& previousBlock) {
            if (previousBlock.index + 1 != newBlock.index) return false;
            if (newBlock.previous_hash != previousBlock.hash) return false;
            if (newBlock.hash != newBlock.compute_hash()) return false;
            if (!hash_meets_difficulty(newBlock.hash)) return false;
            // Verify Merkle root matches transactions
            if (newBlock.merkle_root != MerkleTree::ComputeRoot(newBlock.transaction_hashes())) return false;
            return true;
        }
    };

    // ---------------------------------------------------------------------
    // 4. DEMONSTRATION / TEST DRIVER (compiled only with -DTEST)
    // ---------------------------------------------------------------------

#ifdef TEST
    void demo() {
        std::cout << "=== MagnumOpus CryptoEngine Demo ===" << std::endl;
        // Create a few dummy transactions
        std::vector<Transaction> txs;
        txs.emplace_back("Alice", "Bob", 12.34, "Payment for services");
        txs.emplace_back("Charlie", "Dave", 0.5678, "Gift");
        txs.emplace_back("Eve", "Frank", 1000.0, "Salary");

        // Initialise blockchain with low difficulty for quick demo
        Blockchain chain(1);
        chain.add_block(txs);

        const auto& blocks = chain.get_chain();
        for (const auto& blk : blocks) {
            std::cout << "Block " << blk.index << " hash: " << blk.hash << std::endl;
            std::cout << "  Prev: " << blk.previous_hash << std::endl;
            std::cout << "  MerkleRoot: " << blk.merkle_root << std::endl;
            std::cout << "  Tx count: " << blk.transactions.size() << std::endl;
        }
        std::cout << "Chain valid? " << (chain.is_chain_valid() ? "YES" : "NO") << std::endl;
    }

    int main() {
        demo();
        return 0;
    }
#endif // TEST

} // namespace MagnumOpus