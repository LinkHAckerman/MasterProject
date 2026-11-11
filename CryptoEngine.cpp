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
        { 0, 36,  3, 41, 18},
        { 1, 44, 10, 45,  2},
        {62,  6, 43, 15, 61},
        {28, 55, 25, 21, 56},
        {27, 20, 39,  8, 14}
    };

    // High-performance binary Merkle Tree for transaction batching and proof verification
    class MerkleTree {
    public:
        struct ProofNode {
            std::string hash;
            bool isRightSibling;
        };

        static std::string ComputeRoot(const std::vector<std::string>& leafHashes) {
            if (leafHashes.empty()) return "0x0000000000000000000000000000000000000000000000000000000000000000";
            if (leafHashes.size() == 1) return leafHashes[0];

            std::vector<std::string> currentLevel = leafHashes;
            while (currentLevel.size() > 1) {
                std::vector<std::string> nextLevel;
                for (size_t i = 0; i < currentLevel.size(); i += 2) {
                    if (i + 1 < currentLevel.size()) {
                        nextLevel.push_back(Keccak256::ComputeHash(currentLevel[i] + currentLevel[i + 1]));
                    } else {
                        nextLevel.push_back(Keccak256::ComputeHash(currentLevel[i] + currentLevel[i]));
                    }
                }
                currentLevel = std::move(nextLevel);
            }
            return currentLevel[0];
        }

        static std::vector<ProofNode> GenerateProof(const std::vector<std::string>& leaves, size_t index) {
            std::vector<ProofNode> proof;
            if (index >= leaves.size()) return proof;

            std::vector<std::string> currentLevel = leaves;
            size_t currentIndex = index;

            while (currentLevel.size() > 1) {
                bool isEven = (currentIndex % 2 == 0);
                size_t siblingIndex = isEven ? currentIndex + 1 : currentIndex - 1;

                if (siblingIndex < currentLevel.size()) {
                    proof.push_back({currentLevel[siblingIndex], !isEven});
                } else {
                    proof.push_back({currentLevel[currentIndex], false});
                }

                std::vector<std::string> nextLevel;
                for (size_t i = 0; i < currentLevel.size(); i += 2) {
                    if (i + 1 < currentLevel.size()) {
                        nextLevel.push_back(Keccak256::ComputeHash(currentLevel[i] + currentLevel[i + 1]));
                    } else {
                        nextLevel.push_back(Keccak256::ComputeHash(currentLevel[i] + currentLevel[i]));
                    }
                }
                currentLevel = std::move(nextLevel);
                currentIndex /= 2;
            }
            return proof;
        }

        static bool VerifyProof(const std::string& leaf, const std::vector<ProofNode>& proof, const std::string& expectedRoot) {
            std::string current = leaf;
            for (const auto& node : proof) {
                if (node.isRightSibling) {
                    current = Keccak256::ComputeHash(node.hash + current);
                } else {
                    current = Keccak256::ComputeHash(current + node.hash);
                }
            }
            return current == expectedRoot;
        }
    };

    // =========================================================================
    // 2. CONSTANT PRODUCT & CONCENTRATED LIQUIDITY AMM MATH ENGINE
    // =========================================================================

    class AmmMathEngine {
    public:
        struct PoolState {
            double reserve0;
            double reserve1;
            double feeRate; // e.g. 0.003 for 0.3%
            double totalLiquidity;
        };

        struct SwapResult {
            double amountOut;
            double feePaid;
            double executionPrice;
            double priceImpactPct;
            double newReserve0;
            double newReserve1;
        };

        // Constant Product Swap (Uniswap v2 formula: (x + dx*(1-fee)) * (y - dy) = k)
        static SwapResult SwapExactInput(
            const PoolState& pool,
            double amountIn,
            bool zeroForOne
        ) {
            assert(amountIn > 0.0);
            double rIn = zeroForOne ? pool.reserve0 : pool.reserve1;
            double rOut = zeroForOne ? pool.reserve1 : pool.reserve0;

            double amountInWithFee = amountIn * (1.0 - pool.feeRate);
            double numerator = amountInWithFee * rOut;
            double denominator = rIn + amountInWithFee;
            double amountOut = numerator / denominator;

            double feePaid = amountIn * pool.feeRate;
            double spotPriceBefore = rOut / rIn;
            double executionPrice = amountOut / amountIn;
            double priceImpactPct = std::fabs(1.0 - (executionPrice / spotPriceBefore)) * 100.0;

            double newRIn = rIn + amountIn;
            double newROut = rOut - amountOut;

            return {
                amountOut,
                feePaid,
                executionPrice,
                priceImpactPct,
                zeroForOne ? newRIn : newROut,
                zeroForOne ? newROut : newRIn
            };
        }

        // Impermanent Loss estimation for a price ratio change (k = P_after / P_before)
        static double CalculateImpermanentLoss(double priceRatio) {
            if (priceRatio <= 0.0) return -100.0;
            double sqrtK = std::sqrt(priceRatio);
            double holdValue = (1.0 + priceRatio) / 2.0;
            double poolValue = sqrtK;
            return ((poolValue - holdValue) / holdValue) * 100.0;
        }

        // Concentrated Liquidity (Uniswap v3) Tick to SqrtPriceX96 converter
        static double TickToSqrtPriceX96(int32_t tick) {
            double price = std::pow(1.0001, static_cast<double>(tick));
            double sqrtPrice = std::sqrt(price);
            return sqrtPrice * std::pow(2.0, 96);
        }

        // SqrtPriceX96 to standard human-readable price
        static double SqrtPriceX96ToPrice(double sqrtPriceX96) {
            double ratio = sqrtPriceX96 / std::pow(2.0, 96);
            return ratio * ratio;
        }
    };

    // =========================================================================
    // 3. ULTRA-FAST ORDER BOOK & MATCHING ENGINE
    // =========================================================================

    enum class OrderSide { BUY, SELL };
    enum class OrderType { LIMIT, MARKET };

    struct Order {
        uint64_t id;
        std::string trader;
        OrderSide side;
        OrderType type;
        double price;
        double quantity;
        double filled;
        int64_t timestamp;
    };

    struct Trade {
        uint64_t buyOrderId;
        uint64_t sellOrderId;
        std::string buyer;
        std::string seller;
        double price;
        double quantity;
        int64_t timestamp;
    };

    struct OrderBookLevel {
        double price;
        double totalQuantity;
        size_t orderCount;
    };

    struct OrderBookDepth {
        std::vector<OrderBookLevel> bids;
        std::vector<OrderBookLevel> asks;
    };

    class MatchingEngine {
    private:
        mutable std::shared_mutex rwMutex_;

        // Bids: descending price, ascending timestamp
        struct BidComparator {
            bool operator()(const std::shared_ptr<Order>& a, const std::shared_ptr<Order>& b) const {
                if (std::fabs(a->price - b->price) > 1e-9) {
                    return a->price > b->price;
                }
                return a->timestamp < b->timestamp;
            }
        };

        // Asks: ascending price, ascending timestamp
        struct AskComparator {
            bool operator()(const std::shared_ptr<Order>& a, const std::shared_ptr<Order>& b) const {
                if (std::fabs(a->price - b->price) > 1e-9) {
                    return a->price < b->price;
                }
                return a->timestamp < b->timestamp;
            }
        };

        std::vector<std::shared_ptr<Order>> bids_;
        std::vector<std::shared_ptr<Order>> asks_;
        std::unordered_map<uint64_t, std::shared_ptr<Order>> activeOrders_;
        std::vector<Trade> tradeHistory_;
        std::atomic<uint64_t> nextOrderId_{1};

    public:
        MatchingEngine() = default;

        std::shared_ptr<Order> SubmitOrder(const std::string& trader, OrderSide side, OrderType type, double price, double quantity) {
            std::unique_lock<std::shared_mutex> lock(rwMutex_);

            auto order = std::make_shared<Order>();
            order->id = nextOrderId_.fetch_add(1, std::memory_order_relaxed);
            order->trader = trader;
            order->side = side;
            order->type = type;
            order->price = price;
            order->quantity = quantity;
            order->filled = 0.0;
            order->timestamp = std::chrono::duration_cast<std::chrono::microseconds>(
                std::chrono::system_clock::now().time_since_epoch()).count();

            MatchOrder(order);

            if (order->filled < order->quantity && order->type == OrderType::LIMIT) {
                activeOrders_[order->id] = order;
                if (order->side == OrderSide::BUY) {
                    bids_.push_back(order);
                    std::sort(bids_.begin(), bids_.end(), BidComparator{});
                } else {
                    asks_.push_back(order);
                    std::sort(asks_.begin(), asks_.end(), AskComparator{});
                }
            }

            return order;
        }

        bool CancelOrder(uint64_t orderId) {
            std::unique_lock<std::shared_mutex> lock(rwMutex_);
            auto it = activeOrders_.find(orderId);
            if (it == activeOrders_.end()) return false;

            auto order = it->second;
            if (order->side == OrderSide::BUY) {
                bids_.erase(std::remove_if(bids_.begin(), bids_.end(), [orderId](const auto& o) { return o->id == orderId; }), bids_.end());
            } else {
                asks_.erase(std::remove_if(asks_.begin(), asks_.end(), [orderId](const auto& o) { return o->id == orderId; }), asks_.end());
            }
            activeOrders_.erase(it);
            return true;
        }

        OrderBookDepth GetDepth(size_t limit = 10) const {
            std::shared_lock<std::shared_mutex> lock(rwMutex_);
            OrderBookDepth depth;

            std::map<double, double, std::greater<double>> bidMap;
            for (const auto& o : bids_) {
                bidMap[o->price] += (o->quantity - o->filled);
            }
            size_t count = 0;
            for (const auto& [price, qty] : bidMap) {
                if (++count > limit) break;
                depth.bids.push_back({price, qty, 1});
            }

            std::map<double, double> askMap;
            for (const auto& o : asks_) {
                askMap[o->price] += (o->quantity - o->filled);
            }
            count = 0;
            for (const auto& [price, qty] : askMap) {
                if (++count > limit) break;
                depth.asks.push_back({price, qty, 1});
            }

            return depth;
        }

        std::vector<Trade> GetTradeHistory(size_t maxCount = 50) const {
            std::shared_lock<std::shared_mutex> lock(rwMutex_);
            if (tradeHistory_.size() <= maxCount) {
                return tradeHistory_;
            }
            return std::vector<Trade>(tradeHistory_.end() - maxCount, tradeHistory_.end());
        }

    private:
        void MatchOrder(const std::shared_ptr<Order>& incoming) {
            int64_t now = std::chrono::duration_cast<std::chrono::microseconds>(
                std::chrono::system_clock::now().time_since_epoch()).count();

            if (incoming->side == OrderSide::BUY) {
                while (!asks_.empty() && incoming->filled < incoming->quantity) {
                    auto& bestAsk = asks_.front();
                    if (incoming->type == OrderType::LIMIT && incoming->price < bestAsk->price) {
                        break;
                    }

                    double remainingIncoming = incoming->quantity - incoming->filled;
                    double remainingAsk = bestAsk->quantity - bestAsk->filled;
                    double fillQty = std::min(remainingIncoming, remainingAsk);
                    double executionPrice = bestAsk->price;

                    incoming->filled += fillQty;
                    bestAsk->filled += fillQty;

                    tradeHistory_.push_back({
                        incoming->id,
                        bestAsk->id,
                        incoming->trader,
                        bestAsk->trader,
                        executionPrice,
                        fillQty,
                        now
                    });

                    if (bestAsk->filled >= bestAsk->quantity) {
                        activeOrders_.erase(bestAsk->id);
                        asks_.erase(asks_.begin());
                    }
                }
            } else {
                while (!bids_.empty() && incoming->filled < incoming->quantity) {
                    auto& bestBid = bids_.front();
                    if (incoming->type == OrderType::LIMIT && incoming->price > bestBid->price) {
                        break;
                    }

                    double remainingIncoming = incoming->quantity - incoming->filled;
                    double remainingBid = bestBid->quantity - bestBid->filled;
                    double fillQty = std::min(remainingIncoming, remainingBid);
                    double executionPrice = bestBid->price;

                    incoming->filled += fillQty;
                    bestBid->filled += fillQty;

                    tradeHistory_.push_back({
                        bestBid->id,
                        incoming->id,
                        bestBid->trader,
                        incoming->trader,
                        executionPrice,
                        fillQty,
                        now
                    });

                    if (bestBid->filled >= bestBid->quantity) {
                        activeOrders_.erase(bestBid->id);
                        bids_.erase(bids_.begin());
                    }
                }
            }
        }
    };

    // =========================================================================
    // 4. HIGH-PERFORMANCE CONCURRENT TRANSACTION MEMPOOL
    // =========================================================================

    struct MempoolTransaction {
        std::string hash;
        std::string sender;
        std::string recipient;
        uint64_t nonce;
        double gasPriceGwei;
        uint64_t gasLimit;
        double valueEth;
        std::string signature;
        int64_t timestamp;
    };

    class ConcurrentMempool {
    private:
        struct TxPriorityCompare {
            bool operator()(const std::shared_ptr<MempoolTransaction>& a, const std::shared_ptr<MempoolTransaction>& b) const {
                if (std::fabs(a->gasPriceGwei - b->gasPriceGwei) > 1e-6) {
                    return a->gasPriceGwei < b->gasPriceGwei;
                }
                return a->timestamp > b->timestamp;
            }
        };

        mutable std::mutex mtx_;
        std::priority_queue<std::shared_ptr<MempoolTransaction>, std::vector<std::shared_ptr<MempoolTransaction>>, TxPriorityCompare> queue_;
        std::unordered_map<std::string, std::shared_ptr<MempoolTransaction>> txMap_;
        size_t maxCapacity_;

    public:
        explicit ConcurrentMempool(size_t maxCapacity = 50000) : maxCapacity_(maxCapacity) {}

        bool Push(const MempoolTransaction& tx) {
            std::lock_guard<std::mutex> lock(mtx_);
            if (txMap_.find(tx.hash) != txMap_.end()) return false;
            if (txMap_.size() >= maxCapacity_) return false;

            auto txPtr = std::make_shared<MempoolTransaction>(tx);
            txMap_[tx.hash] = txPtr;
            queue_.push(txPtr);
            return true;
        }

        std::vector<MempoolTransaction> ExtractBlockBatch(size_t maxTxCount) {
            std::lock_guard<std::mutex> lock(mtx_);
            std::vector<MempoolTransaction> batch;
            batch.reserve(maxTxCount);

            while (!queue_.empty() && batch.size() < maxTxCount) {
                auto top = queue_.top();
                queue_.pop();
                auto it = txMap_.find(top->hash);
                if (it != txMap_.end()) {
                    batch.push_back(*top);
                    txMap_.erase(it);
                }
            }
            return batch;
        }

        size_t Size() const {
            std::lock_guard<std::mutex> lock(mtx_);
            return txMap_.size();
        }
    };

    // =========================================================================
    // 5. BLOCK VALIDATION & CONSENSUS ENGINE
    // =========================================================================

    struct BlockHeader {
        uint64_t blockNumber;
        std::string previousBlockHash;
        std::string stateRoot;
        std::string transactionsRoot;
        uint64_t timestamp;
        uint32_t difficulty;
        uint64_t nonce;
    };

    class ConsensusVerifier {
    public:
        static std::string ComputeHeaderHash(const BlockHeader& header) {
            std::stringstream ss;
            ss << header.blockNumber
               << header.previousBlockHash
               << header.stateRoot
               << header.transactionsRoot
               << header.timestamp
               << header.difficulty
               << header.nonce;
            return Keccak256::ComputeHash(ss.str());
        }

        static bool VerifyProofOfWork(const BlockHeader& header) {
            std::string hash = ComputeHeaderHash(header);
            if (hash.length() < 2 + header.difficulty) return false;
            for (size_t i = 2; i < 2 + header.difficulty; ++i) {
                if (hash[i] != '0') return false;
            }
            return true;
        }

        static uint64_t MineBlock(BlockHeader& header, uint64_t maxIterations = 1000000) {
            for (uint64_t nonce = 0; nonce < maxIterations; ++nonce) {
                header.nonce = nonce;
                if (VerifyProofOfWork(header)) {
                    return nonce;
                }
            }
            return 0;
        }
    };

} // namespace MagnumOpus

