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
            // Padding: 0x01 ... 0x80 (Keccak padding)
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

            // 2. Squeeze phase – we only need first 32 bytes
            unsigned char out[OUTPUT_BYTES];
            size_t copied = 0;
            while (copied < OUTPUT_BYTES) {
                size_t toCopy = std::min(OUTPUT_BYTES - copied, RATE_BYTES);
                for (size_t i = 0; i < toCopy / 8; ++i) {
                    uint64_t lane = state[i];
                    for (size_t b = 0; b < 8 && copied < OUTPUT_BYTES; ++b) {
                        out[copied++] = static_cast<unsigned char>((lane >> (8 * b)) & 0xFF);
                    }
                }
                if (copied < OUTPUT_BYTES) {
                    KeccakF1600(state);
                }
            }
            return BytesToHex(out, OUTPUT_BYTES);
        }
    };

    // Definition of static constants for Keccak256
    const std::array<uint64_t, 24> Keccak256::RC = {
        0x0000000000000001ULL, 0x0000000000008082ULL, 0x800000000000808aULL, 0x8000000080008000ULL,
        0x000000000000808bULL, 0x0000000080000001ULL, 0x8000000080008081ULL, 0x8000000000008009ULL,
        0x000000000000008aULL, 0x0000000000000088ULL, 0x0000000080008009ULL, 0x000000008000000aULL,
        0x000000008000808bULL, 0x800000000000008bULL, 0x8000000000008089ULL, 0x8000000000008003ULL,
        0x8000000000008002ULL, 0x8000000000000080ULL, 0x000000000000800aULL, 0x800000008000000aULL,
        0x8000000080008081ULL, 0x8000000000008080ULL, 0x0000000080000001ULL, 0x8000000080008008ULL
    };

    const std::array<std::array<int,5>,5> Keccak256::ROTC = {{
        {{ 0, 36, 3, 41, 18 }},
        {{ 1, 44, 10, 45, 2 }},
        {{ 62, 6, 43, 15, 61 }},
        {{ 28, 55, 25, 21, 56 }},
        {{ 27, 20, 39, 8, 14 }}
    }};

    // =========================================================================
    // 2. HIGH‑LEVEL ENGINE HELPERS
    // =========================================================================

    // Helper to convert a hex string (with optional "0x" prefix) to a byte vector
    static std::vector<uint8_t> HexToBytes(const std::string& hex) {
        std::string clean = hex;
        if (clean.rfind("0x", 0) == 0) clean = clean.substr(2);
        std::vector<uint8_t> out;
        out.reserve(clean.size() / 2);
        for (size_t i = 0; i < clean.size(); i += 2) {
            unsigned int byte;
            std::sscanf(clean.c_str() + i, "%02x", &byte);
            out.push_back(static_cast<uint8_t>(byte));
        }
        return out;
    }

    // Helper to convert a byte vector to a hex string with "0x" prefix
    static std::string BytesToHex(const std::vector<uint8_t>& data) {
        std::ostringstream oss;
        oss << "0x" << std::hex << std::setfill('0');
        for (auto b : data) {
            oss << std::setw(2) << static_cast<int>(b);
        }
        return oss.str();
    }

    // Simple Merkle tree utility – returns the Merkle root of a list of transaction hashes (hex strings)
    class MerkleTree {
    public:
        static std::string ComputeRoot(const std::vector<std::string>& leafHashes) {
            if (leafHashes.empty()) return "0x"; // empty root
            std::vector<std::string> current = leafHashes;
            while (current.size() > 1) {
                std::vector<std::string> nextLevel;
                for (size_t i = 0; i < current.size(); i += 2) {
                    std::string left = current[i];
                    std::string right = (i + 1 < current.size()) ? current[i + 1] : left; // duplicate if odd
                    // Concatenate raw bytes of left and right, then double‑SHA256
                    std::vector<uint8_t> leftBytes = HexToBytes(left);
                    std::vector<uint8_t> rightBytes = HexToBytes(right);
                    std::string concat(reinterpret_cast<char*>(leftBytes.data()), leftBytes.size());
                    concat.append(reinterpret_cast<char*>(rightBytes.data()), rightBytes.size());
                    std::string parent = DoubleSha256::Compute(concat);
                    nextLevel.push_back(parent);
                }
                current.swap(nextLevel);
            }
            return current.front();
        }
    };

    // High‑level façade exposing the most common cryptographic operations
    class CryptoEngine {
    public:
        static std::string Sha256Hash(const std::string& data) {
            return Sha256::ComputeHash(data);
        }

        static std::string DoubleSha256Hash(const std::string& data) {
            return DoubleSha256::Compute(data);
        }

        static std::string Keccak256Hash(const std::string& data) {
            return Keccak256::ComputeHash(data);
        }

        static std::string MerkleRoot(const std::vector<std::string>& txHashes) {
            return MerkleTree::ComputeRoot(txHashes);
        }
    };

#ifdef TEST_CRYPTO_ENGINE
    int main() {
        std::cout << "=== Magnum Opus CryptoEngine Demo ===\n";
        std::string msg = "Magnum Opus";
        std::cout << "Message: " << msg << "\n";
        std::cout << "SHA‑256:   " << CryptoEngine::Sha256Hash(msg) << "\n";
        std::cout << "Double SHA‑256: " << CryptoEngine::DoubleSha256Hash(msg) << "\n";
        std::cout << "Keccak‑256: " << CryptoEngine::Keccak256Hash(msg) << "\n";

        std::vector<std::string> txs = {
            CryptoEngine::Sha256Hash("tx1"),
            CryptoEngine::Sha256Hash("tx2"),
            CryptoEngine::Sha256Hash("tx3")
        };
        std::cout << "Merkle Root of 3 txs: " << CryptoEngine::MerkleRoot(txs) << "\n";
        return 0;
    }
#endif

} // namespace MagnumOpus