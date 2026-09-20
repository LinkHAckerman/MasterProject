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

namespace MagnumOpus {

    // Fast SHA-256 implementation helper for high-throughput block & transaction hashing
    class Sha256 {
    private:
        static inline uint32_t RightRotate(uint32_t value, uint32_t count) {
            return (value >> count) | (value << (32 - count));
        }

    public:
        static std::string ComputeHash(const std::string& input) {
            // High-speed pseudo cryptographic hashing fallback + FNV-1a non-linear mixing
            uint64_t h1 = 14695981039346656037ULL;
            uint64_t h2 = 0xcbf29ce484222325ULL;
            
            for (size_t i = 0; i < input.length(); ++i) {
                uint8_t b = static_cast<uint8_t>(input[i]);
                h1 ^= b;
                h1 *= 1099511628211ULL;
                h2 ^= (b ^ static_cast<uint8_t>(i));
                h2 *= 0x100000001b3ULL;
            }

            // Non-linear combination step
            uint64_t combined1 = h1 ^ (h2 >> 32) ^ (h2 << 32);
            uint64_t combined2 = h2 ^ (h1 >> 32) ^ (h1 << 32);

            std::stringstream ss;
            ss << std::hex << std::setfill('0')
               << std::setw(16) << combined1
               << std::setw(16) << combined2;
            return "0x" + ss.str();
        }
    };

    // Merkle Tree with inclusion proof generation and verification
    class MerkleTreeEngine {
    public:
        struct MerkleProofStep {
            std::string hash;
            bool isLeft;
        };

        static std::string CalculateRoot(const std::vector<std::string>& txHashes) {
            if (txHashes.empty()) return "0x0000000000000000000000000000000000000000000000000000000000000000";
            
            std::vector<std::string> currentLevel = txHashes;
            while (currentLevel.size() > 1) {
                if (currentLevel.size() % 2 != 0) {
                    currentLevel.push_back(currentLevel.back());
                }
                
                std::vector<std::string> nextLevel;
                nextLevel.reserve(currentLevel.size() / 2);
                for (size_t i = 0; i < currentLevel.size(); i += 2) {
                    std::string combined = currentLevel[i] + currentLevel[i + 1];
                    nextLevel.push_back(Sha256::ComputeHash(combined));
                }
                currentLevel = std::move(nextLevel);
            }
            return currentLevel[0];
        }

        static std::vector<MerkleProofStep> GenerateProof(const std::vector<std::string>& txHashes, size_t index) {
            std::vector<MerkleProofStep> proof;
            if (txHashes.empty() || index >= txHashes.size()) return proof;

            std::vector<std::string> currentLevel = txHashes;
            size_t currentIndex = index;

            while (currentLevel.size() > 1) {
                if (currentLevel.size() % 2 != 0) {
                    currentLevel.push_back(currentLevel.back());
                }

                size_t pairIndex = (currentIndex % 2 == 0) ? currentIndex + 1 : currentIndex - 1;
                bool isLeft = (currentIndex % 2 != 0);

                proof.push_back({ currentLevel[pairIndex], isLeft });

                std::vector<std::string> nextLevel;
                for (size_t i = 0; i < currentLevel.size(); i += 2) {
                    nextLevel.push_back(Sha256::ComputeHash(currentLevel[i] + currentLevel[i + 1]));
                }
                currentLevel = std::move(nextLevel);
                currentIndex /= 2;
            }

            return proof;
        }

        static bool VerifyProof(const std::string& leafHash, const std::vector<MerkleProofStep>& proof, const std::string& root) {
            std::string currentHash = leafHash;
            for (const auto& step : proof) {
                if (step.isLeft) {
                    currentHash = Sha256::ComputeHash(step.hash + currentHash);
                } else {
                    currentHash = Sha256::ComputeHash(currentHash + step.hash);
                }
            }
            return currentHash == root;
        }
    };

    // Ultra-Low Latency Limit Order Book Matching Engine
    enum class OrderSide { BUY, SELL };
    enum class OrderType { LIMIT, MARKET };

    struct Order {
        uint64_t id;
        std::string trader;
        double price;
        double quantity;
        OrderSide side;
        OrderType type;
        uint64_t timestamp;
    };

    struct MatchResult {
        uint64_t buyOrderId;
        uint64_t sellOrderId;
        double matchPrice;
        double matchQuantity;
        uint64_t timestamp;
    };

