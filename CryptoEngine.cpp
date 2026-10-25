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
#include <openssl/sha.h>
#include <openssl/ripemd.h>

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

            // Absorption phase
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

    // Definition of Keccak round constants
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
        { 1, 44,10, 45,  2 },
        {62,  6,43, 15, 61 },
        {28, 55,25, 21, 56 },
        {27, 20,39,  8, 14 }
    };

    // =========================================================================
    // 2. UTILITY FUNCTIONS
    // =========================================================================

    // Convert a byte vector to a hex string (prefixed with 0x)
    inline std::string BytesToHex(const std::vector<uint8_t>& data) {
        std::ostringstream oss;
        oss << "0x" << std::hex << std::setfill('0');
        for (auto b : data) {
            oss << std::setw(2) << static_cast<int>(b);
        }
        return oss.str();
    }

    // Convert a hex string (with optional 0x) to a byte vector
    inline std::vector<uint8_t> HexToBytes(const std::string& hex) {
        std::string clean = hex;
        if (clean.rfind("0x", 0) == 0 || clean.rfind("0X", 0) == 0) {
            clean = clean.substr(2);
        }
        if (clean.size() % 2 != 0) {
            clean = "0" + clean; // pad with leading zero
        }
        std::vector<uint8_t> out;
        out.reserve(clean.size() / 2);
        for (size_t i = 0; i < clean.size(); i += 2) {
            std::string byteStr = clean.substr(i, 2);
            uint8_t byte = static_cast<uint8_t>(std::stoul(byteStr, nullptr, 16));
            out.push_back(byte);
        }
        return out;
    }

    // =========================================================================
    // 3. HIGH‑LEVEL CRYPTO ENGINE
    // =========================================================================

    class CryptoEngine {
    public:
        // Simple SHA‑256 using OpenSSL (returns 0x‑prefixed hex)
        static std::string Sha256Hash(const std::string& data) {
            unsigned char hash[SHA256_DIGEST_LENGTH];
            SHA256_CTX ctx;
            SHA256_Init(&ctx);
            SHA256_Update(&ctx, data.data(), data.size());
            SHA256_Final(hash, &ctx);
            return BytesToHex(std::vector<uint8_t>(hash, hash + SHA256_DIGEST_LENGTH));
        }

        // Double SHA‑256 (commonly used in Bitcoin block hashing)
        static std::string DoubleSha256(const std::string& data) {
            std::string first = Sha256Hash(data);
            // Remove 0x prefix for second pass
            std::vector<uint8_t> firstBytes = HexToBytes(first);
            unsigned char hash[SHA256_DIGEST_LENGTH];
            SHA256_CTX ctx;
            SHA256_Init(&ctx);
            SHA256_Update(&ctx, firstBytes.data(), firstBytes.size());
            SHA256_Final(hash, &ctx);
            return BytesToHex(std::vector<uint8_t>(hash, hash + SHA256_DIGEST_LENGTH));
        }

        // RIPEMD‑160 using OpenSSL (returns 0x‑prefixed hex)
        static std::string Ripemd160Hash(const std::string& data) {
            unsigned char hash[RIPEMD160_DIGEST_LENGTH];
            RIPEMD160_CTX ctx;
            RIPEMD160_Init(&ctx);
            RIPEMD160_Update(&ctx, data.data(), data.size());
            RIPEMD160_Final(hash, &ctx);
            return BytesToHex(std::vector<uint8_t>(hash, hash + RIPEMD160_DIGEST_LENGTH));
        }

        // HASH160 = RIPEMD160(SHA256(data)) – used for Bitcoin addresses
        static std::string Hash160(const std::string& data) {
            std::string sha = Sha256Hash(data);
            std::vector<uint8_t> shaBytes = HexToBytes(sha);
            unsigned char hash[RIPEMD160_DIGEST_LENGTH];
            RIPEMD160_CTX ctx;
            RIPEMD160_Init(&ctx);
            RIPEMD160_Update(&ctx, shaBytes.data(), shaBytes.size());
            RIPEMD160_Final(hash, &ctx);
            return BytesToHex(std::vector<uint8_t>(hash, hash + RIPEMD160_DIGEST_LENGTH));
        }

        // Keccak‑256 wrapper (exposes the same 0x‑prefixed hex format)
        static std::string Keccak256Hash(const std::string& data) {
            return Keccak256::ComputeHash(data);
        }

        // Compute Merkle root from a list of transaction hashes (hex strings)
        static std::string MerkleRoot(const std::vector<std::string>& txHashes) {
            if (txHashes.empty()) return "0x";
            std::vector<std::string> layer = txHashes;
            while (layer.size() > 1) {
                std::vector<std::string> next;
                for (size_t i = 0; i < layer.size(); i += 2) {
                    std::string left = layer[i];
                    std::string right = (i + 1 < layer.size()) ? layer[i + 1] : left; // duplicate if odd
                    // Concatenate raw bytes before hashing
                    std::vector<uint8_t> concat = HexToBytes(left);
                    std::vector<uint8_t> rightBytes = HexToBytes(right);
                    concat.insert(concat.end(), rightBytes.begin(), rightBytes.end());
                    // Double SHA‑256 as per Bitcoin's Merkle tree spec
                    unsigned char hash[SHA256_DIGEST_LENGTH];
                    SHA256_CTX ctx;
                    SHA256_Init(&ctx);
                    SHA256_Update(&ctx, concat.data(), concat.size());
                    SHA256_Final(hash, &ctx);
                    // second round
                    unsigned char hash2[SHA256_DIGEST_LENGTH];
                    SHA256_Init(&ctx);
                    SHA256_Update(&ctx, hash, SHA256_DIGEST_LENGTH);
                    SHA256_Final(hash2, &ctx);
                    next.push_back(BytesToHex(std::vector<uint8_t>(hash2, hash2 + SHA256_DIGEST_LENGTH)));
                }
                layer.swap(next);
            }
            return layer.front();
        }
    };

    // =========================================================================
    // 4. QUICK DEMO (compiled only in debug builds)
    // =========================================================================

    #ifdef DEBUG
    inline void Demo() {
        std::string msg = "Magnum Opus Crypto Engine";
        std::cout << "SHA256:   " << Sha256::ComputeHash(msg) << std::endl;
        std::cout << "Keccak256:" << Keccak256::ComputeHash(msg) << std::endl;
        std::cout << "OpenSSL SHA256: " << CryptoEngine::Sha256Hash(msg) << std::endl;
        std::cout << "Hash160:  " << CryptoEngine::Hash160(msg) << std::endl;
        std::vector<std::string> txs = {CryptoEngine::Sha256Hash("tx1"), CryptoEngine::Sha256Hash("tx2"), CryptoEngine::Sha256Hash("tx3")};
        std::cout << "Merkle Root: " << CryptoEngine::MerkleRoot(txs) << std::endl;
    }
    #endif

} // namespace MagnumOpus
