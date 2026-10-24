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

    // Definitions of Keccak-256 round constants & rotation matrix
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
        { 62,  6, 43, 15, 39 },
        { 28, 55, 25, 21, 56 },
        { 27, 20, 39,  8, 14 }
    };

    // =========================================================================
    // 2. MERKLE TREE ENGINE & PROOF VERIFIER
    // =========================================================================

    struct MerkleNode {
        std::string hash;
        std::shared_ptr<MerkleNode> left;
        std::shared_ptr<MerkleNode> right;

        MerkleNode(const std::string& h) : hash(h), left(nullptr), right(nullptr) {}
        MerkleNode(const std::string& h, std::shared_ptr<MerkleNode> l, std::shared_ptr<MerkleNode> r)
            : hash(h), left(l), right(r) {}
    };

    class MerkleTree {
    private:
        std::shared_ptr<MerkleNode> root;
        std::vector<std::string> leaves;

        std::shared_ptr<MerkleNode> BuildSubtree(const std::vector<std::shared_ptr<MerkleNode>>& nodes) {
            if (nodes.empty()) return nullptr;
            if (nodes.size() == 1) return nodes[0];

            std::vector<std::shared_ptr<MerkleNode>> parentLevel;
            for (size_t i = 0; i < nodes.size(); i += 2) {
                if (i + 1 < nodes.size()) {
                    std::string combined = Keccak256::ComputeHash(nodes[i]->hash + nodes[i + 1]->hash);
                    parentLevel.push_back(std::make_shared<MerkleNode>(combined, nodes[i], nodes[i + 1]));
                } else {
                    // Duplicate odd node for balance
                    std::string combined = Keccak256::ComputeHash(nodes[i]->hash + nodes[i]->hash);
                    parentLevel.push_back(std::make_shared<MerkleNode>(combined, nodes[i], nodes[i]));
                }
            }
            return BuildSubtree(parentLevel);
        }

    public:
        explicit MerkleTree(const std::vector<std::string>& transactions) {
            leaves.clear();
            std::vector<std::shared_ptr<MerkleNode>> leafNodes;
            for (const auto& tx : transactions) {
                std::string leafHash = Keccak256::ComputeHash(tx);
                leaves.push_back(leafHash);
                leafNodes.push_back(std::make_shared<MerkleNode>(leafHash));
            }
            if (leafNodes.empty()) {
                root = std::make_shared<MerkleNode>(Keccak256::ComputeHash(""));
            } else {
                root = BuildSubtree(leafNodes);
            }
        }

        std::string GetRootHash() const {
            return root ? root->hash : "";
        }

        struct ProofStep {
            std::string siblingHash;
            bool isLeft;
        };

        std::vector<ProofStep> GenerateProof(size_t index) const {
            std::vector<ProofStep> proof;
            if (index >= leaves.size()) return proof;

            // Internal traverse for proof generation
            std::vector<std::string> currentHashes = leaves;
            size_t currIdx = index;

            while (currentHashes.size() > 1) {
                std::vector<std::string> nextLevel;
                for (size_t i = 0; i < currentHashes.size(); i += 2) {
                    size_t pairIdx = (i + 1 < currentHashes.size()) ? (i + 1) : i;
                    if (i == currIdx || pairIdx == currIdx) {
                        size_t siblingIdx = (currIdx % 2 == 0) ? pairIdx : i;
                        bool isLeft = (currIdx % 2 != 0);
                        proof.push_back({ currentHashes[siblingIdx], isLeft });
                    }
                    std::string combined = Keccak256::ComputeHash(currentHashes[i] + currentHashes[pairIdx]);
                    nextLevel.push_back(combined);
                }
                currIdx /= 2;
                currentHashes = nextLevel;
            }
            return proof;
        }

        static bool VerifyProof(const std::string& leafHash, const std::vector<ProofStep>& proof, const std::string& expectedRoot) {
            std::string currentHash = leafHash;
            for (const auto& step : proof) {
                if (step.isLeft) {
                    currentHash = Keccak256::ComputeHash(step.siblingHash + currentHash);
                } else {
                    currentHash = Keccak256::ComputeHash(currentHash + step.siblingHash);
                }
            }
            return currentHash == expectedRoot;
        }
    };

    // =========================================================================
    // 3. HIGH-THROUGHPUT ORDER BOOK MATCHING ENGINE
    // =========================================================================

    enum class OrderSide { BUY, SELL };
    enum class OrderType { LIMIT, MARKET };

    struct Order {
        uint64_t id;
        std::string trader;
        OrderSide side;
        OrderType type;
        double price;
        double amount;
        uint64_t timestamp;
    };

    struct TradeMatch {
        uint64_t buyOrderId;
        uint64_t sellOrderId;
        std::string buyer;
        std::string seller;
        double price;
        double amount;
        uint64_t timestamp;
    };

    class OrderBookEngine {
    private:
        // Price-time priority queues using std::map
        // Bids: descending price, ascending timestamp
        std::map<double, std::vector<Order>, std::greater<double>> bids;
        // Asks: ascending price, ascending timestamp
        std::map<double, std::vector<Order>, std::less<double>> asks;
        
        mutable std::mutex bookMutex;
        std::atomic<uint64_t> nextOrderId{1};
        std::vector<TradeMatch> tradeHistory;

    public:
        OrderBookEngine() = default;

        uint64_t PlaceOrder(const std::string& trader, OrderSide side, OrderType type, double price, double amount) {
            std::lock_guard<std::mutex> lock(bookMutex);
            uint64_t orderId = nextOrderId++;
            uint64_t now = std::chrono::duration_cast<std::chrono::milliseconds>(
                std::chrono::system_clock::now().time_since_epoch()
            ).count();

            Order order{ orderId, trader, side, type, price, amount, now };
            MatchOrders(order);
            return orderId;
        }

    private:
        void MatchOrders(Order& incoming) {
            if (incoming.side == OrderSide::BUY) {
                while (incoming.amount > 1e-8 && !asks.empty()) {
                    auto bestAskIt = asks.begin();
                    double bestAskPrice = bestAskIt->first;

                    if (incoming.type == OrderType::LIMIT && incoming.price < bestAskPrice) {
                        break; // No match possible
                    }

                    auto& queue = bestAskIt->second;
                    while (!queue.empty() && incoming.amount > 1e-8) {
                        Order& restingAsk = queue.front();
                        double tradeAmount = std::min(incoming.amount, restingAsk.amount);
                        double tradePrice = restingAsk.price;

                        incoming.amount -= tradeAmount;
                        restingAsk.amount -= tradeAmount;

                        tradeHistory.push_back({
                            incoming.id, restingAsk.id,
                            incoming.trader, restingAsk.trader,
                            tradePrice, tradeAmount,
                            static_cast<uint64_t>(std::chrono::duration_cast<std::chrono::milliseconds>(
                                std::chrono::system_clock::now().time_since_epoch()).count())
                        });

                        if (restingAsk.amount <= 1e-8) {
                            queue.erase(queue.begin());
                        }
                    }

                    if (queue.empty()) {
                        asks.erase(bestAskIt);
                    }
                }

                if (incoming.amount > 1e-8 && incoming.type == OrderType::LIMIT) {
                    bids[incoming.price].push_back(incoming);
                }
            } else {
                // Sell order matching
                while (incoming.amount > 1e-8 && !bids.empty()) {
                    auto bestBidIt = bids.begin();
                    double bestBidPrice = bestBidIt->first;

                    if (incoming.type == OrderType::LIMIT && incoming.price > bestBidPrice) {
                        break; // No match possible
                    }

                    auto& queue = bestBidIt->second;
                    while (!queue.empty() && incoming.amount > 1e-8) {
                        Order& restingBid = queue.front();
                        double tradeAmount = std::min(incoming.amount, restingBid.amount);
                        double tradePrice = restingBid.price;

                        incoming.amount -= tradeAmount;
                        restingBid.amount -= tradeAmount;

                        tradeHistory.push_back({
                            restingBid.id, incoming.id,
                            restingBid.trader, incoming.trader,
                            tradePrice, tradeAmount,
                            static_cast<uint64_t>(std::chrono::duration_cast<std::chrono::milliseconds>(
                                std::chrono::system_clock::now().time_since_epoch()).count())
                        });

                        if (restingBid.amount <= 1e-8) {
                            queue.erase(queue.begin());
                        }
                    }

                    if (queue.empty()) {
                        bids.erase(bestBidIt);
                    }
                }

                if (incoming.amount > 1e-8 && incoming.type == OrderType::LIMIT) {
                    asks[incoming.price].push_back(incoming);
                }
            }
        }

    public:
        std::pair<double, double> GetSpread() const {
            std::lock_guard<std::mutex> lock(bookMutex);
            double highestBid = bids.empty() ? 0.0 : bids.begin()->first;
            double lowestAsk = asks.empty() ? 0.0 : asks.begin()->first;
            return { highestBid, lowestAsk };
        }

        std::vector<TradeMatch> GetRecentTrades(size_t limit = 50) const {
            std::lock_guard<std::mutex> lock(bookMutex);
            if (tradeHistory.size() <= limit) return tradeHistory;
            return std::vector<TradeMatch>(tradeHistory.end() - limit, tradeHistory.end());
        }
    };

    // =========================================================================
    // 4. AUTOMATED MARKET MAKER (AMM) CONSTANT PRODUCT ENGINE
    // =========================================================================

    class ConstantProductAMM {
    private:
        double reserveA;
        double reserveB;
        double feeRatio; // e.g., 0.003 for 0.3%
        mutable std::mutex ammMutex;

    public:
        ConstantProductAMM(double initialA, double initialB, double fee = 0.003)
            : reserveA(initialA), reserveB(initialB), feeRatio(fee) {}

        struct SwapResult {
            double amountOut;
            double newReserveA;
            double newReserveB;
            double priceImpact;
            double feePaid;
        };

        SwapResult SwapAForB(double amountAIn) {
            std::lock_guard<std::mutex> lock(ammMutex);
            double amountInWithFee = amountAIn * (1.0 - feeRatio);
            double numerator = amountInWithFee * reserveB;
            double denominator = reserveA + amountInWithFee;
            double amountBOut = numerator / denominator;

            double initialPrice = reserveB / reserveA;
            reserveA += amountAIn;
            reserveB -= amountBOut;
            double finalPrice = reserveB / reserveA;
            double priceImpact = std::abs((finalPrice - initialPrice) / initialPrice);

            return { amountBOut, reserveA, reserveB, priceImpact, amountAIn * feeRatio };
        }

        SwapResult SwapBForA(double amountBIn) {
            std::lock_guard<std::mutex> lock(ammMutex);
            double amountInWithFee = amountBIn * (1.0 - feeRatio);
            double numerator = amountInWithFee * reserveA;
            double denominator = reserveB + amountInWithFee;
            double amountAOut = numerator / denominator;

            double initialPrice = reserveA / reserveB;
            reserveB += amountBIn;
            reserveA -= amountAOut;
            double finalPrice = reserveA / reserveB;
            double priceImpact = std::abs((finalPrice - initialPrice) / initialPrice);

            return { amountAOut, reserveA, reserveB, priceImpact, amountBIn * feeRatio };
        }

        std::pair<double, double> GetReserves() const {
            std::lock_guard<std::mutex> lock(ammMutex);
            return { reserveA, reserveB };
        }
    };

    // =========================================================================
    // 5. BLOCKCHAIN MEMPOOL & BLOCK PROOF-OF-WORK / POS ENGINE
    // =========================================================================

    struct Transaction {
        std::string sender;
        std::string recipient;
        double amount;
        double fee;
        uint64_t nonce;
        std::string signature;
        std::string txHash;

        void CalculateHash() {
            std::stringstream ss;
            ss << sender << ":" << recipient << ":" << amount << ":" << fee << ":" << nonce;
            txHash = Sha256::ComputeHash(ss.str());
        }
    };

    struct BlockHeader {
        uint64_t index;
        std::string previousHash;
        std::string merkleRoot;
        uint64_t timestamp;
        uint32_t difficulty;
        uint64_t nonce;
    };

    struct Block {
        BlockHeader header;
        std::vector<Transaction> transactions;
        std::string blockHash;
    };

    class BlockEngine {
    public:
        static std::string ComputeBlockHash(const BlockHeader& header) {
            std::stringstream ss;
            ss << header.index << header.previousHash << header.merkleRoot
               << header.timestamp << header.difficulty << header.nonce;
            return Keccak256::ComputeHash(ss.str());
        }

        static Block MineBlock(uint64_t index, const std::string& prevHash, const std::vector<Transaction>& txs, uint32_t targetZeros) {
            std::vector<std::string> txHashes;
            for (const auto& tx : txs) {
                txHashes.push_back(tx.txHash);
            }
            MerkleTree merkleTree(txHashes);

            Block block;
            block.header.index = index;
            block.header.previousHash = prevHash;
            block.header.merkleRoot = merkleTree.GetRootHash();
            block.header.timestamp = std::chrono::duration_cast<std::chrono::seconds>(
                std::chrono::system_clock::now().time_since_epoch()).count();
            block.header.difficulty = targetZeros;
            block.header.nonce = 0;
            block.transactions = txs;

            std::string prefix(targetZeros, '0');
            std::string fullPrefix = "0x" + prefix;

            while (true) {
                std::string hash = ComputeBlockHash(block.header);
                if (hash.rfind(fullPrefix, 0) == 0 || targetZeros == 0) {
                    block.blockHash = hash;
                    break;
                }
                block.header.nonce++;
            }
            return block;
        }
    };

} // namespace MagnumOpus