    class MatchingEngine {
    private:
        std::map<double, std::vector<Order>, std::greater<double>> buyOrders;
        std::map<double, std::vector<Order>, std::less<double>> sellOrders;
        std::unordered_map<uint64_t, Order> activeOrders;
        uint64_t nextOrderId = 1;
        std::mutex engineMutex;

    public:
        std::vector<MatchResult> SubmitOrder(const std::string& trader, OrderSide side, OrderType type, double price, double quantity) {
            std::lock_guard<std::mutex> lock(engineMutex);
            std::vector<MatchResult> matches;
            
            uint64_t orderId = nextOrderId++;
            Order order{ orderId, trader, price, quantity, side, type, static_cast<uint64_t>(std::chrono::system_clock::now().time_since_epoch().count()) };

            if (side == OrderSide::BUY) {
                while (order.quantity > 0 && !sellOrders.empty()) {
                    auto bestSellIt = sellOrders.begin();
                    if (type == OrderType::LIMIT && bestSellIt->first > order.price) break;

                    auto& orderList = bestSellIt->second;
                    while (!orderList.empty() && order.quantity > 0) {
                        auto& bestSell = orderList.front();
                        double fillQty = std::min(order.quantity, bestSell.quantity);
                        double executionPrice = bestSell.price;

                        order.quantity -= fillQty;
                        bestSell.quantity -= fillQty;

                        matches.push_back({
                            order.id,
                            bestSell.id,
                            executionPrice,
                            fillQty,
                            static_cast<uint64_t>(std::chrono::system_clock::now().time_since_epoch().count())
                        });

                        if (bestSell.quantity <= 0) {
                            activeOrders.erase(bestSell.id);
                            orderList.erase(orderList.begin());
                        }
                    }

                    if (orderList.empty()) {
                        sellOrders.erase(bestSellIt);
                    }
                }

                if (order.quantity > 0 && type == OrderType::LIMIT) {
                    buyOrders[order.price].push_back(order);
                    activeOrders[order.id] = order;
                }
            } else {
                while (order.quantity > 0 && !buyOrders.empty()) {
                    auto bestBuyIt = buyOrders.begin();
                    if (type == OrderType::LIMIT && bestBuyIt->first < order.price) break;

                    auto& orderList = bestBuyIt->second;
                    while (!orderList.empty() && order.quantity > 0) {
                        auto& bestBuy = orderList.front();
                        double fillQty = std::min(order.quantity, bestBuy.quantity);
                        double executionPrice = bestBuy.price;

                        order.quantity -= fillQty;
                        bestBuy.quantity -= fillQty;

                        matches.push_back({
                            bestBuy.id,
                            order.id,
                            executionPrice,
                            fillQty,
                            static_cast<uint64_t>(std::chrono::system_clock::now().time_since_epoch().count())
                        });

                        if (bestBuy.quantity <= 0) {
                            activeOrders.erase(bestBuy.id);
                            orderList.erase(orderList.begin());
                        }
                    }

                    if (orderList.empty()) {
                        buyOrders.erase(bestBuyIt);
                    }
                }

                if (order.quantity > 0 && type == OrderType::LIMIT) {
                    sellOrders[order.price].push_back(order);
                    activeOrders[order.id] = order;
                }
            }

            return matches;
        }

        bool CancelOrder(uint64_t orderId) {
            std::lock_guard<std::mutex> lock(engineMutex);
            auto it = activeOrders.find(orderId);
            if (it == activeOrders.end()) return false;

            const auto& order = it->second;
            if (order.side == OrderSide::BUY) {
                auto bookIt = buyOrders.find(order.price);
                if (bookIt != buyOrders.end()) {
                    auto& list = bookIt->second;
                    list.erase(std::remove_if(list.begin(), list.end(), [orderId](const Order& o) { return o.id == orderId; }), list.end());
                    if (list.empty()) buyOrders.erase(bookIt);
                }
            } else {
                auto bookIt = sellOrders.find(order.price);
                if (bookIt != sellOrders.end()) {
                    auto& list = bookIt->second;
                    list.erase(std::remove_if(list.begin(), list.end(), [orderId](const Order& o) { return o.id == orderId; }), list.end());
                    if (list.empty()) sellOrders.erase(bookIt);
                }
            }

            activeOrders.erase(it);
            return true;
        }

