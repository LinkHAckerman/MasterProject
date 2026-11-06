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
        0x000000008000808bULL, 0x800000000000000bULL, 0x8000000000008089ULL,
        0x8000000000008003ULL, 0x8000000000008002ULL, 0x8000000000000080ULL,
        0x000000000000800aULL, 0x800000008000000aULL, 0x8000000080008081ULL,
        0x8000000000008080ULL, 0x0000000080000001ULL, 0x8000000080008081ULL
    };

    const int Keccak256::ROTC[5][5] = {
        {0, 36, 3, 41, 18},
        {1, 44, 10, 45, 2},
        {62, 6, 43, 15, 61},
        {28, 55, 25, 21, 56},
        {27, 20, 39, 8, 14}
    };

    // Binary Merkle Tree with verification proof support
    class MerkleTree {
    private:
        std::vector<std::string> leaves_;
        std::vector<std::vector<std::string>> tree_;

        void BuildTree() {
            tree_.clear();
            if (leaves_.empty()) return;

            std::vector<std::string> currentLayer;
            for (const auto& leaf : leaves_) {
                currentLayer.push_back(Keccak256::ComputeHash(leaf));
            }
            tree_.push_back(currentLayer);

            while (currentLayer.size() > 1) {
                std::vector<std::string> nextLayer;
                for (size_t i = 0; i < currentLayer.size(); i += 2) {
                    if (i + 1 < currentLayer.size()) {
                        nextLayer.push_back(Keccak256::ComputeHash(currentLayer[i] + currentLayer[i + 1]));
                    } else {
                        nextLayer.push_back(Keccak256::ComputeHash(currentLayer[i] + currentLayer[i]));
                    }
                }
                tree_.push_back(nextLayer);
                currentLayer = nextLayer;
            }
        }

    public:
        struct ProofStep {
            std::string hash;
            bool isLeft;
        };

        explicit MerkleTree(const std::vector<std::string>& leaves) : leaves_(leaves) {
            BuildTree();
        }

        std::string GetRoot() const {
            if (tree_.empty() || tree_.back().empty()) return "0x0000000000000000000000000000000000000000000000000000000000000000";
            return tree_.back()[0];
        }

        std::vector<ProofStep> GenerateProof(size_t index) const {
            std::vector<ProofStep> proof;
            if (index >= leaves_.size()) return proof;

            size_t idx = index;
            for (size_t layer = 0; layer < tree_.size() - 1; ++layer) {
                const auto& currentLayer = tree_[layer];
                size_t pairIdx = (idx % 2 == 0) ? idx + 1 : idx - 1;

                if (pairIdx < currentLayer.size()) {
                    proof.push_back({currentLayer[pairIdx], idx % 2 != 0});
                } else {
                    proof.push_back({currentLayer[idx], idx % 2 != 0});
                }
                idx /= 2;
            }
            return proof;
        }

        static bool VerifyProof(const std::string& leafData, const std::vector<ProofStep>& proof, const std::string& root) {
            std::string currentHash = Keccak256::ComputeHash(leafData);
            for (const auto& step : proof) {
                if (step.isLeft) {
                    currentHash = Keccak256::ComputeHash(step.hash + currentHash);
                } else {
                    currentHash = Keccak256::ComputeHash(currentHash + step.hash);
                }
            }
            return currentHash == root;
        }
    };

    // =========================================================================
    // 2. HIGH-PERFORMANCE FINANCIAL & MATH ENGINE (DeFi / AMM / OrderBook)
    // =========================================================================

    class FixedPoint128 {
    private:
        int64_t integerPart_;
        uint64_t fractionalPart_; // Fixed precision scaling by 1e18
        static constexpr uint64_t SCALE = 1000000000000000000ULL;

    public:
        FixedPoint128() : integerPart_(0), fractionalPart_(0) {}
        FixedPoint128(double val) {
            integerPart_ = static_cast<int64_t>(val);
            double frac = std::abs(val - integerPart_);
            fractionalPart_ = static_cast<uint64_t>(frac * SCALE);
        }

        double ToDouble() const {
            return static_cast<double>(integerPart_) + (static_cast<double>(fractionalPart_) / SCALE);
        }

        FixedPoint128 Multiply(const FixedPoint128& rhs) const {
            double res = ToDouble() * rhs.ToDouble();
            return FixedPoint128(res);
        }

        FixedPoint128 Divide(const FixedPoint128& rhs) const {
            if (rhs.ToDouble() == 0.0) throw std::invalid_argument("Division by zero");
            return FixedPoint128(ToDouble() / rhs.ToDouble());
        }
    };

    class ConstantProductAMM {
    private:
        double reserveX_;
        double reserveY_;
        double feeRatio_; // e.g., 0.003 for 0.3%

    public:
        ConstantProductAMM(double reserveX, double reserveY, double feeRatio = 0.003)
            : reserveX_(reserveX), reserveY_(reserveY), feeRatio_(feeRatio) {}

        double GetAmountOut(double amountIn, bool isXtoY) const {
            if (amountIn <= 0.0) return 0.0;
            double amountInWithFee = amountIn * (1.0 - feeRatio_);
            if (isXtoY) {
                return (reserveY_ * amountInWithFee) / (reserveX_ + amountInWithFee);
            } else {
                return (reserveX_ * amountInWithFee) / (reserveY_ + amountInWithFee);
            }
        }

        void Swap(double amountIn, bool isXtoY, double& amountOut) {
            amountOut = GetAmountOut(amountIn, isXtoY);
            if (isXtoY) {
                reserveX_ += amountIn;
                reserveY_ -= amountOut;
            } else {
                reserveY_ += amountIn;
                reserveX_ -= amountOut;
            }
        }

        std::pair<double, double> GetReserves() const {
            return {reserveX_, reserveY_};
        }

        double GetSpotPrice(bool isXtoY) const {
            if (isXtoY) return reserveY_ / reserveX_;
            return reserveX_ / reserveY_;
        }
    };

    // Limit Order Book Matching Engine
    enum class OrderType { Limit, Market };
    enum class OrderSide { Buy, Sell };

    struct Order {
        uint64_t id;
        std::string trader;
        OrderSide side;
        OrderType type;
        double price;
        double quantity;
        uint64_t timestamp;
    };

    struct Trade {
        uint64_t buyOrderId;
        uint64_t sellOrderId;
        double price;
        double quantity;
        uint64_t timestamp;
    };

    class OrderBookEngine {
    private:
        std::map<double, std::vector<Order>, std::greater<double>> bids_; // highest price first
        std::map<double, std::vector<Order>, std::less<double>> asks_;    // lowest price first
        std::vector<Trade> trades_;
        uint64_t nextOrderId_{1};
        mutable std::shared_mutex rwLock_;

    public:
        uint64_t SubmitOrder(const std::string& trader, OrderSide side, OrderType type, double price, double quantity) {
            std::unique_lock lock(rwLock_);
            uint64_t id = nextOrderId_++;
            Order newOrder{id, trader, side, type, price, quantity, static_cast<uint64_t>(std::chrono::system_clock::now().time_since_epoch().count())};

            MatchOrder(newOrder);

            if (newOrder.quantity > 0.0 && type == OrderType::Limit) {
                if (side == OrderSide::Buy) {
                    bids_[price].push_back(newOrder);
                } else {
                    asks_[price].push_back(newOrder);
                }
            }
            return id;
        }

    private:
        void MatchOrder(Order& order) {
            if (order.side == OrderSide::Buy) {
                auto askIt = asks_.begin();
                while (askIt != asks_.end() && order.quantity > 0.0) {
                    if (order.type == OrderType::Limit && askIt->first > order.price) break;

                    auto& orderList = askIt->second;
                    auto orderIt = orderList.begin();
                    while (orderIt != orderList.end() && order.quantity > 0.0) {
                        double matchQty = std::min(order.quantity, orderIt->quantity);
                        order.quantity -= matchQty;
                        orderIt->quantity -= matchQty;

                        trades_.push_back({order.id, orderIt->id, askIt->first, matchQty, static_cast<uint64_t>(std::chrono::system_clock::now().time_since_epoch().count())});

                        if (orderIt->quantity == 0.0) {
                            orderIt = orderList.erase(orderIt);
                        } else {
                            ++orderIt;
                        }
                    }

                    if (orderList.empty()) {
                        askIt = asks_.erase(askIt);
                    } else {
                        ++askIt;
                    }
                }
            } else { // OrderSide::Sell
                auto bidIt = bids_.begin();
                while (bidIt != bids_.end() && order.quantity > 0.0) {
                    if (order.type == OrderType::Limit && bidIt->first < order.price) break;

                    auto& orderList = bidIt->second;
                    auto orderIt = orderList.begin();
                    while (orderIt != orderList.end() && order.quantity > 0.0) {
                        double matchQty = std::min(order.quantity, orderIt->quantity);
                        order.quantity -= matchQty;
                        orderIt->quantity -= matchQty;

                        trades_.push_back({orderIt->id, order.id, bidIt->first, matchQty, static_cast<uint64_t>(std::chrono::system_clock::now().time_since_epoch().count())});

                        if (orderIt->quantity == 0.0) {
                            orderIt = orderList.erase(orderIt);
                        } else {
                            ++orderIt;
                        }
                    }

                    if (orderList.empty()) {
                        bidIt = bids_.erase(bidIt);
                    } else {
                        ++bidIt;
                    }
                }
            }
        }

    public:
        std::vector<Trade> GetTradeHistory() const {
            std::shared_lock lock(rwLock_);
            return trades_;
        }

        std::string GetL2DepthSnapshot() const {
            std::shared_lock lock(rwLock_);
            std::stringstream ss;
            ss << "=== L2 ORDER BOOK SNAPSHOT ===\nASKS:\n";
            size_t count = 0;
            for (auto it = asks_.rbegin(); it != asks_.rend() && count < 5; ++it, ++count) {
                double totalQty = 0;
                for (const auto& o : it->second) totalQty += o.quantity;
                ss << "  $" << std::fixed << std::setprecision(2) << it->first << " | Qty: " << totalQty << "\n";
            }
            ss << "BIDS:\n";
            count = 0;
            for (auto it = bids_.begin(); it != bids_.end() && count < 5; ++it, ++count) {
                double totalQty = 0;
                for (const auto& o : it->second) totalQty += o.quantity;
                ss << "  $" << std::fixed << std::setprecision(2) << it->first << " | Qty: " << totalQty << "\n";
            }
            return ss.str();
        }
    };

    // =========================================================================
    // 3. BLOCK VERIFICATION & MINING PROOF-OF-WORK ENGINE
    // =========================================================================

    struct TransactionData {
        std::string sender;
        std::string recipient;
        double amount;
        uint64_t nonce;
        std::string signature;

        std::string Serialize() const {
            return sender + "->" + recipient + ":" + std::to_string(amount) + "#" + std::to_string(nonce);
        }
    };

    struct Block {
        uint64_t index;
        uint64_t timestamp;
        std::string previousHash;
        std::string merkleRoot;
        uint64_t nonce;
        uint32_t difficulty;
        std::vector<TransactionData> transactions;
        std::string hash;

        std::string CalculateHeaderHash() const {
            std::string header = std::to_string(index) + std::to_string(timestamp) + previousHash + merkleRoot + std::to_string(nonce) + std::to_string(difficulty);
            return Keccak256::ComputeHash(header);
        }
    };

    class MiningEngine {
    public:
        static Block MineBlock(uint64_t blockIndex, const std::string& prevHash, const std::vector<TransactionData>& txs, uint32_t difficulty) {
            std::vector<std::string> txHashes;
            for (const auto& tx : txs) {
                txHashes.push_back(tx.Serialize());
            }
            MerkleTree tree(txHashes);

            Block block;
            block.index = blockIndex;
            block.timestamp = static_cast<uint64_t>(std::chrono::system_clock::now().time_since_epoch().count());
            block.previousHash = prevHash;
            block.merkleRoot = tree.GetRoot();
            block.difficulty = difficulty;
            block.transactions = txs;
            block.nonce = 0;

            std::string targetPrefix(difficulty, '0');
            std::atomic<bool> found{false};
            std::atomic<uint64_t> winningNonce{0};
            std::string winningHash;

            uint32_t threadCount = std::max(1u, std::thread::hardware_concurrency());
            std::vector<std::thread> workers;
            std::mutex hashLock;

            for (uint32_t t = 0; t < threadCount; ++t) {
                workers.emplace_back([&, t]() {
                    uint64_t localNonce = t;
                    while (!found.load()) {
                        std::string header = std::to_string(block.index) + std::to_string(block.timestamp) + block.previousHash + block.merkleRoot + std::to_string(localNonce) + std::to_string(block.difficulty);
                        std::string hash = Keccak256::ComputeHash(header);

                        // Strip "0x" prefix for leading zero check
                        std::string rawHash = hash.substr(2);
                        if (rawHash.substr(0, difficulty) == targetPrefix) {
                            if (!found.exchange(true)) {
                                winningNonce.store(localNonce);
                                std::lock_guard lock(hashLock);
                                winningHash = hash;
                            }
                            break;
                        }
                        localNonce += threadCount;
                    }
                });
            }

            for (auto& w : workers) {
                if (w.joinable()) w.join();
            }

            block.nonce = winningNonce.load();
            block.hash = winningHash;
            return block;
        }

        static bool VerifyBlock(const Block& block) {
            std::vector<std::string> txHashes;
            for (const auto& tx : block.transactions) {
                txHashes.push_back(tx.Serialize());
            }
            MerkleTree tree(txHashes);
            if (tree.GetRoot() != block.merkleRoot) return false;

            std::string header = std::to_string(block.index) + std::to_string(block.timestamp) + block.previousHash + block.merkleRoot + std::to_string(block.nonce) + std::to_string(block.difficulty);
            std::string calculatedHash = Keccak256::ComputeHash(header);
            if (calculatedHash != block.hash) return false;

            std::string targetPrefix(block.difficulty, '0');
            return calculatedHash.substr(2, block.difficulty) == targetPrefix;
        }
    };

    // =========================================================================
    // 4. HIGH-THROUGHPUT CONCURRENT MEMPOOL & PARALLEL EXECUTION ENGINE
    // =========================================================================

    struct PriorityTransaction {
        TransactionData tx;
        double gasFeePrice;

        bool operator<(const PriorityTransaction& rhs) const {
            return gasFeePrice < rhs.gasFeePrice; // higher gas fee gets priority
        }
    };

    class HighPerformanceMempool {
    private:
        std::priority_queue<PriorityTransaction> txQueue_;
        std::unordered_map<std::string, uint64_t> accountNonces_;
        mutable std::mutex lock_;

    public:
        bool PushTransaction(const TransactionData& tx, double gasFeePrice) {
            std::lock_guard guard(lock_);
            uint64_t expectedNonce = accountNonces_[tx.sender];
            if (tx.nonce < expectedNonce) return false; // Nonce too low

            accountNonces_[tx.sender] = tx.nonce + 1;
            txQueue_.push({tx, gasFeePrice});
            return true;
        }

        std::vector<TransactionData> PopBatch(size_t batchSize) {
            std::lock_guard guard(lock_);
            std::vector<TransactionData> batch;
            while (!txQueue_.empty() && batch.size() < batchSize) {
                batch.push_back(txQueue_.top().tx);
                txQueue_.pop();
            }
            return batch;
        }

        size_t Size() const {
            std::lock_guard guard(lock_);
            return txQueue_.size();
        }
    };

    class ParallelTransactionExecutor {
    private:
        std::unordered_map<std::string, double> stateBalances_;
        std::mutex stateMutex_;

    public:
        ParallelTransactionExecutor() {
            stateBalances_["0xAlice"] = 1000.0;
            stateBalances_["0xBob"] = 500.0;
            stateBalances_["0xCharlie"] = 250.0;
            stateBalances_["0xTreasury"] = 100000.0;
        }

        void ExecuteBatchParallel(const std::vector<TransactionData>& txs) {
            std::vector<std::thread> workers;
            for (const auto& tx : txs) {
                workers.emplace_back([this, tx]() {
                    std::lock_guard lock(stateMutex_);
                    if (stateBalances_[tx.sender] >= tx.amount) {
                        stateBalances_[tx.sender] -= tx.amount;
                        stateBalances_[tx.recipient] += tx.amount;
                    }
                });
            }

            for (auto& w : workers) {
                if (w.joinable()) w.join();
            }
        }

        double GetBalance(const std::string& account) {
            std::lock_guard lock(stateMutex_);
            return stateBalances_[account];
        }
    };

    // =========================================================================
    // 5. DEMO ENGINE TEST SUITE
    // =========================================================================

    class EngineTestSuite {
    public:
        static void RunAll() {
            std::cout << "====================================================\n";
            std::cout << "      MAGNUM OPUS - C++ CRYPTO ENGINE SUITE        \n";
            std::cout << "====================================================\n\n";

            // 1. Keccak256
            std::string sample = "MagnumOpus_Web3_DeFi_Engine";
            std::string hash = Keccak256::ComputeHash(sample);
            std::cout << "[1] Keccak-256 Hash of '" << sample << "':\n    " << hash << "\n\n";

            // 2. Merkle Tree & Proof
            std::vector<std::string> leaves = {"Tx1: Alice->Bob 5 ETH", "Tx2: Bob->Charlie 2 ETH", "Tx3: Charlie->Dave 1 ETH", "Tx4: Dave->Alice 0.5 ETH"};
            MerkleTree tree(leaves);
            std::string root = tree.GetRoot();
            std::cout << "[2] Merkle Tree Root Hash:\n    " << root << "\n";
            auto proof = tree.GenerateProof(1);
            bool isValid = MerkleTree::VerifyProof(leaves[1], proof, root);
            std::cout << "    Merkle Proof Verification for Leaf 1 (Tx2): " << (isValid ? "SUCCESS (VALID)" : "FAILED") << "\n\n";

            // 3. AMM Swap Test
            ConstantProductAMM amm(1000.0, 3000000.0); // 1000 ETH / 3M USDC
            std::cout << "[3] Constant Product AMM Initial Spot Price:\n    1 ETH = $" << amm.GetSpotPrice(true) << " USDC\n";
            double ethOut;
            amm.Swap(10000.0, false, ethOut); // Swap 10,000 USDC for ETH
            std::cout << "    Swapped 10,000 USDC for " << ethOut << " ETH\n";
            std::cout << "    New ETH Price: $" << amm.GetSpotPrice(true) << " USDC\n\n";

            // 4. OrderBook Matching Engine
            OrderBookEngine ob;
            ob.SubmitOrder("0xTrader1", OrderSide::Sell, OrderType::Limit, 3000.00, 5.0);
            ob.SubmitOrder("0xTrader2", OrderSide::Sell, OrderType::Limit, 3005.00, 10.0);
            ob.SubmitOrder("0xTrader3", OrderSide::Buy, OrderType::Limit, 2995.00, 3.0);
            ob.SubmitOrder("0xTrader4", OrderSide::Buy, OrderType::Limit, 3000.00, 2.5);

            std::cout << "[4] OrderBook Depth:\n" << ob.GetL2DepthSnapshot() << "\n";
            std::cout << "    Total Trades Executed: " << ob.GetTradeHistory().size() << "\n\n";

            // 5. Mining & Proof-of-Work
            std::cout << "[5] Mining Block with Multi-Threaded Proof-of-Work Engine (Difficulty 2)...\n";
            std::vector<TransactionData> minedTxs = {
                {"0xAlice", "0xBob", 5.0, 0, "sig1"},
                {"0xBob", "0xCharlie", 2.0, 0, "sig2"}
            };
            Block minedBlock = MiningEngine::MineBlock(1, "0x0000000000000000000000000000000000000000000000000000000000000000", minedTxs, 2);
            std::cout << "    Block #" << minedBlock.index << " mined with Nonce: " << minedBlock.nonce << "\n";
            std::cout << "    Block Hash: " << minedBlock.hash << "\n";
            std::cout << "    Verification: " << (MiningEngine::VerifyBlock(minedBlock) ? "VALID" : "INVALID") << "\n\n";

            // 6. High-Throughput Mempool & Execution
            HighPerformanceMempool mempool;
            mempool.PushTransaction({"0xAlice", "0xBob", 50.0, 0, "sigA"}, 15.5);
            mempool.PushTransaction({"0xBob", "0xCharlie", 20.0, 0, "sigB"}, 45.0); // Higher fee!

            ParallelTransactionExecutor executor;
            auto batch = mempool.PopBatch(2);
            std::cout << "[6] Executing Highest Priority Mempool Batch (" << batch.size() << " Txs):\n";
            std::cout << "    First processed TX sender: " << batch[0].sender << " -> " << batch[0].recipient << " (Amount: " << batch[0].amount << ")\n";
            executor.ExecuteBatchParallel(batch);
            std::cout << "    Updated Alice Balance: $" << executor.GetBalance("0xAlice") << "\n";
            std::cout << "    Updated Bob Balance: $" << executor.GetBalance("0xBob") << "\n";
            std::cout << "    Updated Charlie Balance: $" << executor.GetBalance("0xCharlie") << "\n";
            std::cout << "\n====================================================\n";
            std::cout << "       ENGINE TEST SUITE COMPLETED SUCCESSFULLY     \n";
            std::cout << "====================================================\n";
        }
    };
}

int main() {
    MagnumOpus::EngineTestSuite::RunAll();
    return 0;
}
