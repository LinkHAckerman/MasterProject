/**
 * MAGNUM OPUS // Web3 & DeFi Nexus Engine - Core Client Application
 * High-Performance Client-Side Architecture for Decentralized Finance,
 * Merkle Proof Computation, AMM DEX Simulation, Governance & NFT Matrix.
 */

(function () {
    'use strict';

    // --- Global Application State ---
    const State = {
        wallet: {
            connected: false,
            address: null,
            network: 'Ethereum Mainnet',
            chainId: 1,
            balanceEth: 14.8520,
            balanceMopus: 4500.00,
            balanceUsdc: 18500.25,
            nonce: 42,
            activeTxCount: 0
        },
        tokens: [
            { symbol: 'ETH', name: 'Ethereum', price: 3420.50, change24h: 3.45, reserve: 15000, color: '#38bdf8' },
            { symbol: 'MOPUS', name: 'Magnum Opus Token', price: 12.80, change24h: 18.90, reserve: 500000, color: '#a855f7' },
            { symbol: 'USDC', name: 'USD Coin', price: 1.00, change24h: 0.01, reserve: 25000000, color: '#10b981' },
            { symbol: 'SOL', name: 'Solana', price: 178.40, change24h: -1.25, reserve: 45000, color: '#f59e0b' },
            { symbol: 'WBTC', name: 'Wrapped Bitcoin', price: 68450.00, change24h: 2.10, reserve: 850, color: '#f43f5e' }
        ],
        staking: {
            totalStaked: 1420500.00,
            userStaked: 350.00,
            rewardRatePerSec: 0.0045,
            accumulatedRewards: 12.842,
            apr: 48.6
        },
        gas: {
            slow: 14,
            standard: 18,
            fast: 24,
            instant: 32,
            current: 18,
            trend: 'stable'
        },
        mempool: [],
        blocks: [],
        activeTab: 'swap',
        governance: {
            proposals: [
                {
                    id: 'MIP-42',
                    title: 'Implement Multi-Chain ZK-Rollup Settlement Layer via Rust Anchor Contract',
                    status: 'Active',
                    forVotes: 894000,
                    againstVotes: 42000,
                    quorum: 1000000,
                    endsIn: '2d 14h',
                    userVoted: null
                },
                {
                    id: 'MIP-43',
                    title: 'Adjust Synthetix Reward Emission Curves to 0.05 MOPUS/block',
                    status: 'Active',
                    forVotes: 1240500,
                    againstVotes: 310000,
                    quorum: 1000000,
                    endsIn: '5d 08h',
                    userVoted: null
                },
                {
                    id: 'MIP-41',
                    title: 'Expand Collateral Basket to Include Liquid Staked SOL (LST)',
                    status: 'Passed',
                    forVotes: 2150000,
                    againstVotes: 88000,
                    quorum: 1000000,
                    endsIn: 'Executed',
                    userVoted: 'for'
                }
            ]
        },
        nfts: [
            { id: 1042, name: 'Cybernetic Aegis #1042', rarity: 'Legendary', power: '98.5 TH/s', floor: '4.50 ETH', imageRgb: [56, 189, 248] },
            { id: 2088, name: 'Quantum Core #2088', rarity: 'Mythic', power: '142.0 TH/s', floor: '8.20 ETH', imageRgb: [168, 85, 247] },
            { id: 3104, name: 'Neural Shard #3104', rarity: 'Rare', power: '54.2 TH/s', floor: '1.85 ETH', imageRgb: [16, 185, 129] },
            { id: 4096, name: 'Singularity Drift #4096', rarity: 'Celestial', power: '310.0 TH/s', floor: '15.00 ETH', imageRgb: [244, 63, 94] }
        ]
    };

    // --- Fast SHA-256 Client-Side Implementation (Pure JS) ---
    const Cryptography = {
        async sha256(message) {
            if (window.crypto && window.crypto.subtle) {
                const msgUint8 = new TextEncoder().encode(message);
                const hashBuffer = await window.crypto.subtle.digest('SHA-256', msgUint8);
                const hashArray = Array.from(new Uint8Array(hashBuffer));
                return '0x' + hashArray.map(b => b.toString(16).padStart(2, '0')).join('');
            } else {
                // Fallback deterministic pseudo-hash for testing without subtle crypto
                let hash = 0x811c9dc5;
                for (let i = 0; i < message.length; i++) {
                    hash ^= message.charCodeAt(i);
                    hash = Math.imul(hash, 0x01000193);
                }
                return '0x' + (hash >>> 0).toString(16).padStart(64, '0');
            }
        },

        generateAddress() {
            const hex = Array.from({ length: 40 }, () => Math.floor(Math.random() * 16).toString(16)).join('');
            return '0x' + hex;
        },

        generateTxHash() {
            const hex = Array.from({ length: 64 }, () => Math.floor(Math.random() * 16).toString(16)).join('');
            return '0x' + hex;
        }
    };

    // --- Merkle Tree Generator & Proof Engine ---
    class MerkleTree {
        constructor(leaves) {
            this.leaves = leaves;
            this.layers = [];
        }

        async buildTree() {
            let currentLayer = await Promise.all(this.leaves.map(l => Cryptography.sha256(l)));
            this.layers = [currentLayer];
            while (currentLayer.length > 1) {
                const nextLayer = [];
                for (let i = 0; i < currentLayer.length; i += 2) {
                    const left = currentLayer[i];
                    const right = (i + 1 < currentLayer.length) ? currentLayer[i + 1] : left;
                    const combinedHash = await Cryptography.sha256(left + right);
                    nextLayer.push(combinedHash);
                }
                this.layers.push(nextLayer);
                currentLayer = nextLayer;
            }
            return this.layers[this.layers.length - 1][0];
        }

        async getProof(index) {
            const proof = [];
            let currentIndex = index;
            for (let i = 0; i < this.layers.length - 1; i++) {
                const layer = this.layers[i];
                const isRightChild = currentIndex % 2 === 1;
                const pairIndex = isRightChild ? currentIndex - 1 : currentIndex + 1;
                if (pairIndex < layer.length) {
                    proof.push({
                        position: isRightChild ? 'left' : 'right',
                        data: layer[pairIndex]
                    });
                } else {
                    proof.push({
                        position: 'right',
                        data: layer[currentIndex]
                    });
                }
                currentIndex = Math.floor(currentIndex / 2);
            }
            return proof;
        }
    }

    // --- AMM Constant Product DEX Engine (x * y = k) ---
    const AMMEngine = {
        getAmountOut(amountIn, reserveIn, reserveOut, feeBps = 30) {
            const amountInWithFee = amountIn * (10000 - feeBps);
            const numerator = amountInWithFee * reserveOut;
            const denominator = (reserveIn * 10000) + amountInWithFee;
            return numerator / denominator;
        },

        calculatePriceImpact(amountIn, reserveIn) {
            return (amountIn / (reserveIn + amountIn)) * 100;
        },

        calculateSlippage(expectedOut, actualOut) {
            return Math.max(0, ((expectedOut - actualOut) / expectedOut) * 100);
        }
    };

    // --- UI Controller & DOM Orchestration ---
    const UI = {
        elements: {},

        init() {
            this.cacheDom();
            this.bindEvents();
            this.startLiveSimulation();
            this.renderTokens();
            this.renderGovernance();
            this.renderNfts();
            this.initMarketChart();
            this.initMerkleTool();
            this.logActivity('Magnum Opus Nexus Engine v4.0.0 initialized successfully.', 'sys');
        },

        cacheDom() {
            this.elements.connectBtn = document.getElementById('btn-connect-wallet') || document.querySelector('[data-action="connect-wallet"]');
            this.elements.walletAddr = document.getElementById('wallet-display-addr');
            this.elements.walletEth = document.getElementById('wallet-balance-eth');
            this.elements.walletMopus = document.getElementById('wallet-balance-mopus');
            this.elements.gasDisplay = document.getElementById('gas-tracker-val');
            this.elements.tokenList = document.getElementById('token-market-table-body');
            this.elements.swapFromInput = document.getElementById('swap-from-amount');
            this.elements.swapToInput = document.getElementById('swap-to-amount');
            this.elements.swapFromSelect = document.getElementById('swap-from-token');
            this.elements.swapToSelect = document.getElementById('swap-to-token');
            this.elements.swapBtn = document.getElementById('btn-execute-swap');
            this.elements.priceImpactDisplay = document.getElementById('swap-price-impact');
            this.elements.stakingUserBalance = document.getElementById('stake-user-amount');
            this.elements.stakingEarned = document.getElementById('stake-earned-reward');
            this.elements.btnClaimRewards = document.getElementById('btn-claim-rewards');
            this.elements.btnStakeAction = document.getElementById('btn-stake-action');
            this.elements.inputStakeAmount = document.getElementById('input-stake-amount');
            this.elements.mempoolFeed = document.getElementById('mempool-live-feed');
            this.elements.govProposals = document.getElementById('governance-proposals-container');
            this.elements.nftGrid = document.getElementById('nft-matrix-grid');
            this.elements.logOutput = document.getElementById('nexus-console-logs');
            this.elements.merkleInput = document.getElementById('merkle-leaves-input');
            this.elements.merkleBuildBtn = document.getElementById('btn-build-merkle');
            this.elements.merkleTreeVisual = document.getElementById('merkle-tree-visualizer');
            this.elements.marketChartCanvas = document.getElementById('market-trend-chart');
        },

        bindEvents() {
            if (this.elements.connectBtn) {
                this.elements.connectBtn.addEventListener('click', () => this.toggleWalletConnection());
            }

            if (this.elements.swapFromInput && this.elements.swapFromSelect && this.elements.swapToSelect) {
                const updateSwapRate = () => this.computeSwapEstimate();
                this.elements.swapFromInput.addEventListener('input', updateSwapRate);
                this.elements.swapFromSelect.addEventListener('change', updateSwapRate);
                this.elements.swapToSelect.addEventListener('change', updateSwapRate);
            }

            if (this.elements.swapBtn) {
                this.elements.swapBtn.addEventListener('click', () => this.executeSwap());
            }

            if (this.elements.btnClaimRewards) {
                this.elements.btnClaimRewards.addEventListener('click', () => this.claimStakingRewards());
            }

            if (this.elements.btnStakeAction) {
                this.elements.btnStakeAction.addEventListener('click', () => this.executeStaking());
            }

            if (this.elements.merkleBuildBtn) {
                this.elements.merkleBuildBtn.addEventListener('click', () => this.generateMerkleVisualization());
            }

            // Tab navigation listeners
            document.querySelectorAll('[data-nexus-tab]').forEach(tabBtn => {
                tabBtn.addEventListener('click', (e) => {
                    const target = e.currentTarget.getAttribute('data-nexus-tab');
                    this.switchTab(target);
                });
            });
        },

        switchTab(tabName) {
            State.activeTab = tabName;
            document.querySelectorAll('[data-nexus-tab]').forEach(btn => {
                if (btn.getAttribute('data-nexus-tab') === tabName) {
                    btn.classList.add('active', 'border-accent-cyan', 'text-accent-cyan');
                } else {
                    btn.classList.remove('active', 'border-accent-cyan', 'text-accent-cyan');
                }
            });
            document.querySelectorAll('[data-tab-content]').forEach(section => {
                if (section.getAttribute('data-tab-content') === tabName) {
                    section.style.display = 'block';
                } else {
                    section.style.display = 'none';
                }
            });
        },

        toggleWalletConnection() {
            if (!State.wallet.connected) {
                State.wallet.connected = true;
                State.wallet.address = Cryptography.generateAddress();
                this.logActivity(`Wallet Connected: ${State.wallet.address} [${State.wallet.network}]`, 'success');
                if (this.elements.connectBtn) {
                    this.elements.connectBtn.innerText = `${State.wallet.address.substring(0, 6)}...${State.wallet.address.substring(38)}`;
                    this.elements.connectBtn.classList.add('connected-glow');
                }
            } else {
                State.wallet.connected = false;
                State.wallet.address = null;
                this.logActivity('Wallet disconnected by user.', 'warn');
                if (this.elements.connectBtn) {
                    this.elements.connectBtn.innerText = 'Connect Web3 Wallet';
                    this.elements.connectBtn.classList.remove('connected-glow');
                }
            }
            this.updateWalletUI();
        },

        updateWalletUI() {
            if (this.elements.walletAddr) {
                this.elements.walletAddr.innerText = State.wallet.connected ? State.wallet.address : 'Not Connected';
            }
            if (this.elements.walletEth) {
                this.elements.walletEth.innerText = `${State.wallet.balanceEth.toFixed(4)} ETH`;
            }
            if (this.elements.walletMopus) {
                this.elements.walletMopus.innerText = `${State.wallet.balanceMopus.toFixed(2)} MOPUS`;
            }
            if (this.elements.stakingUserBalance) {
                this.elements.stakingUserBalance.innerText = `${State.staking.userStaked.toFixed(2)} MOPUS`;
            }
        },

        computeSwapEstimate() {
            if (!this.elements.swapFromInput || !this.elements.swapToInput) return;
            const amountIn = parseFloat(this.elements.swapFromInput.value) || 0;
            const symIn = this.elements.swapFromSelect.value;
            const symOut = this.elements.swapToSelect.value;

            if (symIn === symOut || amountIn <= 0) {
                this.elements.swapToInput.value = amountIn > 0 ? amountIn.toFixed(4) : '';
                if (this.elements.priceImpactDisplay) this.elements.priceImpactDisplay.innerText = '0.00%';
                return;
            }

            const tIn = State.tokens.find(t => t.symbol === symIn) || State.tokens[0];
            const tOut = State.tokens.find(t => t.symbol === symOut) || State.tokens[1];

            const inValueUSD = amountIn * tIn.price;
            const estimatedOut = inValueUSD / tOut.price;
            const impact = AMMEngine.calculatePriceImpact(amountIn, tIn.reserve);

            this.elements.swapToInput.value = (estimatedOut * 0.997).toFixed(5); // 0.3% fee
            if (this.elements.priceImpactDisplay) {
                this.elements.priceImpactDisplay.innerText = `${impact.toFixed(2)}%`;
                this.elements.priceImpactDisplay.style.color = impact > 2.0 ? 'var(--accent-rose, #f43f5e)' : 'var(--accent-emerald, #10b981)';
            }
        },

        executeSwap() {
            if (!State.wallet.connected) {
                this.logActivity('Execution rejected: Web3 wallet not connected.', 'error');
                alert('Please connect your Web3 wallet first.');
                return;
            }
            const amountIn = parseFloat(this.elements.swapFromInput.value);
            const symIn = this.elements.swapFromSelect.value;
            const symOut = this.elements.swapToSelect.value;
            const amountOut = parseFloat(this.elements.swapToInput.value);

            if (!amountIn || amountIn <= 0) {
                this.logActivity('Swap execution error: Invalid input amount.', 'warn');
                return;
            }

            // Deduct / Add balance demo
            if (symIn === 'ETH' && State.wallet.balanceEth < amountIn) {
                this.logActivity('Transaction failed: Insufficient ETH for swap + gas.', 'error');
                return;
            }

            if (symIn === 'ETH') State.wallet.balanceEth -= amountIn;
            if (symIn === 'MOPUS') State.wallet.balanceMopus -= amountIn;
            if (symOut === 'ETH') State.wallet.balanceEth += amountOut;
            if (symOut === 'MOPUS') State.wallet.balanceMopus += amountOut;

            const txHash = Cryptography.generateTxHash();
            this.pushMempoolItem({
                hash: txHash,
                type: `Swap ${symIn} -> ${symOut}`,
                amount: `${amountIn} ${symIn}`,
                status: 'Confirmed',
                time: 'Just now'
            });

            this.logActivity(`DEX Swap: Exchanged ${amountIn} ${symIn} for ${amountOut.toFixed(4)} ${symOut} | Hash: ${txHash.substring(0, 14)}...`, 'success');
            this.updateWalletUI();
            this.elements.swapFromInput.value = '';
            this.elements.swapToInput.value = '';
        },

        executeStaking() {
            if (!State.wallet.connected) {
                alert('Please connect your Web3 wallet first.');
                return;
            }
            const stakeAmt = parseFloat(this.elements.inputStakeAmount?.value || 0);
            if (stakeAmt <= 0 || stakeAmt > State.wallet.balanceMopus) {
                this.logActivity('Staking rejected: Invalid amount or insufficient MOPUS balance.', 'warn');
                return;
            }
            State.wallet.balanceMopus -= stakeAmt;
            State.staking.userStaked += stakeAmt;
            State.staking.totalStaked += stakeAmt;
            this.logActivity(`Successfully staked ${stakeAmt} MOPUS at ${State.staking.apr}% APR into Synthetix Pool.`, 'success');
            if (this.elements.inputStakeAmount) this.elements.inputStakeAmount.value = '';
            this.updateWalletUI();
        },

        claimStakingRewards() {
            if (State.staking.accumulatedRewards <= 0) {
                this.logActivity('No accumulated staking rewards to harvest.', 'warn');
                return;
            }
            const claimed = State.staking.accumulatedRewards;
            State.wallet.balanceMopus += claimed;
            State.staking.accumulatedRewards = 0;
            this.logActivity(`Harvested +${claimed.toFixed(4)} MOPUS reward tokens to wallet.`, 'success');
            this.updateWalletUI();
        },

        renderTokens() {
            if (!this.elements.tokenList) return;
            this.elements.tokenList.innerHTML = State.tokens.map(t => `
                <tr style="border-bottom: 1px solid rgba(255, 255, 255, 0.05); transition: background 0.2s;">
                    <td style="padding: 0.85rem 1rem; display: flex; align-items: center; gap: 0.5rem;">
                        <span style="width: 10px; height: 10px; border-radius: 50%; background: ${t.color}; display: inline-block;"></span>
                        <strong>${t.symbol}</strong> <span style="color: var(--text-muted); font-size: 0.85rem;">${t.name}</span>
                    </td>
                    <td style="padding: 0.85rem 1rem; text-align: right; font-family: var(--font-mono);">$${t.price.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}</td>
                    <td style="padding: 0.85rem 1rem; text-align: right; font-family: var(--font-mono); color: ${t.change24h >= 0 ? '#10b981' : '#f43f5e'};">
                        ${t.change24h >= 0 ? '+' : ''}${t.change24h.toFixed(2)}%
                    </td>
                    <td style="padding: 0.85rem 1rem; text-align: right; font-family: var(--font-mono); color: var(--text-muted);">
                        ${t.reserve.toLocaleString()} ${t.symbol}
                    </td>
                </tr>
            `).join('');
        },

        renderGovernance() {
            if (!this.elements.govProposals) return;
            this.elements.govProposals.innerHTML = State.governance.proposals.map(p => {
                const totalVotes = p.forVotes + p.againstVotes;
                const forPct = totalVotes > 0 ? ((p.forVotes / totalVotes) * 100).toFixed(1) : 0;
                const againstPct = totalVotes > 0 ? ((p.againstVotes / totalVotes) * 100).toFixed(1) : 0;
                return `
                    <div style="background: var(--bg-card); border: 1px solid var(--border-color); border-radius: 12px; padding: 1.25rem; margin-bottom: 1rem;">
                        <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 0.75rem;">
                            <span style="font-family: var(--font-mono); font-size: 0.8rem; background: rgba(56,189,248,0.15); color: #38bdf8; padding: 0.2rem 0.5rem; border-radius: 4px;">${p.id}</span>
                            <span style="font-size: 0.85rem; color: ${p.status === 'Active' ? '#10b981' : '#a855f7'};">● ${p.status} (${p.endsIn})</span>
                        </div>
                        <h4 style="font-size: 1.05rem; margin-bottom: 0.75rem; color: #fff;">${p.title}</h4>
                        <div style="margin-bottom: 0.75rem;">
                            <div style="display: flex; justify-content: space-between; font-size: 0.8rem; margin-bottom: 0.25rem; color: var(--text-muted); font-family: var(--font-mono);">
                                <span>For: ${p.forVotes.toLocaleString()} (${forPct}%)</span>
                                <span>Against: ${p.againstVotes.toLocaleString()} (${againstPct}%)</span>
                            </div>
                            <div style="width: 100%; height: 6px; background: rgba(255,255,255,0.1); border-radius: 3px; overflow: hidden; display: flex;">
                                <div style="width: ${forPct}%; background: #10b981;"></div>
                                <div style="width: ${againstPct}%; background: #f43f5e;"></div>
                            </div>
                        </div>
                        ${p.status === 'Active' ? `
                        <div style="display: flex; gap: 0.5rem;">
                            <button onclick="window.MagnumNexus.voteProposal('${p.id}', 'for')" style="flex: 1; padding: 0.45rem; background: rgba(16, 185, 129, 0.15); border: 1px solid #10b981; color: #10b981; border-radius: 6px; cursor: pointer; font-weight: bold;">Vote FOR</button>
                            <button onclick="window.MagnumNexus.voteProposal('${p.id}', 'against')" style="flex: 1; padding: 0.45rem; background: rgba(244, 63, 94, 0.15); border: 1px solid #f43f5e; color: #f43f5e; border-radius: 6px; cursor: pointer; font-weight: bold;">Vote AGAINST</button>
                        </div>` : ''}
                    </div>
                `;
            }).join('');
        },

        renderNfts() {
            if (!this.elements.nftGrid) return;
            this.elements.nftGrid.innerHTML = State.nfts.map(nft => `
                <div style="background: var(--bg-card); border: 1px solid var(--border-color); border-radius: 12px; overflow: hidden; transition: transform 0.2s;">
                    <div style="height: 140px; background: linear-gradient(135deg, rgb(${nft.imageRgb.join(',')}), #030611); display: flex; align-items: center; justify-content: center;">
                        <svg width="60" height="60" viewBox="0 0 24 24" fill="none" stroke="#ffffff" stroke-width="1.5">
                            <polygon points="12 2 2 7 12 12 22 7 12 2"></polygon>
                            <polyline points="2 17 12 22 22 17"></polyline>
                            <polyline points="2 12 12 17 22 12"></polyline>
                        </svg>
                    </div>
                    <div style="padding: 1rem;">
                        <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 0.5rem;">
                            <h5 style="font-size: 0.95rem; font-weight: 700;">${nft.name}</h5>
                            <span style="font-size: 0.75rem; color: #a855f7; font-family: var(--font-mono);">${nft.rarity}</span>
                        </div>
                        <div style="display: flex; justify-content: space-between; font-size: 0.85rem; color: var(--text-muted); font-family: var(--font-mono); margin-bottom: 0.75rem;">
                            <span>Power: ${nft.power}</span>
                            <span>Floor: ${nft.floor}</span>
                        </div>
                        <button onclick="window.MagnumNexus.mintNft(${nft.id})" style="width: 100%; padding: 0.5rem; background: linear-gradient(135deg, #38bdf8, #a855f7); border: none; border-radius: 6px; color: #fff; font-weight: bold; cursor: pointer;">Stake in Vault</button>
                    </div>
                </div>
            `).join('');
        },

        pushMempoolItem(tx) {
            State.mempool.unshift(tx);
            if (State.mempool.length > 8) State.mempool.pop();
            if (this.elements.mempoolFeed) {
                this.elements.mempoolFeed.innerHTML = State.mempool.map(item => `
                    <div style="display: flex; justify-content: space-between; align-items: center; padding: 0.6rem 0.8rem; border-bottom: 1px solid rgba(255,255,255,0.05); font-family: var(--font-mono); font-size: 0.8rem;">
                        <div>
                            <span style="color: #38bdf8;">${item.hash.substring(0, 10)}...</span>
                            <span style="margin-left: 0.5rem; color: var(--text-muted);">${item.type}</span>
                        </div>
                        <div>
                            <span style="color: #10b981; font-weight: bold;">${item.amount}</span>
                            <span style="margin-left: 0.5rem; font-size: 0.7rem; color: #94a3b8;">${item.time}</span>
                        </div>
                    </div>
                `).join('');
            }
        },

        logActivity(msg, type = 'info') {
            const time = new Date().toLocaleTimeString();
            let color = '#94a3b8';
            if (type === 'success') color = '#10b981';
            if (type === 'warn') color = '#f59e0b';
            if (type === 'error') color = '#f43f5e';
            if (type === 'sys') color = '#38bdf8';

            const logLine = `<div style="margin-bottom: 4px; font-family: var(--font-mono); font-size: 0.78rem; color: ${color};">[${time}] ${msg}</div>`;
            if (this.elements.logOutput) {
                this.elements.logOutput.insertAdjacentHTML('afterbegin', logLine);
            }
        },

        async initMerkleTool() {
            if (!this.elements.merkleInput) return;
            this.elements.merkleInput.value = "Tx1: 0x4f...a1\nTx2: 0x8b...3c\nTx3: 0xd2...9e\nTx4: 0x11...70";
            await this.generateMerkleVisualization();
        },

        async generateMerkleVisualization() {
            if (!this.elements.merkleInput || !this.elements.merkleTreeVisual) return;
            const raw = this.elements.merkleInput.value.split('\n').map(s => s.trim()).filter(Boolean);
            if (raw.length === 0) return;

            const tree = new MerkleTree(raw);
            const root = await tree.buildTree();

            let html = `<div style="padding: 1rem; font-family: var(--font-mono); font-size: 0.8rem;">`;
            html += `<div style="color: #10b981; font-weight: bold; margin-bottom: 0.75rem;">Merkle Root: ${root}</div>`;
            html += `<div style="color: var(--text-muted); margin-bottom: 0.5rem;">Layers (${tree.layers.length}):</div>`;
            
            tree.layers.forEach((layer, idx) => {
                html += `<div style="margin-bottom: 0.5rem; padding-left: ${idx * 12}px;"><span style="color: #a855f7;">Layer ${idx}:</span> [${layer.map(h => h.substring(0, 10) + '...').join(' | ')}]</div>`;
            });
            html += `</div>`;
            this.elements.merkleTreeVisual.innerHTML = html;
        },

        initMarketChart() {
            if (!this.elements.marketChartCanvas) return;
            const ctx = this.elements.marketChartCanvas.getContext('2d');
            if (!ctx) return;

            let points = [3200, 3240, 3220, 3290, 3350, 3310, 3380, 3420.50];
            
            const draw = () => {
                const w = this.elements.marketChartCanvas.width = this.elements.marketChartCanvas.offsetWidth || 500;
                const h = this.elements.marketChartCanvas.height = 160;
                ctx.clearRect(0, 0, w, h);

                const min = Math.min(...points) * 0.98;
                const max = Math.max(...points) * 1.02;
                const step = w / (points.length - 1);

                const gradient = ctx.createLinearGradient(0, 0, 0, h);
                gradient.addColorStop(0, 'rgba(56, 189, 248, 0.4)');
                gradient.addColorStop(1, 'rgba(56, 189, 248, 0.0)');

                ctx.beginPath();
                points.forEach((p, i) => {
                    const x = i * step;
                    const y = h - ((p - min) / (max - min)) * (h - 20) - 10;
                    if (i === 0) ctx.moveTo(x, y);
                    else ctx.lineTo(x, y);
                });
                
                ctx.strokeStyle = '#38bdf8';
                ctx.lineWidth = 2.5;
                ctx.stroke();

                // Fill area
                ctx.lineTo(w, h);
                ctx.lineTo(0, h);
                ctx.closePath();
                ctx.fillStyle = gradient;
                ctx.fill();
            };

            draw();
            window.addEventListener('resize', draw);

            // Live tick simulation
            setInterval(() => {
                const last = points[points.length - 1];
                const delta = (Math.random() - 0.48) * 8;
                const next = Math.max(3000, last + delta);
                points.shift();
                points.push(next);
                State.tokens[0].price = next;
                draw();
            }, 2500);
        },

        startLiveSimulation() {
            // Yield farming rewards accumulator ticker
            setInterval(() => {
                if (State.staking.userStaked > 0) {
                    State.staking.accumulatedRewards += (State.staking.userStaked * (State.staking.rewardRatePerSec / 1000));
                    if (this.elements.stakingEarned) {
                        this.elements.stakingEarned.innerText = `${State.staking.accumulatedRewards.toFixed(4)} MOPUS`;
                    }
                }
            }, 1000);

            // Gas price & mempool simulator
            setInterval(() => {
                const gasVariance = Math.floor((Math.random() - 0.5) * 4);
                State.gas.current = Math.max(12, Math.min(65, State.gas.current + gasVariance));
                if (this.elements.gasDisplay) {
                    this.elements.gasDisplay.innerText = `${State.gas.current} Gwei`;
                }
            }, 3500);

            // Background mock transaction generator
            setInterval(() => {
                const token = State.tokens[Math.floor(Math.random() * State.tokens.length)];
                const amt = (Math.random() * 50 + 1).toFixed(2);
                this.pushMempoolItem({
                    hash: Cryptography.generateTxHash(),
                    type: Math.random() > 0.5 ? 'Limit Order' : 'Liquidity Add',
                    amount: `${amt} ${token.symbol}`,
                    status: 'Pending',
                    time: '1s ago'
                });
            }, 6000);
        }
    };

    // Expose global actions for inline handlers
    window.MagnumNexus = {
        voteProposal(proposalId, voteType) {
            if (!State.wallet.connected) {
                alert('Please connect your Web3 wallet to vote on governance proposals.');
                return;
            }
            const prop = State.governance.proposals.find(p => p.id === proposalId);
            if (prop) {
                if (voteType === 'for') prop.forVotes += 5000;
                else prop.againstVotes += 5000;
                prop.userVoted = voteType;
                UI.logActivity(`Voted ${voteType.toUpperCase()} on proposal ${proposalId} with 5,000 MOPUS weight.`, 'success');
                UI.renderGovernance();
            }
        },
        mintNft(nftId) {
            if (!State.wallet.connected) {
                alert('Please connect your Web3 wallet first.');
                return;
            }
            UI.logActivity(`Staked NFT Matrix Asset #${nftId} into Quantum Yield Vault. Hash: ${Cryptography.generateTxHash().substring(0, 16)}...`, 'success');
        }
    };

    // Initialize upon DOM readiness
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', () => UI.init());
    } else {
        UI.init();
    }
})();
