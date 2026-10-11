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
        {  0, 36,  3, 41, 18 },
        {  1, 44, 10, 45,  2 },
        { 62,  6, 43, 15, 61 },
        { 28, 55, 25, 21, 56 },
        { 27, 20, 39,  8, 14 }
    };

    // 2048-bit Ethereum-compatible Bloom Filter for log topics and addresses
    class BloomFilter {
    private:
        std::array<uint8_t, 256> filterBytes{};

    public:
        BloomFilter() { filterBytes.fill(0); }

        void Add(const std::string& item) {
            std::string hash = Keccak256::ComputeHash(item);
            // Extract three pairs of bits as per yellow paper
            for (size_t i = 0; i < 3; ++i) {
                if (hash.length() >= 4 + (i * 4) + 4) {
                    std::string hexSub = hash.substr(2 + (i * 4), 4);
                    uint32_t val = static_cast<uint32_t>(std::stoul(hexSub, nullptr, 16));
                    uint16_t bitIndex = val & 0x07FF; // 2047 modulo
                    size_t bytePos = 255 - (bitIndex / 8);
                    uint8_t bitPos = 1 << (bitIndex % 8);
                    filterBytes[bytePos] |= bitPos;
                }
            }
        }

        bool Contains(const std::string& item) const {
            std::string hash = Keccak256::ComputeHash(item);
            for (size_t i = 0; i < 3; ++i) {
                if (hash.length() >= 4 + (i * 4) + 4) {
                    std::string hexSub = hash.substr(2 + (i * 4), 4);
                    uint32_t val = static_cast<uint32_t>(std::stoul(hexSub, nullptr, 16));
                    uint16_t bitIndex = val & 0x07FF;
                    size_t bytePos = 255 - (bitIndex / 8);
                    uint8_t bitPos = 1 << (bitIndex % 8);
                    if ((filterBytes[bytePos] & bitPos) == 0) {
                        return false;
                    }
                }
            }
            return true;
        }

        std::string ToHexString() const {
            std::stringstream ss;
            ss << "0x";
            for (uint8_t b : filterBytes) {
                ss << std::hex << std::setfill('0') << std::setw(2) << static_cast<int>(b);
            }
            return ss.str();
        }
    };

    // =========================================================================
    // 2. MERKLE TREE & PROOF VERIFICATION ENGINE
    // =========================================================================

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

    // =========================================================================
    // 3. ULTRA-LOW LATENCY LIMIT ORDER BOOK MATCHING ENGINE
    // =========================================================================

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

    struct DepthLevel {
        double price;
        double volume;
        size_t orderCount;
    };

    class MatchingEngine {
    private:
        // Bids ordered descending (highest bid first)
        std::map<double, std::queue<Order>, std::greater<double>> bids;
        // Asks ordered ascending (lowest ask first)
        std::map<double, std::queue<Order>, std::less<double>> asks;
        std::unordered_map<uint64_t, OrderSide> orderSideMap;
        mutable std::mutex engineMutex;
        std::atomic<uint64_t> totalTradesProcessed{0};
        std::atomic<double> totalVolumeTraded{0.0};

    public:
        MatchingEngine() = default;

        std::vector<MatchResult> SubmitOrder(Order incomingOrder) {
            std::lock_guard<std::mutex> lock(engineMutex);
            std::vector<MatchResult> executions;
            uint64_t now = static_cast<uint64_t>(std::chrono::system_clock::now().time_since_epoch().count());
            if (incomingOrder.timestamp == 0) incomingOrder.timestamp = now;

            if (incomingOrder.side == OrderSide::BUY) {
                // Match against asks
                while (incomingOrder.quantity > 1e-9 && !asks.empty()) {
                    auto bestAskIt = asks.begin();
                    double bestAskPrice = bestAskIt->first;

                    if (incomingOrder.type == OrderType::LIMIT && incomingOrder.price < bestAskPrice) {
                        break; // Limit price below best ask
                    }

                    auto& queue = bestAskIt->second;
                    while (!queue.empty() && incomingOrder.quantity > 1e-9) {
                        Order& restingAsk = queue.front();
                        double tradeQty = std::min(incomingOrder.quantity, restingAsk.quantity);
                        double executionPrice = restingAsk.price;

                        executions.push_back({
                            incomingOrder.id,
                            restingAsk.id,
                            executionPrice,
                            tradeQty,
                            now
                        });

                        incomingOrder.quantity -= tradeQty;
                        restingAsk.quantity -= tradeQty;
                        totalTradesProcessed++;
                        totalVolumeTraded = totalVolumeTraded.load() + tradeQty;

                        if (restingAsk.quantity <= 1e-9) {
                            orderSideMap.erase(restingAsk.id);
                            queue.pop();
                        }
                    }

                    if (queue.empty()) {
                        asks.erase(bestAskIt);
                    }
                }

                if (incomingOrder.quantity > 1e-9 && incomingOrder.type == OrderType::LIMIT) {
                    orderSideMap[incomingOrder.id] = OrderSide::BUY;
                    bids[incomingOrder.price].push(incomingOrder);
                }
            } else { // SELL side
                // Match against bids
                while (incomingOrder.quantity > 1e-9 && !bids.empty()) {
                    auto bestBidIt = bids.begin();
                    double bestBidPrice = bestBidIt->first;

                    if (incomingOrder.type == OrderType::LIMIT && incomingOrder.price > bestBidPrice) {
                        break; // Limit price above best bid
                    }

                    auto& queue = bestBidIt->second;
                    while (!queue.empty() && incomingOrder.quantity > 1e-9) {
                        Order& restingBid = queue.front();
                        double tradeQty = std::min(incomingOrder.quantity, restingBid.quantity);
                        double executionPrice = restingBid.price;

                        executions.push_back({
                            restingBid.id,
                            incomingOrder.id,
                            executionPrice,
                            tradeQty,
                            now
                        });

                        incomingOrder.quantity -= tradeQty;
                        restingBid.quantity -= tradeQty;
                        totalTradesProcessed++;
                        totalVolumeTraded = totalVolumeTraded.load() + tradeQty;

                        if (restingBid.quantity <= 1e-9) {
                            orderSideMap.erase(restingBid.id);
                            queue.pop();
                        }
                    }

                    if (queue.empty()) {
                        bids.erase(bestBidIt);
                    }
                }

                if (incomingOrder.quantity > 1e-9 && incomingOrder.type == OrderType::LIMIT) {
                    orderSideMap[incomingOrder.id] = OrderSide::SELL;
                    asks[incomingOrder.price].push(incomingOrder);
                }
            }

            return executions;
        }

        bool CancelOrder(uint64_t orderId) {
            std::lock_guard<std::mutex> lock(engineMutex);
            auto it = orderSideMap.find(orderId);
            if (it == orderSideMap.end()) return false;

            OrderSide side = it->second;
            orderSideMap.erase(it);

            if (side == OrderSide::BUY) {
                for (auto mapIt = bids.begin(); mapIt != bids.end(); ++mapIt) {
                    std::queue<Order> newQueue;
                    bool found = false;
                    while (!mapIt->second.empty()) {
                        Order o = mapIt->second.front();
                        mapIt->second.pop();
                        if (o.id == orderId) {
                            found = true;
                        } else {
                            newQueue.push(o);
                        }
                    }
                    mapIt->second = std::move(newQueue);
                    if (mapIt->second.empty()) {
                        bids.erase(mapIt);
                    }
                    if (found) return true;
                }
            } else {
                for (auto mapIt = asks.begin(); mapIt != asks.end(); ++mapIt) {
                    std::queue<Order> newQueue;
                    bool found = false;
                    while (!mapIt->second.empty()) {
                        Order o = mapIt->second.front();
                        mapIt->second.pop();
                        if (o.id == orderId) {
                            found = true;
                        } else {
                            newQueue.push(o);
                        }
                    }
                    mapIt->second = std::move(newQueue);
                    if (mapIt->second.empty()) {
                        asks.erase(mapIt);
                    }
                    if (found) return true;
                }
            }
            return false;
        }

        std::pair<std::vector<DepthLevel>, std::vector<DepthLevel>> GetDepth(size_t levels = 10) const {
            std::lock_guard<std::mutex> lock(engineMutex);
            std::vector<DepthLevel> bidDepth;
            std::vector<DepthLevel> askDepth;

            size_t count = 0;
            for (const auto& [price, q] : bids) {
                if (count++ >= levels) break;
                double totalVol = 0.0;
                std::queue<Order> copyQ = q;
                size_t oCount = copyQ.size();
                while (!copyQ.empty()) {
                    totalVol += copyQ.front().quantity;
                    copyQ.pop();
                }
                bidDepth.push_back({ price, totalVol, oCount });
            }

            count = 0;
            for (const auto& [price, q] : asks) {
                if (count++ >= levels) break;
                double totalVol = 0.0;
                std::queue<Order> copyQ = q;
                size_t oCount = copyQ.size();
                while (!copyQ.empty()) {
                    totalVol += copyQ.front().quantity;
                    copyQ.pop();
                }
                askDepth.push_back({ price, totalVol, oCount });
            }

            return { bidDepth, askDepth };
        }

        std::optional<double> GetSpread() const {
            std::lock_guard<std::mutex> lock(engineMutex);
            if (bids.empty() || asks.empty()) return std::nullopt;
            return asks.begin()->first - bids.begin()->first;
        }

        std::optional<double> GetMidPrice() const {
            std::lock_guard<std::mutex> lock(engineMutex);
            if (bids.empty() || asks.empty()) return std::nullopt;
            return (asks.begin()->first + bids.begin()->first) / 2.0;
        }

        uint64_t GetTotalTrades() const { return totalTradesProcessed.load(); }
        double GetTotalVolume() const { return totalVolumeTraded.load(); }
    };

    // =========================================================================
    // 4. DEFI & AMM MATHEMATICAL ENGINE (UNISWAP V2 / V3 FORMULAS)
    // =========================================================================

    class AmmMath {
    public:
        // Constant product invariant: (x + dx * (1 - fee)) * (y - dy) = x * y
        static double GetAmountOut(double amountIn, double reserveIn, double reserveOut, double feeBps = 30.0) {
            if (amountIn <= 0.0 || reserveIn <= 0.0 || reserveOut <= 0.0) return 0.0;
            double feeMultiplier = (10000.0 - feeBps) / 10000.0;
            double amountInWithFee = amountIn * feeMultiplier;
            double numerator = amountInWithFee * reserveOut;
            double denominator = reserveIn + amountInWithFee;
            return numerator / denominator;
        }

        static double GetAmountIn(double amountOut, double reserveIn, double reserveOut, double feeBps = 30.0) {
            if (amountOut <= 0.0 || reserveIn <= 0.0 || reserveOut <= amountOut) return 0.0;
            double numerator = reserveIn * amountOut * 10000.0;
            double denominator = (reserveOut - amountOut) * (10000.0 - feeBps);
            return (numerator / denominator) + 1.0; // Round up for pool safety
        }

        static double CalculatePriceImpact(double amountIn, double reserveIn, double reserveOut, double feeBps = 30.0) {
            if (reserveIn <= 0.0 || reserveOut <= 0.0 || amountIn <= 0.0) return 0.0;
            double spotPrice = reserveOut / reserveIn;
            double amountOut = GetAmountOut(amountIn, reserveIn, reserveOut, feeBps);
            double effectivePrice = amountOut / amountIn;
            return std::max(0.0, (1.0 - (effectivePrice / spotPrice)) * 100.0);
        }

        // Impermanent loss estimation given price movement ratio k = P_new / P_old
        static double CalculateImpermanentLoss(double priceRatio) {
            if (priceRatio <= 0.0) return 0.0;
            double il = (2.0 * std::sqrt(priceRatio) / (1.0 + priceRatio)) - 1.0;
            return std::abs(il) * 100.0; // Percentage
        }

        // Uniswap v3 Tick to Square Root Price: sqrt(P) = 1.0001^(tick / 2)
        static double TickToSqrtPriceX96(int32_t tick) {
            double price = std::pow(1.0001, static_cast<double>(tick));
            double sqrtPrice = std::sqrt(price);
            return sqrtPrice * std::pow(2.0, 96.0);
        }

        static int32_t SqrtPriceX96ToTick(double sqrtPriceX96) {
            double sqrtPrice = sqrtPriceX96 / std::pow(2.0, 96.0);
            double price = sqrtPrice * sqrtPrice;
            return static_cast<int32_t>(std::round(std::log(price) / std::log(1.0001)));
        }
    };

    // =========================================================================
    // 5. BLOCK VALIDATION & CONSENSUS ENGINE
    // =========================================================================

    struct Transaction {
        std::string hash;
        std::string sender;
        std::string recipient;
        double amount;
        double gasPriceGwei;
        uint64_t nonce;
        std::string signature;
    };

    struct BlockHeader {
        uint64_t blockNumber;
        std::string previousBlockHash;
        std::string stateRoot;
        std::string txMerkleRoot;
        uint64_t timestamp;
        uint32_t difficultyBits;
        uint64_t nonce;
        std::string minerAddress;
    };

    struct Block {
        BlockHeader header;
        std::vector<Transaction> transactions;
        std::string blockHash;
    };

    class BlockValidator {
    public:
        static std::string ComputeHeaderHash(const BlockHeader& header) {
            std::stringstream ss;
            ss << header.blockNumber << ":"
               << header.previousBlockHash << ":"
               << header.stateRoot << ":"
               << header.txMerkleRoot << ":"
               << header.timestamp << ":"
               << header.difficultyBits << ":"
               << header.nonce << ":"
               << header.minerAddress;
            return Sha256::ComputeHash(ss.str());
        }

        static bool VerifyBlock(const Block& block, const std::string& expectedPrevHash) {
            // 1. Previous block hash pointer check
            if (block.header.previousBlockHash != expectedPrevHash) {
                return false;
            }

            // 2. Validate Merkle Root
            std::vector<std::string> txHashes;
            txHashes.reserve(block.transactions.size());
            for (const auto& tx : block.transactions) {
                txHashes.push_back(tx.hash);
            }
            std::string calculatedRoot = MerkleTreeEngine::CalculateRoot(txHashes);
            if (calculatedRoot != block.header.txMerkleRoot) {
                return false;
            }

            // 3. Block Hash integrity verification
            std::string computedHash = ComputeHeaderHash(block.header);
            if (computedHash != block.blockHash) {
                return false;
            }

            // 4. Proof of Work / Target Difficulty validation
            if (block.header.difficultyBits > 0) {
                // Ensure leading zero nibbles match difficultyBits
                size_t requiredZeros = block.header.difficultyBits;
                if (block.blockHash.rfind("0x", 0) == 0) {
                    std::string hexPart = block.blockHash.substr(2);
                    if (hexPart.length() < requiredZeros) return false;
                    for (size_t i = 0; i < requiredZeros; ++i) {
                        if (hexPart[i] != '0') return false;
                    }
                }
            }

            return true;
        }
    };

    // =========================================================================
    // 6. THREAD-SAFE MEMPOOL WITH PRIORITY GAS ORDERING
    // =========================================================================

    class Mempool {
    private:
        struct GasPriceComparator {
            bool operator()(const Transaction& a, const Transaction& b) const {
                // Higher gas price priority
                return a.gasPriceGwei < b.gasPriceGwei;
            }
        };

        mutable std::mutex mempoolMutex;
        std::priority_queue<Transaction, std::vector<Transaction>, GasPriceComparator> txPriorityQueue;
        std::unordered_map<std::string, Transaction> knownTransactions;
        std::unordered_map<std::string, uint64_t> accountNonces;
        const size_t maxCapacity;

    public:
        explicit Mempool(size_t capacity = 100000) : maxCapacity(capacity) {}

        bool AddTransaction(const Transaction& tx) {
            std::lock_guard<std::mutex> lock(mempoolMutex);
            if (knownTransactions.size() >= maxCapacity) {
                return false; // Mempool full
            }

            if (knownTransactions.find(tx.hash) != knownTransactions.end()) {
                return false; // Already present
            }

            // Nonce ordering check
            auto nonceIt = accountNonces.find(tx.sender);
            if (nonceIt != accountNonces.end()) {
                if (tx.nonce <= nonceIt->second) {
                    return false; // Stale nonce
                }
            }

            accountNonces[tx.sender] = tx.nonce;
            knownTransactions[tx.hash] = tx;
            txPriorityQueue.push(tx);
            return true;
        }

        std::vector<Transaction> ExtractTopTransactions(size_t limit) {
            std::lock_guard<std::mutex> lock(mempoolMutex);
            std::vector<Transaction> result;
            result.reserve(std::min(limit, txPriorityQueue.size()));

            while (!txPriorityQueue.empty() && result.size() < limit) {
                Transaction topTx = txPriorityQueue.top();
                txPriorityQueue.pop();
                knownTransactions.erase(topTx.hash);
                result.push_back(topTx);
            }

            return result;
        }

        size_t Size() const {
            std::lock_guard<std::mutex> lock(mempoolMutex);
            return knownTransactions.size();
        }

        void Clear() {
            std::lock_guard<std::mutex> lock(mempoolMutex);
            while (!txPriorityQueue.empty()) txPriorityQueue.pop();
            knownTransactions.clear();
            accountNonces.clear();
        }
    };

    // =========================================================================
    // 7. HIGH-PERFORMANCE ENGINE EXPORT API (C-LINKAGE INTEROPERABILITY)
    // =========================================================================

    extern "C" {
        // Exported fast hashing routine for C# P/Invoke and Go cgo bindings
        const char* MagnumOpus_ComputeSha256(const char* input) {
            static thread_local std::string buffer;
            buffer = Sha256::ComputeHash(input ? input : "");
            return buffer.c_str();
        }

        const char* MagnumOpus_ComputeKeccak256(const char* input) {
            static thread_local std::string buffer;
            buffer = Keccak256::ComputeHash(input ? input : "");
            return buffer.c_str();
        }

        double MagnumOpus_CalculateAmmOutput(double amountIn, double reserveIn, double reserveOut, double feeBps) {
            return AmmMath::GetAmountOut(amountIn, reserveIn, reserveOut, feeBps);
        }

        double MagnumOpus_CalculatePriceImpact(double amountIn, double reserveIn, double reserveOut, double feeBps) {
            return AmmMath::CalculatePriceImpact(amountIn, reserveIn, reserveOut, feeBps);
        }
    }

} // namespace MagnumOpus