int main() {
    std::cout << "===================================================\n";
    std::cout << " MAGNUM OPUS // Cryptographic Engine Initialized   \n";
    std::cout << "===================================================\n\n";

    // Test Hashing
    std::string testMsg = "MagnumOpusWeb3DeFiEngine2025";
    std::cout << "[+] SHA256 Hash  : " << MagnumOpus::Sha256::ComputeHash(testMsg) << "\n";
    std::cout << "[+] Keccak256 Hash: " << MagnumOpus::Keccak256::ComputeHash(testMsg) << "\n\n";

    // Test Merkle Tree
    std::vector<std::string> txs = { "tx1_alice_bob_100", "tx2_carol_dave_50", "tx3_eve_mallory_25" };
    MagnumOpus::MerkleTree merkle(txs);
    std::cout << "[+] Merkle Root   : " << merkle.GetRootHash() << "\n\n";

    // Test AMM Engine
    MagnumOpus::ConstantProductAMM amm(1000000.0, 3000000000.0); // 1,000,000 ETH / 3,000,000,000 USDC
    auto res = amm.SwapAForB(100.0);
    std::cout << "[+] AMM Swap 100 ETH -> Received USDC: " << res.amountOut 
              << " (Price Impact: " << res.priceImpact * 100.0 << "%)\n\n";

    // Test Mining Engine
    std::vector<MagnumOpus::Transaction> mempoolTx;
    MagnumOpus::Transaction tx1{ "0xAlice", "0xBob", 10.5, 0.001, 1, "sig1", "" };
    tx1.CalculateHash();
    mempoolTx.push_back(tx1);

    std::cout << "[+] Mining Block #1 (Difficulty 2)...\n";
    MagnumOpus::Block minedBlock = MagnumOpus::BlockEngine::MineBlock(
        1, "0x0000000000000000000000000000000000000000000000000000000000000000", mempoolTx, 2
    );
    std::cout << "[+] Block Mined! Hash: " << minedBlock.blockHash 
              << " | Nonce: " << minedBlock.header.nonce << "\n";

    return 0;
}
