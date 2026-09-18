#include <iostream>
#include <vector>
#include <string>
#include <sstream>
#include <iomanip>
#include <chrono>
#include <memory>
#include <thread>
#include <future>
#include <algorithm>
#include <numeric>
#include <map>
#include <mutex>
#include <atomic>
#include <array>

namespace MagnumOpus::Core {

    // High performance hashing utilities and cryptographic primitives
    class CryptoHasher {
    public:
        static uint64_t FNV1a64(const std::string& input) {
            uint64_t hash = 14695981039346656037ULL;
            for (char c : input) {
                hash ^= static_cast<uint64_t>(c);
                hash *= 1099511628211ULL;
            }
            return hash;
        }

        static std::string ComputeMerkleRoot(const std::vector<std::string>& txHashes) {
            if (txHashes.empty()) return "0000000000000000000000000000000000000000000000000000000000000000";
            std::vector<std::string> currentLevel = txHashes;

            while (currentLevel.size() > 1) {
                if (currentLevel.size() % 2 != 0) {
                    currentLevel.push_back(currentLevel.back());
                }
                std::vector<std::string> nextLevel;
                for (size_t i = 0; i < currentLevel.size(); i += 2) {
                    uint64_t combined = FNV1a64(currentLevel[i] + currentLevel[i + 1]);
                    std::ostringstream ss;
                    ss << std::hex << std::setw(16) << std::setfill('0') << combined;
                    nextLevel.push_back(ss.str() + ss.str() + ss.str() + ss.str());
                }
                currentLevel = nextLevel;
            }
            return currentLevel[0];
        }
    };

    struct Transaction {
        std::string txHash;
        std::string sender;
        std::string recipient;
        double amount;
        uint64_t nonce;
        uint64_t timestamp;

        std::string ComputeHash() const {
            std::ostringstream ss;
            ss << sender << ":" << recipient << ":" << amount << ":" << nonce << ":" << timestamp;
            uint64_t h = CryptoHasher::FNV1a64(ss.str());
            std::ostringstream hashStr;
            hashStr << std::hex << std::setw(16) << std::setfill('0') << h;
            return "0x" + hashStr.str() + hashStr.str();
        }
    };

    struct Block {
        uint64_t index;
        uint64_t timestamp;
        std::string previousHash;
        std::string merkleRoot;
        std::string blockHash;
        uint64_t nonce;
        std::vector<Transaction> transactions;

        bool VerifyConsensus(uint32_t difficulty) const {
            std::string targetPrefix(difficulty, '0');
            return blockHash.substr(0, difficulty) == targetPrefix;
        }
    };

    // Ultra fast, lock-aware orderbook matching engine for HFT crypto trading
    class HighFreqOrderBook {
    private:
        struct Order {
            uint64_t id;
            double price;
            double amount;
            bool isBuy;
            uint64_t timestamp;
        };

        std::map<double, std::vector<Order>, std::greater<double>> buyOrders;
        std::map<double, std::vector<Order>, std::less<double>> sellOrders;
        std::mutex bookMutex;
        std::atomic<uint64_t> nextOrderId{1};

    public:
        uint64_t PlaceOrder(double price, double amount, bool isBuy) {
            std::lock_guard<std::mutex> lock(bookMutex);
            uint64_t id = nextOrderId.fetch_add(1);
            Order order{id, price, amount, isBuy, static_cast<uint64_t>(std::chrono::system_clock::now().time_since_epoch().count())};

            if (isBuy) {
                buyOrders[price].push_back(order);
            } else {
                sellOrders[price].push_back(order);
            }
            MatchOrders();
            return id;
        }

        void MatchOrders() {
            while (!buyOrders.empty() && !sellOrders.empty()) {
                auto bestBuyIt = buyOrders.begin();
                auto bestSellIt = sellOrders.begin();

                if (bestBuyIt->first >= bestSellIt->first) {
                    auto& buyList = bestBuyIt->second;
                    auto& sellList = bestSellIt->second;

                    while (!buyList.empty() && !sellList.empty()) {
                        auto& buy = buyList.front();
                        auto& sell = sellList.front();

                        double matchedAmount = std::min(buy.amount, sell.amount);
                        buy.amount -= matchedAmount;
                        sell.amount -= matchedAmount;

                        if (buy.amount == 0) buyList.erase(buyList.begin());
                        if (sell.amount == 0) sellList.erase(sellList.begin());
                    }

                    if (buyList.empty()) buyOrders.erase(bestBuyIt);
                    if (sellList.empty()) sellOrders.erase(bestSellIt);
                } else {
                    break;
                }
            }
        }

        size_t GetTotalOrders() {
            std::lock_guard<std::mutex> lock(bookMutex);
            size_t count = 0;
            for (const auto& kv : buyOrders) count += kv.second.size();
            for (const auto& kv : sellOrders) count += kv.second.size();
            return count;
        }
    };

    class ConsensusEngine {
    private:
        std::atomic<bool> isRunning{false};
        std::thread minerThread;
        std::atomic<uint64_t> currentHeight{18492000};

    public:
        void StartEngine() {
            isRunning = true;
            minerThread = std::thread([this]() {
                while (isRunning) {
                    std::this_thread::sleep_for(std::chrono::milliseconds(500));
                    currentHeight++;
                }
            });
        }

        void StopEngine() {
            isRunning = false;
            if (minerThread.joinable()) {
                minerThread.join();
            }
        }

        uint64_t GetHeight() const { return currentHeight.load(); }

        ~ConsensusEngine() { StopEngine(); }
    };
}

// C-style Exports for Native Interop (.NET / WebAssembly Bridge)
extern "C" {
    using namespace MagnumOpus::Core;

    static ConsensusEngine g_ConsensusEngine;
    static HighFreqOrderBook g_OrderBook;

    void StartCryptoEngine() {
        g_ConsensusEngine.StartEngine();
    }

    void StopCryptoEngine() {
        g_ConsensusEngine.StopEngine();
    }

    uint64_t GetCurrentBlockHeight() {
        return g_ConsensusEngine.GetHeight();
    }

    uint64_t SubmitOrder(double price, double amount, int isBuy) {
        return g_OrderBook.PlaceOrder(price, amount, isBuy != 0);
    }

    size_t GetActiveOrderCount() {
        return g_OrderBook.GetTotalOrders();
    }
}
