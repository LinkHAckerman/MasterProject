(function () {
    'use strict';

    // Global State Management
    const state = {
        wallet: {
            connected: false,
            address: null,
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
                labels: [],
                prices: [],
                volumes: []
            }
        },
        orderBook: {
            bids: [],
            asks: [],
            maxDepth: 12,
            spread: 0.05
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
                image: '\u001b[38;5;208m\u001b[48;5;16m\u001b[1m\u001b[3m\u001b[4m\u001b[5m\u001b[7m\u001b[8m\u001b[9m\u001b[30m\u001b[31m\u001b[32m\u001b[33m\u001b[34m\u001b[35m\u001b[36m\u001b[37m\u001b[40m\u001b[41m\u001b[42m\u001b[43m\u001b[44m\u001b[45m\u001b[46m\u001b[47m\u001b[0m',
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
                image: '\u001b[38;5;208m\u001b[48;5;16m\u001b[1m\u001b[3m\u001b[4m\u001b[5m\u001b[7m\u001b[8m\u001b[9m\u001b[30m\u001b[31m\u001b[32m\u001b[33m\u001b[34m\u001b[35m\u001b[36m\u001b[37m\u001b[40m\u001b[41m\u001b[42m\u001b[43m\u001b[44m\u001b[45m\u001b[46m\u001b[47m\u001b[0m',
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
                image: '\u001b[38;5;208m\u001b[48;5;16m\u001b[1m\u001b[3m\u001b[4m\u001b[5m\u001b[7m\u001b[8m\u001b[9m\u001b[30m\u001b[31m\u001b[32m\u001b[33m\u001b[34m\u001b[35m\u001b[36m\u001b[37m\u001b[40m\u001b[41m\u001b[42m\u001b[43m\u001b[44m\u001b[45m\u001b[46m\u001b[47m\u001b[0m',
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
                image: '\u001b[38;5;208m\u001b[48;5;16m\u001b[1m\u001b[3m\u001b[4m\u001b[5m\u001b[7m\u001b[8m\u001b[9m\u001b[30m\u001b[31m\u001b[32m\u001b[33m\u001b[34m\u001b[35m\u001b[36m\u001b[37m\u001b[40m\u001b[41m\u001b[42m\u001b[43m\u001b[44m\u001b[45m\u001b[46m\u001b[47m\u001b[0m',
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
            } else if (type === 'error') {
                osc.type = 'square';
                osc.frequency.setValueAtTime(200, now);
                gain.gain.setValueAtTime(0.12, now);
                gain.gain.exponentialRampToValueAtTime(0.001, now + 0.4);
                osc.start(now);
                osc.stop(now + 0.4);
            }
        }
    };

    // Utility Functions -----------------------------------------------------
    const fmt = new Intl.NumberFormat('en-US', { maximumFractionDigits: 4 });
    function formatNumber(num) {
        if (typeof num !== 'number') return num;
        return fmt.format(num);
    }

    function debounce(fn, delay) {
        let timer;
        return function (...args) {
            clearTimeout(timer);
            timer = setTimeout(() => fn.apply(this, args), delay);
        };
    }

    // DOM Rendering ----------------------------------------------------------
    function renderWallet() {
        const walletEl = document.getElementById('wallet-summary');
        if (!walletEl) return;
        const { address, balanceEth, balanceUsdt, balanceBtc, balanceSol, balanceOpus, networkName } = state.wallet;
        walletEl.innerHTML = `
            <div class="wallet-address">${address ? address : 'Not Connected'}</div>
            <div class="network-name">${networkName}</div>
            <div class="balances">
                <span>ETH: ${formatNumber(balanceEth)}</span>
                <span>USDT: ${formatNumber(balanceUsdt)}</span>
                <span>BTC: ${formatNumber(balanceBtc)}</span>
                <span>SOL: ${formatNumber(balanceSol)}</span>
                <span>OPUS: ${formatNumber(balanceOpus)}</span>
            </div>
        `;
    }

    function renderMarket() {
        const marketEl = document.getElementById('market-summary');
        if (!marketEl) return;
        const { selectedPair, price, change24h, volume24h, high24h, low24h } = state.market;
        marketEl.innerHTML = `
            <div class="pair">${selectedPair}</div>
            <div class="price">$${formatNumber(price)}</div>
            <div class="change ${change24h >= 0 ? 'up' : 'down'}">${change24h.toFixed(2)}%</div>
            <div class="details">
                <span>24h Vol: ${formatNumber(volume24h)}</span>
                <span>High: $${formatNumber(high24h)}</span>
                <span>Low: $${formatNumber(low24h)}</span>
            </div>
        `;
    }

    function renderSwap() {
        const fromInput = document.getElementById('swap-from-amount');
        const toInput = document.getElementById('swap-to-amount');
        if (!fromInput || !toInput) return;
        fromInput.value = state.swap.fromAmount;
        toInput.value = state.swap.toAmount;
    }

    function renderTransactions() {
        const txList = document.getElementById('tx-list');
        if (!txList) return;
        txList.innerHTML = state.transactions.map(tx => `
            <li class="tx-item ${tx.status.toLowerCase()}">
                <span class="hash">${tx.displayHash}</span>
                <span class="type">${tx.type}</span>
                <span class="desc">${tx.description}</span>
                <span class="amount">${tx.amount}</span>
                <span class="status">${tx.status}</span>
                <span class="time">${new Date(tx.timestamp).toLocaleString()}</span>
            </li>
        `).join('');
    }

    // Core Interaction Logic -------------------------------------------------
    async function fetchMarketData() {
        // Mock fetch – in a real app replace with actual API call
        return new Promise(resolve => {
            setTimeout(() => {
                const mock = {
                    price: (3400 + Math.random() * 200).toFixed(2),
                    change24h: (Math.random() * 10 - 5).toFixed(2),
                    volume24h: Math.floor(1e9 + Math.random() * 5e8),
                    high24h: (3500 + Math.random() * 100).toFixed(2),
                    low24h: (3300 - Math.random() * 100).toFixed(2)
                };
                resolve(mock);
            }, 500);
        });
    }

    async function updateMarket() {
        const data = await fetchMarketData();
        state.market.price = parseFloat(data.price);
        state.market.change24h = parseFloat(data.change24h);
        state.market.volume24h = data.volume24h;
        state.market.high24h = parseFloat(data.high24h);
        state.market.low24h = parseFloat(data.low24h);
        renderMarket();
    }

    function calculateSwap() {
        const fromToken = state.swap.fromToken;
        const toToken = state.swap.toToken;
        const fromAmt = parseFloat(state.swap.fromAmount);
        if (isNaN(fromAmt) || fromAmt <= 0) {
            state.swap.toAmount = '';
            renderSwap();
            return;
        }
        // Simple price based conversion using market.price for ETH/USDT pair
        let rate = 1;
        if (fromToken === 'ETH' && toToken === 'USDT') {
            rate = state.market.price; // ETH price in USDT
        } else if (fromToken === 'USDT' && toToken === 'ETH') {
            rate = 1 / state.market.price;
        } else {
            // For other pairs, mock a 1:1 rate for demo purposes
            rate = 1;
        }
        const toAmt = (fromAmt * rate * (1 - state.swap.slippage / 100)).toFixed(6);
        state.swap.toAmount = toAmt;
        renderSwap();
    }

    const debouncedCalc = debounce(calculateSwap, 300);

    // Event Listeners --------------------------------------------------------
    function bindUI() {
        const connectBtn = document.getElementById('btn-connect');
        if (connectBtn) {
            connectBtn.addEventListener('click', () => {
                // Mock wallet connection
                state.wallet.connected = true;
                state.wallet.address = '0xDEMO' + Math.floor(Math.random() * 10000).toString(16).padStart(4, '0');
                SoundEngine.play('success');
                renderWallet();
            });
        }

        const fromInput = document.getElementById('swap-from-amount');
        const toSelect = document.getElementById('swap-to-token');
        const fromSelect = document.getElementById('swap-from-token');
        const swapBtn = document.getElementById('btn-swap');

        if (fromInput) {
            fromInput.addEventListener('input', e => {
                state.swap.fromAmount = e.target.value;
                debouncedCalc();
                SoundEngine.play('click');
            });
        }
        if (fromSelect) {
            fromSelect.addEventListener('change', e => {
                state.swap.fromToken = e.target.value;
                calculateSwap();
                SoundEngine.play('click');
            });
        }
        if (toSelect) {
            toSelect.addEventListener('change', e => {
                state.swap.toToken = e.target.value;
                calculateSwap();
                SoundEngine.play('click');
            });
        }
        if (swapBtn) {
            swapBtn.addEventListener('click', () => {
                // Mock swap execution
                if (!state.wallet.connected) {
                    alert('Connect wallet first');
                    SoundEngine.play('error');
                    return;
                }
                if (!state.swap.fromAmount || !state.swap.toAmount) {
                    alert('Enter amount');
                    SoundEngine.play('error');
                    return;
                }
                // Update balances (very naive)
                const fromTok = state.wallet.tokens.find(t => t.symbol === state.swap.fromToken);
                const toTok = state.wallet.tokens.find(t => t.symbol === state.swap.toToken);
                const fromAmtNum = parseFloat(state.swap.fromAmount);
                const toAmtNum = parseFloat(state.swap.toAmount);
                if (fromTok && fromTok.balance >= fromAmtNum) {
                    fromTok.balance -= fromAmtNum;
                    toTok.balance += toAmtNum;
                    // Add transaction record
                    const tx = {
                        hash: '0x' + Math.random().toString(16).substr(2, 64),
                        displayHash: '',
                        type: 'Swap',
                        description: `Swapped ${fromAmtNum} ${fromTok.symbol} for ${toAmtNum} ${toTok.symbol}`,
                        amount: `-${fromAmtNum} ${fromTok.symbol}`,
                        status: 'Pending',
                        timestamp: Date.now(),
                        blockNumber: null
                    };
                    tx.displayHash = tx.hash.slice(0, 6) + '...' + tx.hash.slice(-4);
                    state.transactions.unshift(tx);
                    renderTransactions();
                    renderWallet();
                    SoundEngine.play('swap');
                    // Simulate confirmation after 2 seconds
                    setTimeout(() => {
                        tx.status = 'Confirmed';
                        tx.blockNumber = Math.floor(19000000 + Math.random() * 100000);
                        renderTransactions();
                        SoundEngine.play('success');
                    }, 2000);
                } else {
                    alert('Insufficient balance');
                    SoundEngine.play('error');
                }
            });
        }
    }

    // Auto‑Refresh Loop ------------------------------------------------------
    function startAutoRefresh() {
        setInterval(updateMarket, state.settings.autoRefreshInterval);
    }

    // Initialization ----------------------------------------------------------
    document.addEventListener('DOMContentLoaded', () => {
        renderWallet();
        renderMarket();
        renderSwap();
        renderTransactions();
        bindUI();
        startAutoRefresh();
    });

})();