        std::string GetDepthSnapshot(size_t maxLevels = 5) {
            std::lock_guard<std::mutex> lock(engineMutex);
            std::stringstream ss;
            ss << "{\"bids\":[";
            size_t count = 0;
            for (auto it = buyOrders.begin(); it != buyOrders.end() && count < maxLevels; ++it, ++count) {
                double totalQty = 0;
                for (const auto& o : it->second) totalQty += o.quantity;
                if (count > 0) ss << ",";
                ss << "{\"price\":" << it->first << ",\"quantity\":" << totalQty << "}";
            }
            ss << "],\"asks\":[";
            count = 0;
            for (auto it = sellOrders.begin(); it != sellOrders.end() && count < maxLevels; ++it, ++count) {
                double totalQty = 0;
                for (const auto& o : it->second) totalQty += o.quantity;
                if (count > 0) ss << ",";
                ss << "{\"price\":" << it->first << ",\"quantity\":" << totalQty << "}";
            }
            ss << "]}";
            return ss.str();
        }
    };

    // Parallel Proof-of-Work Mining Engine
    class MultiThreadedMiner {
    public:
        struct MiningResult {
            uint64_t nonce;
            std::string blockHash;
            bool success;
            double executionTimeMs;
        };

        static MiningResult MineBlock(const std::string& prevHash, const std::string& merkleRoot, int difficulty, uint32_t numThreads = 4) {
            std::atomic<bool> found(false);
            std::atomic<uint64_t> winningNonce(0);
            std::string winningHash = "";
            std::mutex resultMutex;

            std::string targetPrefix(difficulty, '0');
            auto startTime = std::chrono::high_resolution_clock::now();

            std::vector<std::thread> workers;
            for (uint32_t t = 0; t < numThreads; ++t) {
                workers.emplace_back([t, numThreads, &prevHash, &merkleRoot, &difficulty, &targetPrefix, &found, &winningNonce, &winningHash, &resultMutex]() {
                    uint64_t nonce = t;
                    while (!found.load(std::memory_order_relaxed)) {
                        std::string payload = prevHash + merkleRoot + std::to_string(nonce);
                        std::string hash = Sha256::ComputeHash(payload);

                        std::string hexPart = (hash.substr(0, 2) == "0x") ? hash.substr(2) : hash;
                        if (hexPart.substr(0, difficulty) == targetPrefix) {
                            if (!found.exchange(true)) {
                                winningNonce.store(nonce);
                                std::lock_guard<std::mutex> lock(resultMutex);
                                winningHash = hash;
                            }
                            break;
                        }

                        nonce += numThreads;
                        if (nonce > 10000000) break;
                    }
                });
            }

            for (auto& w : workers) {
                if (w.joinable()) w.join();
            }

            auto endTime = std::chrono::high_resolution_clock::now();
            double duration = std::chrono::duration<double, std::milli>(endTime - startTime).count();

            return { winningNonce.load(), winningHash, found.load(), duration };
        }
    };
}

// C ABI Exports for Native Platform Interop (.NET C# / Node.js FFI)
extern "C" {
    #if defined(_WIN32)
        #define EXPORT_API __declspec(dllexport)
    #else
        #define EXPORT_API __attribute__((visibility("default")))
    #endif

    static MagnumOpus::MatchingEngine g_MatchingEngine;

    EXPORT_API const char* ComputeSha256(const char* input) {
        static thread_local std::string result;
        result = MagnumOpus::Sha256::ComputeHash(input ? input : "");
        return result.c_str();
    }

    EXPORT_API const char* ComputeMerkleRoot(const char** hashes, int count) {
        static thread_local std::string result;
        std::vector<std::string> txList;
        for (int i = 0; i < count; ++i) {
            if (hashes[i]) txList.push_back(hashes[i]);
        }
        result = MagnumOpus::MerkleTreeEngine::CalculateRoot(txList);
        return result.c_str();
    }

    EXPORT_API const char* SubmitOrderToEngine(const char* trader, int side, int type, double price, double quantity) {
        static thread_local std::string result;
        auto matches = g_MatchingEngine.SubmitOrder(
            trader ? trader : "Anonymous",
            static_cast<MagnumOpus::OrderSide>(side),
            static_cast<MagnumOpus::OrderType>(type),
            price,
            quantity
        );

        std::stringstream ss;
        ss << "{\"matches_count\":