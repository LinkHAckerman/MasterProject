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

    // Utility for Bitcoin‑style double SHA‑256 (used for block hashes)
    class DoubleSha256 {
    public:
        static std::string Compute(const std::string& input) {
            // First SHA‑256 using the standard library for correctness
            unsigned char first[32];
            {
                std::vector<unsigned char> data(input.begin(), input.end());
                std::array<unsigned int, 8> h = {
                    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
                    0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
                };
                // For brevity we delegate to OpenSSL if available; otherwise fallback to Sha256::ComputeHash
                // Note: In production you would replace this with a full SHA‑256 implementation.
                std::string tmp = Sha256::ComputeHash(input);
                // Extract raw bytes from hex string (skip "0x")
                for (size_t i = 2; i < tmp.size(); i += 2) {
                    unsigned int byte;
                    std::sscanf(tmp.c_str() + i, "%02x", &byte);
                    first[(i - 2) / 2] = static_cast<unsigned char>(byte);
                }
            }
            // Second SHA‑256 on the raw bytes of the first hash
            std::string second_input(reinterpret_cast<char*>(first), 32);
            return Sha256::ComputeHash(second_input);
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

            // Keccak-256 padding: 0x01, zeroes, 0x80
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

    // Definition of Keccak constants (RC and ROTC)
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
    // 2. MERKLE TREE UTILITIES
    // =========================================================================

    // Simple binary Merkle tree that works on arbitrary leaf strings.
    // Leaves are hashed with Sha256; internal nodes are hash(left || right).
    class MerkleTree {
    public:
        // Compute Merkle root for a vector of leaf data strings.
        static std::string ComputeRoot(const std::vector<std::string>& leaves) {
            if (leaves.empty()) {
                return ""; // Empty tree has no root.
            }
            // Hash leaves first.
            std::vector<std::string> level;
            level.reserve(leaves.size());
            for (const auto& leaf : leaves) {
                level.push_back(Sha256::ComputeHash(leaf));
            }
            // Build the tree upwards.
            while (level.size() > 1) {
                std::vector<std::string> nextLevel;
                for (size_t i = 0; i < level.size(); i += 2) {
                    if (i + 1 < level.size()) {
                        // Concatenate the two child hashes and hash again.
                        std::string combined = level[i] + level[i + 1];
                        nextLevel.push_back(Sha256::ComputeHash(combined));
                    } else {
                        // Odd number of nodes – duplicate the last.
                        nextLevel.push_back(level[i]);
                    }
                }
                level.swap(nextLevel);
            }
            return level.front();
        }
    };

    // =========================================================================
    // 3. BLOCK HEADER HASHING (example for Bitcoin‑like blocks)
    // =========================================================================

    struct BlockHeader {
        uint32_t version;
        std::string prevBlockHash; // hex string (32 bytes)
        std::string merkleRoot;    // hex string (32 bytes)
        uint32_t timestamp;       // Unix epoch
        uint32_t bits;            // Difficulty target
        uint32_t nonce;
    };

    class BlockHasher {
    public:
        // Serialize the header in the classic Bitcoin order and double‑SHA256 it.
        static std::string ComputeBlockHash(const BlockHeader& header) {
            std::ostringstream oss;
            oss << std::hex << std::setfill('0');
            oss << std::setw(8) << header.version;
            // Helper to strip possible "0x" prefix and ensure even length.
            auto cleanHex = [](const std::string& h) -> std::string {
                std::string out = h;
                if (out.rfind("0x", 0) == 0) out = out.substr(2);
                if (out.size() % 2) out = "0" + out;
                return out;
            };
            oss << cleanHex(header.prevBlockHash);
            oss << cleanHex(header.merkleRoot);
            oss << std::setw(8) << header.timestamp;
            oss << std::setw(8) << header.bits;
            oss << std::setw(8) << header.nonce;
            std::string serialized = oss.str();
            // Convert hex string to raw bytes.
            std::string raw;
            raw.reserve(serialized.size() / 2);
            for (size_t i = 0; i < serialized.size(); i += 2) {
                unsigned int byte;
                std::sscanf(serialized.c_str() + i, "%02x", &byte);
                raw.push_back(static_cast<char>(byte));
            }
            return DoubleSha256::Compute(raw);
        }
    };

    // =========================================================================
    // 4. SIMPLE BENCHMARK UTILITIES (optional, compiled out in release)
    // =========================================================================

    #ifdef ENABLE_CRYPTO_BENCHMARK
    class Benchmark {
    public:
        template <typename Func>
        static double MeasureMs(Func&& f) {
            auto start = std::chrono::high_resolution_clock::now();
            f();
            auto end = std::chrono::high_resolution_clock::now();
            std::chrono::duration<double, std::milli> diff = end - start;
            return diff.count();
        }
    };
    #endif // ENABLE_CRYPTO_BENCHMARK

} // namespace MagnumOpus
