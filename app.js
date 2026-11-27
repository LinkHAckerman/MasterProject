(function () {
    'use strict';

    // Global State Management
    const state = {
        wallet: {
            connected: false,
            address: '0x71a48c9f2b1d3e4a5b6c7d8e9f0a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f89e',
            balanceEth: 14.852,
            balanceUsdt: 42500.00,
            balanceBtc: 0.65,
            balanceSol: 12.5,
            balanceOpus: 10000.0,
            chainId: '0x1',
            networkName: 'Ethereum Mainnet',
            tokens: [
                { symbol: 'ETH', name: 'Ethereum', balance: 14.852, decimals: 18, price: 3450.75, icon: 'ETH', change24h: 3.42 },
                { symbol: 'USDT', name: 'Tether USD', balance: 42500.00, decimals: 6, price: 1.00, icon: 'USDT', change24h: 0.01 },
                { symbol: 'BTC', name: 'Bitcoin', balance: 0.65, decimals: 8, price: 64200.00, icon: 'BTC', change24h: 1.85 },
                { symbol: 'SOL', name: 'Solana', balance: 12.5, decimals: 9, price: 145.20, icon: 'SOL', change24h: 6.12 },
                { symbol: 'OPUS', name: 'Magnum Opus Governance', balance: 10000.0, decimals: 18, price: 0.45, icon: 'OPUS', change24h: 12.40 }
            ]
        },
        gas: {
            slow: 12,
            standard: 18,
            fast: 24,
            current: 18,
            selectedTier: 'standard',
            unit: 'Gwei'
        },
        market: {
            selectedPair: 'ETH/USDT',
            price: 3450.75,
            change24h: 4.82,
            volume24h: 1284509000,
            high24h: 3520.00,
            low24h: 3310.50,
            timeframe: '24H',
            chartData: {
                labels: ['00:00', '04:00', '08:00', '12:00', '16:00', '20:00'],
                prices: [3310.50, 3350.00, 3400.25, 3380.00, 3420.50, 3450.75],
                volumes: [120000, 150000, 110000, 180000, 200000, 250000]
            }
        },
        orderBook: {
            bids: [
                { price: 3450.50, amount: 1.2 },
                { price: 3450.25, amount: 0.5 },
                { price: 3449.00, amount: 2.1 }
            ],
            asks: [
                { price: 3451.00, amount: 0.8 },
                { price: 3451.25, amount: 1.5 },
                { price: 3452.50, amount: 0.3 }
            ],
            maxDepth: 12,
            spread: 0.5
        },
        swap: {
            fromToken: 'ETH',
            toToken: 'USDT',
            fromAmount: '',
            toAmount: '',
            slippage: 0.5,
            priceImpact: 0.04,
            routing: 'Magnum Smart Routing v2 (Uniswap v3 + Curve)'
        },
        staking: {
            stakedOpus: 2500.0,
            rewardRateApy: 18.5,
            pendingRewards: 14.8241,
            totalClaimed: 124.50,
            lockPeriodDays: 30,
            lastClaimed: Date.now() - 432000000
        },
        nfts: [
            {
                id: 1,
                name: 'Cyber Opus #001',
                collection: 'Opus Genesis',
                price: '2.5 ETH',
                priceVal: 2.5,
                rarity: 'Legendary',
                rank: 4,
                image: 'https://via.placeholder.com/300/030611/00ffcc?text=Cyber+Opus+001',
                attributes: [
                    { trait: 'Background', value: 'Neon Nebula' },
                    { trait: 'Core', value: 'Quantum Heart' },
                    { trait: 'Aura', value: 'Chrono Pulse' }
                ]
            },
            {
                id: 2,
                name: 'Cyber Opus #042',
                collection: 'Opus Genesis',
                price: '1.2 ETH',
                priceVal: 1.2,
                rarity: 'Rare',
                rank: 142,
                image: 'https://via.placeholder.com/300/030611/00ffcc?text=Cyber+Opus+042',
                attributes: [
                    { trait: 'Background', value: 'Deep Cyber' },
                    { trait: 'Core', value: 'Plasma Engine' },
                    { trait: 'Aura', value: 'Overclock' }
                ]
            },
            {
                id: 3,
                name: 'Aether Shield #108',
                collection: 'Relics of DeFi',
                price: '0.85 ETH',
                priceVal: 0.85,
                rarity: 'Epic',
                rank: 45,
                image: 'https://via.placeholder.com/300/030611/00ffcc?text=Aether+Shield+108',
                attributes: [
                    { trait: 'Power', value: 'Yield Multiplier 2.5x' },
                    { trait: 'Element', value: 'Starlight' }
                ]
            },
            {
                id: 4,
                name: 'Vortex Sentinel #777',
                collection: 'Relics of DeFi',
                price: '3.1 ETH',
                priceVal: 3.1,
                rarity: 'Mythic',
                rank: 1,
                image: 'https://via.placeholder.com/300/030611/00ffcc?text=Vortex+Sentinel+777',
                attributes: [
                    { trait: 'Power', value: 'Zero Gas Transmutation' },
                    { trait: 'Element', value: 'Dark Matter' }
                ]
            }
        ],
        transactions: [
            {
                hash: '0x71a48c9f2b1d3e4a5b6c7d8e9f0a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f89e',
                displayHash: '0x71a...f89e',
                type: 'Swap',
                description: 'Swapped 1.5 ETH for 5,176.12 USDT',
                amount: '-1.5 ETH',
                status: 'Confirmed',
                timestamp: Date.now() - 3600000,
                blockNumber: 19842105
            },
            {
                hash: '0x32c81d7f6e5d4c3b2a1f0e9d8c7b6a5f4e3d2c1b0a9f8e7d6c5b4a3f2e1e11b',
                displayHash: '0x32c...e11b',
                type: 'Stake',
                description: 'Staked 2,500 OPUS in Yield Vault',
                amount: '2,500 OPUS',
                status: 'Confirmed',
                timestamp: Date.now() - 86400000,
                blockNumber: 19835012
            },
            {
                hash: '0x99f12a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e0f1a2b3c4d5e6f7a8b9c0d1e2f',
                displayHash: '0x99f...1e2f',
                type: 'Claim',
                description: 'Claimed Staking Rewards',
                amount: '+14.82 OPUS',
                status: 'Confirmed',
                timestamp: Date.now() - 172800000,
                blockNumber: 19821099
            }
        ],
        settings: {
            theme: 'dark',
            currency: 'USD',
            language: 'en',
            slippageTolerance: 0.5,
            enableSounds: true,
            autoRefreshInterval: 3000
        }
    };

    // Web Audio Synthesizer Engine for Cybernetic Feedback
    const SoundEngine = {
        ctx: null,
        init() {
            try {
                if (!this.ctx && typeof AudioContext !== 'undefined') {
                    this.ctx = new (window.AudioContext || window.webkitAudioContext)();
                }
            } catch (e) {
                console.warn('AudioContext not supported or blocked');
            }
        },
        play(type) {
            if (!state.settings.enableSounds) return;
            this.init();
            if (!this.ctx) return;

            const now = this.ctx.currentTime;
            const osc = this.ctx.createOscillator();
            const gain = this.ctx.createGain();
            osc.connect(gain);
            gain.connect(this.ctx.destination);

            if (type === 'click') {
                osc.type = 'sine';
                osc.frequency.setValueAtTime(800, now);
                osc.frequency.exponentialRampToValueAtTime(400, now + 0.05);
                gain.gain.setValueAtTime(0.08, now);
                gain.gain.exponentialRampToValueAtTime(0.001, now + 0.05);
                osc.start(now);
                osc.stop(now + 0.05);
            } else if (type === 'success') {
                osc.type = 'triangle';
                osc.frequency.setValueAtTime(523.25, now); // C5
                osc.frequency.setValueAtTime(659.25, now + 0.08); // E5
                osc.frequency.setValueAtTime(783.99, now + 0.16); // G5
                gain.gain.setValueAtTime(0.1, now);
                gain.gain.exponentialRampToValueAtTime(0.001, now + 0.3);
                osc.start(now);
                osc.stop(now + 0.3);
            } else if (type === 'swap') {
                osc.type = 'sawtooth';
                osc.frequency.setValueAtTime(300, now);
                osc.frequency.linearRampToValueAtTime(1200, now + 0.15);
                gain.gain.setValueAtTime(0.05, now);
                gain.gain.exponentialRampToValueAtTime(0.001, now + 0.2);
                osc.start(now);
                osc.stop(now + 0.2);
            }
        }
    };

    // UI Controller
    const UI = {
        init() {
            this.bindEvents();
            this.renderDashboard();
            this.startRealtimeUpdates();
        },

        bindEvents() {
            document.querySelectorAll('.btn-action').forEach(btn => {
                btn.addEventListener('click', (e) => {
                    SoundEngine.play('click');
                    const action = e.currentTarget.dataset.action;
                    this.handleAction(action);
                });
            });

            document.getElementById('connect-wallet')?.addEventListener('click', () => this.connectWallet());
            
            // Swap Input Handlers
            const swapFrom = document.getElementById('swap-from-amount');
            const swapTo = document.getElementById('swap-to-amount');

            swapFrom?.addEventListener('input', (e) => {
                const val = e.target.value;
                state.swap.fromAmount = val;
                this.calculateSwap(val, 'from');
            });

            swapTo?.addEventListener('input', (e) => {
                const val = e.target.value;
                state.swap.toAmount = val;
                this.calculateSwap(val, 'to');
            });
        },

        handleAction(action) {
            console.log(`Executing action: ${action}`);
            if (action === 'swap') {
                SoundEngine.play('swap');
                // Logic for swap execution would go here
            }
        },

        connectWallet() {
            state.wallet.connected = true;
            SoundEngine.play('success');
            this.renderDashboard();
            alert('Wallet Connected: ' + state.wallet.address);
        },

        calculateSwap(val, direction) {
            if (!val || isNaN(val)) return;
            const numVal = parseFloat(val);
            if (direction === 'from') {
                const rate = state.market.price;
                state.swap.toAmount = (numVal * rate).toFixed(2);
            } else {
                const rate = state.market.price;
                state.swap.fromAmount = (numVal / rate).toFixed(6);
            }
            this.updateSwapUI();
        },

        updateSwapUI() {
            const fromInput = document.getElementById('swap-from-amount');
            const toInput = document.getElementById('swap-to-amount');
            if (fromInput) fromInput.value = state.swap.fromAmount;
            if (toInput) toInput.value = state.swap.toAmount;
        },

        renderDashboard() {
            // Render Wallet Balance
            const balanceEl = document.getElementById('wallet-balance');
            if (balanceEl) {
                balanceEl.textContent = `$${(state.wallet.balanceEth * state.market.price + state.wallet.balanceUsdt).toLocaleString()}`;
            }

            // Render Token List
            const tokenList = document.getElementById('token-list');
            if (tokenList) {
                tokenList.innerHTML = state.wallet.tokens.map(token => `
                    <div class="token-item">
                        <div class="token-info">
                            <span class="token-symbol">${token.symbol}</span>
                            <span class="token-name">${token.name}</span>
                        </div>
                        <div class="token-balance">
                            <span class="token-amount">${token.balance.toFixed(4)}</span>
                            <span class="token-price">$${token.price.toLocaleString()}</span>
                        </div>
                    </div>
                `).join('');
            }

            // Render Transactions
            const txList = document.getElementById('transaction-list');
            if (txList) {
                txList.innerHTML = state.transactions.map(tx => `
                    <div class="tx-item">
                        <div class="tx-meta">
                            <span class="tx-type">${tx.type}</span>
                            <span class="tx-hash">${tx.displayHash}</span>
                        </div>
                        <div class="tx-details">
                            <span class="tx-desc">${tx.description}</span>
                            <span class="tx-amount ${tx.amount.startsWith('+') ? 'text-success' : 'text-danger'}">${tx.amount}</span>
                        </div>
                        <div class="tx-status">${tx.status}</div>
                    </div>
                `).join('');
            }

            // Render NFTs
            const nftGrid = document.getElementById('nft-grid');
            if (nftGrid) {
                nftGrid.innerHTML = state.nfts.map(nft => `
                    <div class="nft-card">
                        <img src="${nft.image}" alt="${nft.name}" class="nft-img">
                        <div class="nft-info">
                            <h4>${nft.name}</h4>
                            <p>${nft.rarity}</p>
                            <div class="nft-price">${nft.price}</div>
                        </div>
                    </div>
                `).join('');
            }
        },

        startRealtimeUpdates() {
            setInterval(() => {
                // Simulate market volatility
                const volatility = (Math.random() - 0.5) * 10;
                state.market.price += volatility;
                state.market.change24h += (volatility / 100);
                
                // Update UI elements without full re-render for performance
                const priceEl = document.getElementById('market-price');
                if (priceEl) priceEl.textContent = `$${state.market.price.toLocaleString(undefined, {minimumFractionDigits: 2, maximumFractionDigits: 2})}`;
                
                const changeEl = document.getElementById('market-change');
                if (changeEl) {
                    changeEl.textContent = `${state.market.change24h > 0 ? '+' : ''}${state.market.change24h.toFixed(2)}%`;
                    changeEl.className = `market-change ${state.market.change24h >= 0 ? 'text-success' : 'text-danger'}`;
                }

                // Update Swap calculation if amount is present
                if (state.swap.fromAmount) {
                    this.calculateSwap(state.swap.fromAmount, 'from');
                }
            }, state.settings.autoRefreshInterval);
        }
    };

    // Initialize Application
    document.addEventListener('DOMContentLoaded', () => {
        UI.init();
        console.log('MAGNUM OPUS Engine Initialized.');
    });

})();