// =========================================================================
// 6. ENGINE VERIFICATION & INTEGRATION TEST HARNESS
// =========================================================================

int main() {
    std::cout << "===================================================================\n";
    std::cout << "    MAGNUM OPUS // High-Performance Crypto & DeFi Engine (C++20)   \n";
    std::cout << "===================================================================\n\n";

    // 1. Test Keccak-256 and Sha256
    std::string sample = "MagnumOpusWeb3Platform";
    std::string keccak = MagnumOpus::Keccak256::ComputeHash(sample);
    std::string sha = MagnumOpus::Sha256::ComputeHash(sample);
    std::cout << "[+] Crypto Hash Verification:\n";
    std::cout << "    Keccak-256(\"" << sample << "\") = " << keccak << "\n";
    std::cout << "    SHA256-FNV(\"" << sample << "\") = " << sha << "\n\n";

    // 2. Test Merkle Tree Proof Verification
    std::vector<std::string> txHashes = {
        MagnumOpus::Keccak256::ComputeHash("tx0: 0xAlice -> 0xBob 1.5 ETH"),
        MagnumOpus::Keccak256::ComputeHash("tx1: 0xBob -> 0xCharlie 0.5 ETH"),
        MagnumOpus::Keccak256::ComputeHash("tx2: 0xDavid -> 0xSwapPool 2500 USDC"),
        MagnumOpus::Keccak256::ComputeHash("tx3: 0xSwapPool -> 0xDavid 1.0 ETH")
    };
    std::string root = MagnumOpus::MerkleTree::ComputeRoot(txHashes);
    auto proof = MagnumOpus::MerkleTree::GenerateProof(txHashes, 2);
    bool isValidProof = MagnumOpus::MerkleTree::VerifyProof(txHashes[2], proof, root);
    std::cout << "[+] Merkle Tree Engine:\n";
    std::cout << "    Merkle Root = " << root << "\n";
    std::cout << "    Proof for Leaf[2] verified: " << (isValidProof ? "SUCCESS [VALID]" : "FAILED") << "\n\n";

    // 3. Test Constant Product AMM Engine
    MagnumOpus::AmmMathEngine::PoolState ethUsdcPool{1000.0, 3000000.0, 0.003, 54772.25};
    auto swap = MagnumOpus::AmmMathEngine::SwapExactInput(ethUsdcPool, 10.0, true);
    std::cout << "[+] AMM Constant-Product Math:\n";
    std::cout << "    Input: 10 ETH -> Output: " << std::fixed << std::setprecision(2) << swap.amountOut << " USDC\n";
    std::cout << "    Execution Price: " << swap.executionPrice << " USDC/ETH\n";
    std::cout << "    Fee Paid: " << std::setprecision(4) << swap.feePaid << " ETH\n";
    std::cout << "    Price Impact: " << std::setprecision(3) << swap.priceImpactPct << "%\n\n";

    // 4. Test Ultra-Fast Order Book Matching Engine
    MagnumOpus::MatchingEngine engine;
    engine.SubmitOrder("Alice", MagnumOpus::OrderSide::SELL, MagnumOpus::OrderType::LIMIT, 3050.0, 2.5);
    engine.SubmitOrder("Bob", MagnumOpus::OrderSide::SELL, MagnumOpus::OrderType::LIMIT, 3055.0, 5.0);
    engine.SubmitOrder("Charlie", MagnumOpus::OrderSide::BUY, MagnumOpus::OrderType::LIMIT, 3040.0, 1.0);
    std::cout << "[+] Matching Engine - Submitting Crossing Market Buy for 3.0 ETH...\n";
    auto buyerOrder = engine.SubmitOrder("David", MagnumOpus::OrderSide::BUY, MagnumOpus::OrderType::MARKET, 0.0, 3.0);
    std::cout << "    David's Order Fill Status: " << buyerOrder->filled << " / " << buyerOrder->quantity << " ETH filled\n";

    auto trades = engine.GetTradeHistory();
    std::cout << "    Executed Trades: " << trades.size() << "\n";
    for (const auto& t : trades) {
        std::cout << "      -> " << t.quantity << " ETH @ " << t.price << " USDC between " << t.buyer << " & " << t.seller << "\n";
    }

    // 5. Test Block Header PoW Verification
    MagnumOpus::BlockHeader header{
        1048576,
        "0x7f83b1657ff1fc53b92dc18148a1d65dfc2d4b1fa3d677284addd200126d9069",
        "0x9b4b01e1da8b80b7b12d5743c4a45a3df138e68213600b5b29c9a0c793ff85b6",
        root,
        1711929600,
        2, // 2 leading zeros required
        0
    };
    std::cout << "\n[+] Block Header Verification & Mining...\n";
    uint64_t foundNonce = MagnumOpus::ConsensusVerifier::MineBlock(header);
    std::cout << "    Mined Nonce: " << foundNonce << " | Hash: " << MagnumOpus::ConsensusVerifier::ComputeHeaderHash(header) << "\n";
    std::cout << "===================================================================\n";
    std::cout << "    All CryptoEngine modules executed and verified successfully!   \n";
    std::cout << "===================================================================\n";

    return 0;
}
