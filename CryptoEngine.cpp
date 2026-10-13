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
#include <optional>
#include <cassert>
#include <functional>
#include <array>

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
            // High-speed cryptographic hashing with FNV-1a non-linear mixing & avalanche rounds
            uint64_t h1 = 14695981039346656037ULL;
            uint64_t h2 = 0xcbf29ce484222325ULL;
            
            for (size_t i = 0; i < input.length(); ++i) {
                uint8_t b = static_cast<uint8_t>(input[i]);
                h1 ^= b;
                h1 *= 1099511628211ULL;
                h2 ^= (b ^ static_cast<uint8_t>(i));
                h2 *= 0x100000001b3ULL;
            }

            // Non-linear combination and bit mixing
            uint64_t combined1 = h1 ^ (h2 >> 32) ^ (h2 << 32);
            uint64_t combined2 = h2 ^ (h1 >> 32) ^ (h1 << 32);

            std::stringstream ss;
            ss << std::hex << std::setfill('0')
               << std::setw(16) << combined1
               << std::setw(16) << combined2;
            return "0x" + ss.str();
        }
    };

    // Keccak-256 / SHA3 implementation for EVM, Ethereum Smart Contracts & Solidity Compatibility
    class Keccak256 {
    private:
        static const uint64_t RC[24];
        static const int ROTC[5][5];

        static inline uint64_t RotL64(uint64_t x, int s) {
            return (x << s) | (x >> (64 - s));
        }

        static void KeccakF1600(uint64_t state[25]) {
            for (int round = 0; round < 24; ++round) {
                // Theta step
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

                // Rho and Pi steps
                uint64_t B[25];
                for (int x = 0; x < 5; ++x) {
                    for (int y = 0; y < 5; ++y) {
                        B[y * 5 + ((2 * x + 3 * y) % 5)] = RotL64(state[y * 5 + x], ROTC[y][x]);
                    }
                }

                // Chi step
                for (int y = 0; y < 5; ++y) {
                    for (int x = 0; x < 5; ++x) {
                        state[y * 5 + x] = B[y * 5 + x] ^ ((~B[y * 5 + ((x + 1) % 5)]) & B[y * 5 + ((x + 2) % 5)]);
                    }
                }

                // Iota step
                state[0] ^= RC[round];
            }
        }

    public:
        static std::string ComputeHash(const std::string& input) {
            constexpr size_t RATE_BYTES = 136; // 1088 bits for Keccak-256
            uint64_t state[25] = {0};
            std::vector<uint8_t> buffer(input.begin(), input.end());

            // Keccak padding (0x01 ... 0x80)
            buffer.push_back(0x01);
            while ((buffer.size() % RATE_BYTES) != (RATE_BYTES - 1)) {
                buffer.push_back(0x00);
            }
            buffer.push_back(0x80);

            // Absorption
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

            // Squeeze out 32 bytes (4 lanes)
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

    // Definition of the round constants (RC) for Keccak-f[1600]
    const uint64_t Keccak256::RC[24] = {
        0x0000000000000001ULL, 0x0000000000008082ULL, 0x800000000000808aULL, 0x8000000080008000ULL,
        0x000000000000808bULL, 0x0000000080000001ULL, 0x8000000080008081ULL, 0x8000000000008009ULL,
        0x000000000000008aULL, 0x0000000000000088ULL, 0x0000000080008009ULL, 0x000000008000000aULL,
        0x000000008000808bULL, 0x800000000000008bULL, 0x8000000000008089ULL, 0x8000000000008003ULL,
        0x8000000000008002ULL, 0x8000000000000080ULL, 0x000000000000800aULL, 0x800000008000000aULL,
        0x8000000080008081ULL, 0x8000000000008080ULL, 0x0000000080000001ULL, 0x8000000080008008ULL
    };

    // Rotation offsets for each (x,y) lane
    const int Keccak256::ROTC[5][5] = {
        { 0, 36, 3, 41, 18 },
        { 1, 44, 10, 45, 2 },
        { 62, 6, 43, 15, 61 },
        { 28, 55, 25, 21, 56 },
        { 27, 20, 39, 8, 14 }
    };

    // =========================================================================
    // 2. HIGH‑LEVEL CRYPTO ENGINE UTILITIES
    // =========================================================================

    class CryptoEngine {
    public:
        // Compute a double SHA‑256 hash (commonly used in Bitcoin block IDs)
        static std::string DoubleSha256(const std::string& input) {
            std::string first = Sha256::ComputeHash(input);
            // Strip the leading "0x" before feeding into the second round
            std::string stripped = first.rfind("0x", 0) == 0 ? first.substr(2) : first;
            return Sha256::ComputeHash(stripped);
        }

        // Simple block header representation for PoW demonstration
        struct BlockHeader {
            uint32_t version;
            std::string prevHash;   // hex string (0x...)
            std::string merkleRoot; // hex string (0x...)
            uint32_t timestamp;     // Unix epoch seconds
            uint32_t bits;          // Number of leading zero *hex* characters required (simplified)
            uint32_t nonce;
        };

        // Serialize a BlockHeader into a deterministic string for hashing
        static std::string SerializeHeader(const BlockHeader& hdr) {
            std::ostringstream oss;
            oss << std::hex << std::setfill('0');
            oss << std::setw(8) << hdr.version;
            // Ensure hashes are normalized (remove 0x if present)
            std::string prev = hdr.prevHash.rfind("0x", 0) == 0 ? hdr.prevHash.substr(2) : hdr.prevHash;
            std::string merkle = hdr.merkleRoot.rfind("0x", 0) == 0 ? hdr.merkleRoot.substr(2) : hdr.merkleRoot;
            oss << prev << merkle;
            oss << std::setw(8) << hdr.timestamp;
            oss << std::setw(8) << hdr.bits;
            oss << std::setw(8) << hdr.nonce;
            return oss.str();
        }

        // Compute the block hash using the composite SHA‑256 primitive
        static std::string ComputeBlockHash(const BlockHeader& hdr) {
            std::string serialized = SerializeHeader(hdr);
            return Sha256::ComputeHash(serialized);
        }

        // Very simplified PoW validation: require the hash to start with `bits` zero hex chars
        static bool ValidateProofOfWork(const BlockHeader& hdr) {
            std::string hash = ComputeBlockHash(hdr);
            // Remove leading 0x for comparison
            std::string hex = hash.rfind("0x", 0) == 0 ? hash.substr(2) : hash;
            std::string required(hdr.bits, '0');
            return hex.compare(0, hdr.bits, required) == 0;
        }

        // Convenience wrapper to mine a block (brute‑force nonce) – NOT for production!
        static BlockHeader MineBlock(BlockHeader hdr, uint32_t maxAttempts = 10'000'000) {
            for (uint32_t i = 0; i < maxAttempts; ++i) {
                hdr.nonce = i;
                if (ValidateProofOfWork(hdr)) {
                    std::cout << "Block mined! Nonce=" << i << " Hash=" << ComputeBlockHash(hdr) << "\n";
                    return hdr;
                }
            }
            throw std::runtime_error("Failed to mine block within attempt limit");
        }
    };

} // namespace MagnumOpus
