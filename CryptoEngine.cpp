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
                nextLevel.reserve(current.size() / 2);
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
                nextLevel.reserve(current.size() / 2);
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

    // High-performance Bloom Filter for fast event log topic filtering
    class BloomFilter {
    private:
        std::vector<bool> bitset_;
        size_t numHashFunctions_;

        uint64_t HashN(const std::string& item, size_t seed) const {
            uint64_t hash = 14695981039346656037ULL ^ seed;
            for (char c : item) {
                hash ^= static_cast<uint8_t>(c);
                hash *= 1099511628211ULL;
            }
            return hash;
        }

    public:
        BloomFilter(size_t size = 10000, size_t numHashes = 4)
            : bitset_(size, false), numHashFunctions_(numHashes) {}

        void Add(const std::string& item) {
            for (size_t i = 0; i < numHashFunctions_; ++i) {
                uint64_t hash = HashN(item, i * 0x9e3779b97f4a7c15ULL);
                bitset_[hash % bitset_.size()] = true;
            }
        }

        bool Contains(const std::string& item) const {
            for (size_t i = 0; i < numHashFunctions_; ++i) {
                uint64_t hash = HashN(item, i * 0x9e3779b97f4a7c15ULL);
                if (!bitset_[hash % bitset_.size()]) return false;
            }
            return true;
        }
    };

    // Sparse Merkle Tree for account state / key-value proof verification
    class SparseMerkleTree {
    private:
        std::unordered_map<std::string, std::string> store_;
        std::string defaultHash_;

    public:
        SparseMerkleTree() {
            defaultHash_ = Sha256::ComputeHash("EMPTY_NODE");
        }

        void Update(const std::string& key, const std::string& value) {
            std::string leafHash = Sha256::ComputeHash(key + ":" + value);
            store_[key] = leafHash;
        }

        std::string GetRoot() const {
            if (store_.empty()) return defaultHash_;
            std::vector<std::string> hashes;
            hashes.reserve(store_.size());
            for (const auto& pair : store_) {
                hashes.push_back(pair.second);
            }
            std::sort(hashes.begin(), hashes.end());
            return MerkleTree::ComputeRoot(hashes);
        }
    };

    // =========================================================================
    // 2. BLOCK VERIFICATION & HEADER PROCESSING ENGINE
    // =========================================================================

    struct Transaction {
        std::string hash;
        std::string sender;
        std::string recipient;
        double amount;
        double fee;
        uint64_t nonce;
        std::string signature;
        std::string payload;
        uint64_t timestamp;

        std::string ComputeHash() const {
            std::stringstream ss;
            ss << sender << ":" << recipient << ":" << amount << ":"
               << fee << ":" << nonce << ":" << payload << ":" << timestamp;
            return Keccak256::ComputeHash(ss.str());
        }
    };

    struct BlockHeader {
        uint32_t version;
        std::string previousBlockHash;
        std::string merkleRoot;
        uint64_t timestamp;
        uint32_t targetBits;
        uint64_t nonce;
    };

    struct Block {
        BlockHeader header;
        std::vector<Transaction> transactions;
        std::string hash;
    };

    class BlockValidator {
    public:
        static std::string ComputeHeaderHash(const BlockHeader& header) {
            std::stringstream ss;
            ss << header.version << ":" << header.previousBlockHash << ":"
               << header.merkleRoot << ":" << header.timestamp << ":"
               << header.targetBits << ":" << header.nonce;
            return DoubleSha256::Compute(ss.str());
        }

        static bool MeetsTargetDifficulty(const std::string& hash, uint32_t targetBits) {
            size_t requiredZeros = targetBits;
            std::string hexPrefix = hash.substr(0, std::min(requiredZeros, hash.size()));
            for (char c : hexPrefix) {
                if (c != '0' && c != 'x') return false;
            }
            return true;
        }

        static bool ValidateBlock(const Block& block, uint32_t expectedBits) {
            // 1. Verify Header Hash
            std::string calculatedHash = ComputeHeaderHash(block.header);
            if (!MeetsTargetDifficulty(calculatedHash, expectedBits)) {
                return false;
            }

            // 2. Verify Merkle Root
            std::vector<std::string> txHashes;
            txHashes.reserve(block.transactions.size());
            for (const auto& tx : block.transactions) {
                txHashes.push_back(tx.hash);
            }
            std::string calculatedMerkleRoot = MerkleTree::ComputeRoot(txHashes);
            if (calculatedMerkleRoot != block.header.merkleRoot) {
                return false;
            }

            // 3. Verify Transactions Batch
            for (const auto& tx : block.transactions) {
                if (tx.hash != tx.ComputeHash()) {
                    return false;
                }
            }

            return true;
        }

        static Block MineBlock(uint32_t version, const std::string& prevHash, const std::vector<Transaction>& txs, uint32_t targetBits, size_t maxThreads = 4) {
            Block block;
            block.header.version = version;
            block.header.previousBlockHash = prevHash;
            block.transactions = txs;
            block.header.timestamp = static_cast<uint64_t>(std::chrono::duration_cast<std::chrono::seconds>(
                std::chrono::system_clock::now().time_since_epoch()).count());
            block.header.targetBits = targetBits;

            std::vector<std::string> txHashes;
            txHashes.reserve(txs.size());
            for (const auto& tx : txs) {
                txHashes.push_back(tx.hash);
            }
            block.header.merkleRoot = MerkleTree::ComputeRoot(txHashes);

            std::atomic<bool> found(false);
            std::atomic<uint64_t> winningNonce(0);
            std::string winningHash;
            std::mutex hashMutex;

            std::vector<std::thread> workers;
            workers.reserve(maxThreads);

            for (size_t threadId = 0; threadId < maxThreads; ++threadId) {
                workers.emplace_back([&, threadId]() {
                    uint64_t startNonce = threadId * 1000000000ULL;
                    BlockHeader localHeader = block.header;
                    
                    for (uint64_t nonce = startNonce; !found.load(std::memory_order_relaxed); ++nonce) {
                        localHeader.nonce = nonce;
                        std::string hash = ComputeHeaderHash(localHeader);
                        if (MeetsTargetDifficulty(hash, targetBits)) {
                            if (!found.exchange(true)) {
                                winningNonce = nonce;
                                std::lock_guard<std::mutex> lock(hashMutex);
                                winningHash = hash;
                            }
                            break;
                        }
                        if (nonce % 500000 == 0 && found.load(std::memory_order_relaxed)) {
                            break;
                        }
                    }
                });
            }

            for (auto& worker : workers) {
                if (worker.joinable()) worker.join();
            }

            block.header.nonce = winningNonce.load();
            block.hash = winningHash;
            return block;
        }
    };

    // =========================================================================
    // 3. DEFI MATH & HIGH-FREQUENCY ORDERBOOK ENGINE
    // =========================================================================

    class ConstantProductAMM {
    private:
        double reserve0_;
        double reserve1_;
        double feeBps_; // e.g. 30 = 0.3%

    public:
        ConstantProductAMM(double initialReserve0, double initialReserve1, double feeBps = 30.0)
            : reserve0_(initialReserve0), reserve1_(initialReserve1), feeBps_(feeBps) {}

        struct SwapResult {
            double amountOut;
            double newReserve0;
            double newReserve1;
            double priceImpact;
            double feePaid;
        };

        SwapResult SwapExactIn(double amountIn, bool zeroToOne) {
            double reserveIn = zeroToOne ? reserve0_ : reserve1_;
            double reserveOut = zeroToOne ? reserve1_ : reserve0_;

            double feePaid = amountIn * (feeBps_ / 10000.0);
            double amountInWithFee = amountIn - feePaid;
            double amountOut = (amountInWithFee * reserveOut) / (reserveIn + amountInWithFee);

            double spotPriceBefore = reserveOut / reserveIn;
            double spotPriceAfter = (reserveOut - amountOut) / (reserveIn + amountInWithFee);
            double priceImpact = std::abs((spotPriceAfter - spotPriceBefore) / spotPriceBefore) * 100.0;

            if (zeroToOne) {
                reserve0_ += amountIn;
                reserve1_ -= amountOut;
            } else {
                reserve1_ += amountIn;
                reserve0_ -= amountOut;
            }

            return { amountOut, reserve0_, reserve1_, priceImpact, feePaid };
        }

        static double CalculateImpermanentLoss(double priceRatio) {
            if (priceRatio <= 0) return 0.0;
            double sqrtRatio = std::sqrt(priceRatio);
            double il = (2.0 * sqrtRatio / (1.0 + priceRatio)) - 1.0;
            return std::abs(il) * 100.0;
        }

        std::pair<double, double> GetReserves() const {
            return { reserve0_, reserve1_ };
        }
    };

    class ConcentratedLiquidityMath {
    public:
        static double TickToPrice(int32_t tick) {
            return std::pow(1.0001, static_cast<double>(tick));
        }

        static int32_t PriceToTick(double price) {
            if (price <= 0) return 0;
            return static_cast<int32_t>(std::floor(std::log(price) / std::log(1.0001)));
        }

        static double CalculateLiquidity(double amount0, double amount1, double priceCurrent, double priceLower, double priceUpper) {
            double sqrtP = std::sqrt(priceCurrent);
            double sqrtPa = std::sqrt(priceLower);
            double sqrtPb = std::sqrt(priceUpper);

            if (sqrtP <= sqrtPa) {
                return amount0 * (sqrtPa * sqrtPb) / (sqrtPb - sqrtPa);
            } else if (sqrtP < sqrtPb) {
                double l0 = amount0 * (sqrtP * sqrtPb) / (sqrtPb - sqrtP);
                double l1 = amount1 / (sqrtP - sqrtPa);
                return std::min(l0, l1);
            } else {
                return amount1 / (sqrtPb - sqrtPa);
            }
        }
    };

    struct Order {
        uint64_t id;
        std::string trader;
        bool isBuy;
        double price;
        double quantity;
        uint64_t timestamp;
    };

    struct TradeMatch {
        uint64_t buyOrderId;
        uint64_t sellOrderId;
        double price;
        double quantity;
        uint64_t timestamp;
    };

    class OrderBookEngine {
    private:
        // Bids sorted highest first, Asks sorted lowest first
        std::map<double, std::deque<Order>, std::greater<double>> bids_;
        std::map<double, std::deque<Order>, std::less<double>> asks_;
        std::atomic<uint64_t> nextOrderId_{1};
        std::mutex bookMutex_;

    public:
        uint64_t SubmitOrder(const std::string& trader, bool isBuy, double price, double quantity, std::vector<TradeMatch>& outMatches) {
            std::lock_guard<std::mutex> lock(bookMutex_);
            uint64_t orderId = nextOrderId_++;
            Order incoming{ orderId, trader, isBuy, price, quantity, static_cast<uint64_t>(std::chrono::system_clock::now().time_since_epoch().count()) };

            if (isBuy) {
                while (incoming.quantity > 0.000001 && !asks_.empty()) {
                    auto bestAskIt = asks_.begin();
                    double bestAskPrice = bestAskIt->first;
                    if (incoming.price < bestAskPrice) break;

                    auto& queue = bestAskIt->second;
                    while (!queue.empty() && incoming.quantity > 0.000001) {
                        Order& askOrder = queue.front();
                        double tradeQty = std::min(incoming.quantity, askOrder.quantity);
                        incoming.quantity -= tradeQty;
                        askOrder.quantity -= tradeQty;

                        outMatches.push_back({ incoming.id, askOrder.id, bestAskPrice, tradeQty, incoming.timestamp });

                        if (askOrder.quantity <= 0.000001) {
                            queue.pop_front();
                        }
                    }
                    if (queue.empty()) {
                        asks_.erase(bestAskIt);
                    }
                }
                if (incoming.quantity > 0.000001) {
                    bids_[incoming.price].push_back(incoming);
                }
            } else {
                while (incoming.quantity > 0.000001 && !bids_.empty()) {
                    auto bestBidIt = bids_.begin();
                    double bestBidPrice = bestBidIt->first;
                    if (incoming.price > bestBidPrice) break;

                    auto& queue = bestBidIt->second;
                    while (!queue.empty() && incoming.quantity > 0.000001) {
                        Order& bidOrder = queue.front();
                        double tradeQty = std::min(incoming.quantity, bidOrder.quantity);
                        incoming.quantity -= tradeQty;
                        bidOrder.quantity -= tradeQty;

                        outMatches.push_back({ bidOrder.id, incoming.id, bestBidPrice, tradeQty, incoming.timestamp });

                        if (bidOrder.quantity <= 0.000001) {
                            queue.pop_front();
                        }
                    }
                    if (queue.empty()) {
                        bids_.erase(bestBidIt);
                    }
                }
                if (incoming.quantity > 0.000001) {
                    asks_[incoming.price].push_back(incoming);
                }
            }
            return orderId;
        }

        std::pair<double, double> GetSpread() const {
            std::lock_guard<std::mutex> lock(const_cast<std::mutex&>(bookMutex_));
            if (bids_.empty() || asks_.empty()) return { 0.0, 0.0 };
            return { bids_.begin()->first, asks_.begin()->first };
        }
    };

    // =========================================================================
    // 4. CONCURRENT MEMPOOL ENGINE WITH ANTI-MEV PROTECTION
    // =========================================================================

    class HighPerformanceMempool {
    private:
        struct TxPriorityComparator {
            bool operator()(const Transaction& a, const Transaction& b) const {
                if (std::abs(a.fee - b.fee) > 0.000001) {
                    return a.fee < b.fee; // Higher fee gets higher priority
                }
                return a.timestamp > b.timestamp;
            }
        };

        mutable std::shared_mutex poolMutex_;
        std::unordered_map<std::string, Transaction> allTxs_;
        std::priority_queue<Transaction, std::vector<Transaction>, TxPriorityComparator> priorityQueue_;
        std::unordered_map<std::string, uint64_t> accountNonces_;
        BloomFilter duplicateFilter_{50000, 5};

    public:
        bool AddTransaction(const Transaction& tx) {
            std::unique_lock<std::shared_mutex> lock(poolMutex_);
            
            if (duplicateFilter_.Contains(tx.hash)) {
                if (allTxs_.find(tx.hash) != allTxs_.end()) {
                    return false; // Duplicate transaction
                }
            }

            uint64_t currentNonce = accountNonces_[tx.sender];
            if (tx.nonce < currentNonce) {
                return false; // Stale nonce
            }

            duplicateFilter_.Add(tx.hash);
            allTxs_[tx.hash] = tx;
            priorityQueue_.push(tx);
            accountNonces_[tx.sender] = std::max(accountNonces_[tx.sender], tx.nonce + 1);
            return true;
        }

        std::vector<Transaction> GetTopTransactions(size_t count) {
            std::shared_lock<std::shared_mutex> lock(poolMutex_);
            std::vector<Transaction> result;
            result.reserve(std::min(count, allTxs_.size()));

            auto tempQueue = priorityQueue_;
            while (!tempQueue.empty() && result.size() < count) {
                result.push_back(tempQueue.top());
                tempQueue.pop();
            }
            return result;
        }

        bool DetectSandwichMEV(const Transaction& tx) const {
            std::shared_lock<std::shared_mutex> lock(poolMutex_);
            size_t matchingSenderCount = 0;
            for (const auto& pair : allTxs_) {
                if (pair.second.sender == tx.sender && std::abs((int64_t)pair.second.timestamp - (int64_t)tx.timestamp) < 2) {
                    matchingSenderCount++;
                }
            }
            return matchingSenderCount >= 2;
        }

        size_t Size() const {
            std::shared_lock<std::shared_mutex> lock(poolMutex_);
            return allTxs_.size();
        }
    };

    // =========================================================================
    // 5. ENGINE FACADE & C-API BRIDGING MODULE
    // =========================================================================

    class CryptoEngineFacade {
    private:
        HighPerformanceMempool mempool_;
        OrderBookEngine orderBook_;
        ConstantProductAMM amm_{ 1000000.0, 350000000.0, 30.0 }; // 1M TokenA / 350M USDT
        SparseMerkleTree stateTree_;

    public:
        static CryptoEngineFacade& Instance() {
            static CryptoEngineFacade instance;
            return instance;
        }

        std::string BenchmarkHashing(size_t iterations) {
            auto start = std::chrono::high_resolution_clock::now();
            std::string sample = "MagnumOpus_Transaction_Payload_Data_Block_Header_Seed_2025";
            for (size_t i = 0; i < iterations; ++i) {
                sample = Sha256::ComputeHash(sample + std::to_string(i));
            }
            auto end = std::chrono::high_resolution_clock::now();
            double durationMs = std::chrono::duration<double, std::milli>(end - start).count();
            
            std::stringstream ss;
            ss << "Executed " << iterations << " hashes in " << std::fixed << std::setprecision(2)
               << durationMs << " ms (" << (iterations / (durationMs / 1000.0)) << " ops/sec). Final hash: "
               << sample;
            return ss.str();
        }

        HighPerformanceMempool& GetMempool() { return mempool_; }
        OrderBookEngine& GetOrderBook() { return orderBook_; }
        ConstantProductAMM& GetAMM() { return amm_; }
        SparseMerkleTree& GetStateTree() { return stateTree_; }
    };

}

// Optional C-ABI exported wrapper functions for high-speed foreign function interfacing (FFI)
extern "C" {
    const char* MagnumOpus_ComputeKeccak256(const char* input) {
        static thread_local std::string result;
        result = MagnumOpus::Keccak256::ComputeHash(input ? input : "");
        return result.c_str();
    }

    const char* MagnumOpus_BenchmarkEngine(size_t count) {
        static thread_local std::string benchResult;
        benchResult = MagnumOpus::CryptoEngineFacade::Instance().BenchmarkHashing(count);
        return benchResult.c_str();
    }
}
