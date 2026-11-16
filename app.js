/**
 * MAGNUM OPUS // Web3 & DeFi Nexus Engine - Core Application Engine
 * Version 4.2.0 - Production Grade Full-Stack Web3 Client Architecture
 */

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
                image: '🌌',
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
                image: '⚡',
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
                image: '🛡️',
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
                image: '🌀',
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

            try {
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
                    osc.frequency.setValueAtTime(180, now);
                    osc.frequency.setValueAtTime(120, now + 0.1);
                    gain.gain.setValueAtTime(0.1, now);
                    gain.gain.exponentialRampToValueAtTime(0.001, now + 0.25);
                    osc.start(now);
                    osc.stop(now + 0.25);
                }
            } catch (err) {
                // Ignore audio errors
            }
        }
    };

    // Core Utilities & Formatters
    const Utils = {
        formatCurrency(value, symbol = '', decimals = 2) {
            const safeValue = Number(value) || 0;
            const formatted = safeValue.toLocaleString('en-US', {
                minimumFractionDigits: decimals,
                maximumFractionDigits: decimals
            });
            return symbol ? `${formatted} ${symbol}` : formatted;
        },
        formatUsd(value) {
            const safeValue = Number(value) || 0;
            return '$' + safeValue.toLocaleString('en-US', {
                minimumFractionDigits: 2,
                maximumFractionDigits: 2
            });
        },
        formatAddress(addr) {
            if (!addr) return '';
            return `${addr.substring(0, 6)}...${addr.substring(addr.length - 4)}`;
        },
        formatTimestamp(ts) {
            const date = new Date(ts);
            return date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' });
        },
        calculatePortfolioValue() {
            let total = 0;
            state.wallet.tokens.forEach(token => {
                total += token.balance * token.price;
            });
            return total;
        },
        generateTxHash() {
            const chars = '0123456789abcdef';
            let hash = '0x';
            for (let i = 0; i < 64; i++) {
                hash += chars[Math.floor(Math.random() * chars.length)];
            }
            return hash;
        }
    };

    // Toast Notification Manager
    const Toast = {
        container: null,
        init() {
            let el = document.getElementById('toast-container');
            if (!el) {
                el = document.createElement('div');
                el.id = 'toast-container';
                el.style.cssText = `
                    position: fixed;
                    bottom: 24px;
                    right: 24px;
                    z-index: 99999;
                    display: flex;
                    flex-direction: column;
                    gap: 12px;
                    pointer-events: none;
                `;
                document.body.appendChild(el);
            }
            this.container = el;
        },
        show(title, message, type = 'info') {
            this.init();
            const toast = document.createElement('div');
            toast.className = `toast toast-${type}`;
            
            let borderColor = '#3b82f6';
            let icon = 'ℹ️';
            if (type === 'success') { borderColor = '#10b981'; icon = '✅'; }
            if (type === 'warning') { borderColor = '#f59e0b'; icon = '⚠️'; }
            if (type === 'error') { borderColor = '#ef4444'; icon = '❌'; }

            toast.style.cssText = `
                background: rgba(13, 20, 48, 0.95);
                border-left: 4px solid ${borderColor};
                border-radius: 8px;
                padding: 14px 18px;
                color: #f8fafc;
                box-shadow: 0 10px 25px -5px rgba(0, 0, 0, 0.5);
                backdrop-filter: blur(12px);
                min-width: 280px;
                max-width: 380px;
                pointer-events: auto;
                transform: translateX(100%);
                transition: transform 0.3s cubic-bezier(0.16, 1, 0.3, 1), opacity 0.3s;
                opacity: 0;
                font-family: inherit;
            `;

            toast.innerHTML = `
                <div style="display:flex; align-items:flex-start; gap:12px;">
                    <span style="font-size:18px;">${icon}</span>
                    <div style="flex:1;">
                        <div style="font-weight:600; font-size:14px; margin-bottom:2px;">${title}</div>
                        <div style="font-size:12px; color:#94a3b8;">${message}</div>
                    </div>
                </div>
            `;

            this.container.appendChild(toast);

            requestAnimationFrame(() => {
                toast.style.transform = 'translateX(0)';
                toast.style.opacity = '1';
            });

            SoundEngine.play(type === 'error' ? 'error' : 'click');

            setTimeout(() => {
                toast.style.transform = 'translateX(100%)';
                toast.style.opacity = '0';
                setTimeout(() => toast.remove(), 300);
            }, 4000);
        }
    };

    // Wallet Module
    const WalletController = {
        init() {
            this.bindEvents();
            this.render();
        },
        bindEvents() {
            const connectBtn = document.getElementById('connect-wallet-btn');
            const walletModal = document.getElementById('wallet-modal');
            const closeModal = document.getElementById('close-wallet-modal');

            if (connectBtn) {
                connectBtn.addEventListener('click', () => {
                    if (state.wallet.connected) {
                        this.disconnect();
                    } else {
                        this.connect('MetaMask');
                    }
                });
            }

            if (closeModal && walletModal) {
                closeModal.addEventListener('click', () => {
                    walletModal.style.display = 'none';
                });
            }
        },
        connect(providerName) {
            state.wallet.connected = true;
            state.wallet.address = '0x742d35Cc6634C0532925a3b844Bc454e4438f44e';
            this.render();
            Toast.show('Wallet Connected', `Connected to ${providerName} (${Utils.formatAddress(state.wallet.address)})`, 'success');
            SoundEngine.play('success');
        },
        disconnect() {
            state.wallet.connected = false;
            state.wallet.address = null;
            this.render();
            Toast.show('Wallet Disconnected', 'Your wallet has been disconnected.', 'info');
        },
        render() {
            const btn = document.getElementById('connect-wallet-btn');
            const portfolioEl = document.getElementById('total-portfolio-val');
            const addrEl = document.getElementById('wallet-address-display');
            
            if (btn) {
                if (state.wallet.connected) {
                    btn.innerHTML = `<span style="display:inline-block; width:8px; height:8px; background:#10b981; border-radius:50%; margin-right:8px;"></span>${Utils.formatAddress(state.wallet.address)}`;
                    btn.classList.add('btn-connected');
                } else {
                    btn.innerHTML = 'Connect Wallet';
                    btn.classList.remove('btn-connected');
                }
            }

            if (portfolioEl) {
                portfolioEl.textContent = Utils.formatUsd(Utils.calculatePortfolioValue());
            }

            if (addrEl && state.wallet.address) {
                addrEl.textContent = state.wallet.address;
            }

            this.renderTokenBalances();
        },
        renderTokenBalances() {
            const tokenListEl = document.getElementById('token-balances-list');
            if (!tokenListEl) return;

            tokenListEl.innerHTML = state.wallet.tokens.map(token => {
                const totalVal = token.balance * token.price;
                const isPos = token.change24h >= 0;
                return `
                    <div class="token-row" style="display:flex; justify-content:space-between; align-items:center; padding:12px; border-bottom:1px solid rgba(255,255,255,0.05);">
                        <div style="display:flex; align-items:center; gap:10px;">
                            <div class="token-icon" style="width:32px; height:32px; border-radius:50%; background:rgba(59,130,246,0.2); display:flex; align-items:center; justify-content:center; font-weight:bold; font-size:12px; color:#60a5fa;">
                                ${token.symbol.substring(0, 3)}
                            </div>
                            <div>
                                <div style="font-weight:600;">${token.name}</div>
                                <div style="font-size:12px; color:#64748b;">${token.symbol}</div>
                            </div>
                        </div>
                        <div style="text-align:right;">
                            <div style="font-weight:600;">${token.balance.toLocaleString()} ${token.symbol}</div>
                            <div style="font-size:12px; color:${isPos ? '#10b981' : '#ef4444'};">
                                ${Utils.formatUsd(totalVal)} (${isPos ? '+' : ''}${token.change24h}%)
                            </div>
                        </div>
                    </div>
                `;
            }).join('');
        }
    };

    // Market & Live Candlestick/Line Dynamic Chart Controller
    const MarketController = {
        canvas: null,
        ctx: null,
        init() {
            this.canvas = document.getElementById('market-chart-canvas');
            if (this.canvas) {
                this.ctx = this.canvas.getContext('2d');
                this.resizeCanvas();
                window.addEventListener('resize', () => this.resizeCanvas());
            }
            this.generateInitialChartData();
            this.bindEvents();
            this.render();
        },
        resizeCanvas() {
            if (!this.canvas) return;
            const rect = this.canvas.parentElement.getBoundingClientRect();
            this.canvas.width = rect.width;
            this.canvas.height = rect.height || 300;
            this.renderChart();
        },
        generateInitialChartData() {
            const points = 40;
            let currentPrice = state.market.price;
            state.market.chartData.prices = [];
            state.market.chartData.labels = [];
            
            for (let i = points; i >= 0; i--) {
                const time = new Date(Date.now() - i * 15 * 60 * 1000);
                currentPrice += (Math.random() - 0.48) * 15;
                state.market.chartData.prices.push(currentPrice);
                state.market.chartData.labels.push(time.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }));
            }
        },
        bindEvents() {
            const timeframeBtns = document.querySelectorAll('.tf-btn');
            timeframeBtns.forEach(btn => {
                btn.addEventListener('click', (e) => {
                    timeframeBtns.forEach(b => b.classList.remove('active'));
                    e.target.classList.add('active');
                    state.market.timeframe = e.target.textContent;
                    this.generateInitialChartData();
                    this.renderChart();
                    SoundEngine.play('click');
                });
            });
        },
        render() {
            const priceEl = document.getElementById('market-current-price');
            const changeEl = document.getElementById('market-price-change');
            const highEl = document.getElementById('market-24h-high');
            const lowEl = document.getElementById('market-24h-low');
            const volumeEl = document.getElementById('market-24h-volume');

            if (priceEl) priceEl.textContent = Utils.formatUsd(state.market.price);
            if (changeEl) {
                const isPos = state.market.change24h >= 0;
                changeEl.textContent = `${isPos ? '+' : ''}${state.market.change24h}%`;
                changeEl.style.color = isPos ? '#10b981' : '#ef4444';
            }
            if (highEl) highEl.textContent = Utils.formatUsd(state.market.high24h);
            if (lowEl) lowEl.textContent = Utils.formatUsd(state.market.low24h);
            if (volumeEl) volumeEl.textContent = Utils.formatUsd(state.market.volume24h);

            this.renderChart();
        },
        renderChart() {
            if (!this.ctx || !this.canvas) return;
            const ctx = this.ctx;
            const width = this.canvas.width;
            const height = this.canvas.height;
            const prices = state.market.chartData.prices;
            if (prices.length === 0) return;

            ctx.clearRect(0, 0, width, height);

            const minPrice = Math.min(...prices) * 0.998;
            const maxPrice = Math.max(...prices) * 1.002;
            const range = maxPrice - minPrice || 1;

            // Draw Grid Lines
            ctx.strokeStyle = 'rgba(255, 255, 255, 0.04)';
            ctx.lineWidth = 1;
            for (let i = 1; i <= 4; i++) {
                const y = (height / 5) * i;
                ctx.beginPath();
                ctx.moveTo(0, y);
                ctx.lineTo(width, y);
                ctx.stroke();
            }

            // Gradient Fill for Price Line
            const gradient = ctx.createLinearGradient(0, 0, 0, height);
            gradient.addColorStop(0, 'rgba(59, 130, 246, 0.35)');
            gradient.addColorStop(1, 'rgba(59, 130, 246, 0.0)');

            ctx.beginPath();
            prices.forEach((price, i) => {
                const x = (i / (prices.length - 1)) * width;
                const y = height - ((price - minPrice) / range) * height;
                if (i === 0) ctx.moveTo(x, y);
                else ctx.lineTo(x, y);
            });

            // Stroke Line
            ctx.strokeStyle = '#3b82f6';
            ctx.lineWidth = 2.5;
            ctx.stroke();

            // Fill Area
            ctx.lineTo(width, height);
            ctx.lineTo(0, height);
            ctx.closePath();
            ctx.fillStyle = gradient;
            ctx.fill();
        }
    };

    // Order Book Component Engine
    const OrderBookController = {
        init() {
            this.generateOrderBookData();
            this.render();
        },
        generateOrderBookData() {
            const basePrice = state.market.price;
            state.orderBook.bids = [];
            state.orderBook.asks = [];

            let accumBidTotal = 0;
            let accumAskTotal = 0;

            for (let i = 1; i <= 8; i++) {
                const bidPrice = basePrice * (1 - i * 0.0015);
                const bidAmount = (Math.random() * 2.5 + 0.1).toFixed(3);
                accumBidTotal += parseFloat(bidAmount);
                state.orderBook.bids.push({ price: bidPrice, amount: bidAmount, total: accumBidTotal.toFixed(3) });

                const askPrice = basePrice * (1 + i * 0.0015);
                const askAmount = (Math.random() * 2.5 + 0.1).toFixed(3);
                accumAskTotal += parseFloat(askAmount);
                state.orderBook.asks.push({ price: askPrice, amount: askAmount, total: accumAskTotal.toFixed(3) });
            }
        },
        render() {
            const bidsEl = document.getElementById('orderbook-bids');
            const asksEl = document.getElementById('orderbook-asks');
            if (!bidsEl || !asksEl) return;

            bidsEl.innerHTML = state.orderBook.bids.map(b => `
                <div style="display:flex; justify-space-between; font-size:12px; padding:3px 0; position:relative;">
                    <span style="color:#10b981; flex:1;">${b.price.toFixed(2)}</span>
                    <span style="color:#cbd5e1; flex:1; text-align:right;">${b.amount}</span>
                    <span style="color:#64748b; flex:1; text-align:right;">${b.total}</span>
                </div>
            `).join('');

            asksEl.innerHTML = state.orderBook.asks.map(a => `
                <div style="display:flex; justify-space-between; font-size:12px; padding:3px 0; position:relative;">
                    <span style="color:#ef4444; flex:1;">${a.price.toFixed(2)}</span>
                    <span style="color:#cbd5e1; flex:1; text-align:right;">${a.amount}</span>
                    <span style="color:#64748b; flex:1; text-align:right;">${a.total}</span>
                </div>
            `).join('');
        }
    };

    // DEX Swap Module Engine
    const SwapController = {
        init() {
            this.bindEvents();
            this.updateCalculations();
        },
        bindEvents() {
            const fromInput = document.getElementById('swap-from-amount');
            const switchBtn = document.getElementById('swap-switch-btn');
            const submitBtn = document.getElementById('swap-submit-btn');

            if (fromInput) {
                fromInput.addEventListener('input', (e) => {
                    state.swap.fromAmount = e.target.value;
                    this.updateCalculations();
                });
            }

            if (switchBtn) {
                switchBtn.addEventListener('click', () => {
                    const temp = state.swap.fromToken;
                    state.swap.fromToken = state.swap.toToken;
                    state.swap.toToken = temp;
                    this.updateCalculations();
                    SoundEngine.play('swap');
                });
            }

            if (submitBtn) {
                submitBtn.addEventListener('click', () => {
                    this.executeSwap();
                });
            }
        },
        updateCalculations() {
            const fromInput = document.getElementById('swap-from-amount');
            const toInput = document.getElementById('swap-to-amount');
            const rateEl = document.getElementById('swap-exchange-rate');
            const impactEl = document.getElementById('swap-price-impact');

            const fromTokenObj = state.wallet.tokens.find(t => t.symbol === state.swap.fromToken) || { price: 1 };
            const toTokenObj = state.wallet.tokens.find(t => t.symbol === state.swap.toToken) || { price: 1 };

            const rate = fromTokenObj.price / toTokenObj.price;
            if (rateEl) rateEl.textContent = `1 ${state.swap.fromToken} ≈ ${rate.toFixed(4)} ${state.swap.toToken}`;

            const val = parseFloat(state.swap.fromAmount) || 0;
            const calculatedTo = (val * rate).toFixed(4);
            if (toInput && document.activeElement !== toInput) {
                toInput.value = val > 0 ? calculatedTo : '';
            }

            const impact = val > 100 ? (val * 0.0001).toFixed(2) : '0.04';
            if (impactEl) impactEl.textContent = `${impact}%`;
        },
        executeSwap() {
            if (!state.wallet.connected) {
                Toast.show('Wallet Required', 'Please connect your wallet to execute swaps.', 'warning');
                return;
            }

            const amount = parseFloat(state.swap.fromAmount);
            if (!amount || amount <= 0) {
                Toast.show('Invalid Amount', 'Please enter a valid swap amount.', 'error');
                return;
            }

            const hash = Utils.generateTxHash();
            const newTx = {
                hash,
                displayHash: Utils.formatAddress(hash),
                type: 'Swap',
                description: `Swapped ${amount} ${state.swap.fromToken} for ${(amount * 3450).toFixed(2)} ${state.swap.toToken}`,
                amount: `-${amount} ${state.swap.fromToken}`,
                status: 'Confirmed',
                timestamp: Date.now(),
                blockNumber: 19842106 + state.transactions.length
            };

            state.transactions.unshift(newTx);
            TransactionController.render();

            Toast.show('Swap Executed', `Successfully swapped ${amount} ${state.swap.fromToken}`, 'success');
            SoundEngine.play('success');

            // Clear inputs
            state.swap.fromAmount = '';
            const fromInput = document.getElementById('swap-from-amount');
            const toInput = document.getElementById('swap-to-amount');
            if (fromInput) fromInput.value = '';
            if (toInput) toInput.value = '';
        }
    };

    // Staking Module
    const StakingController = {
        init() {
            this.bindEvents();
            this.render();
            this.startRewardTicker();
        },
        bindEvents() {
            const claimBtn = document.getElementById('staking-claim-btn');
            const stakeBtn = document.getElementById('staking-stake-btn');

            if (claimBtn) {
                claimBtn.addEventListener('click', () => this.claimRewards());
            }
            if (stakeBtn) {
                stakeBtn.addEventListener('click', () => this.stakeOpus());
            }
        },
        startRewardTicker() {
            setInterval(() => {
                // Increment pending rewards based on APY
                const perSecondReward = (state.staking.stakedOpus * (state.staking.rewardRateApy / 100)) / (365 * 86400);
                state.staking.pendingRewards += perSecondReward;
                const pendingEl = document.getElementById('staking-pending-rewards');
                if (pendingEl) {
                    pendingEl.textContent = state.staking.pendingRewards.toFixed(4) + ' OPUS';
                }
            }, 1000);
        },
        claimRewards() {
            if (state.staking.pendingRewards <= 0) {
                Toast.show('No Rewards', 'You have no pending rewards to claim.', 'info');
                return;
            }
            const claimed = state.staking.pendingRewards;
            state.staking.totalClaimed += claimed;
            state.staking.pendingRewards = 0;

            Toast.show('Rewards Claimed', `Successfully claimed ${claimed.toFixed(4)} OPUS!`, 'success');
            SoundEngine.play('success');
            this.render();
        },
        stakeOpus() {
            state.staking.stakedOpus += 500;
            Toast.show('Stake Increased', 'Staked an additional 500 OPUS into Yield Vault.', 'success');
            SoundEngine.play('success');
            this.render();
        },
        render() {
            const stakedEl = document.getElementById('staking-staked-amount');
            const apyEl = document.getElementById('staking-apy');
            const claimedEl = document.getElementById('staking-total-claimed');

            if (stakedEl) stakedEl.textContent = `${state.staking.stakedOpus.toLocaleString()} OPUS`;
            if (apyEl) apyEl.textContent = `${state.staking.rewardRateApy}%`;
            if (claimedEl) claimedEl.textContent = `${state.staking.totalClaimed.toFixed(2)} OPUS`;
        }
    };

    // NFT Marketplace Controller
    const NFTController = {
        init() {
            this.render();
        },
        render() {
            const gridEl = document.getElementById('nft-grid-container');
            if (!gridEl) return;

            gridEl.innerHTML = state.nfts.map(nft => `
                <div class="nft-card" style="background:rgba(13,20,48,0.75); border:1px solid rgba(255,255,255,0.08); border-radius:12px; padding:16px; transition:transform 0.2s;">
                    <div style="height:140px; background:rgba(30,41,59,0.5); border-radius:8px; display:flex; align-items:center; justify-content:center; font-size:48px;">
                        ${nft.image}
                    </div>
                    <div style="margin-top:12px; display:flex; justify-content:space-between; align-items:flex-start;">
                        <div>
                            <div style="font-weight:700; font-size:16px;">${nft.name}</div>
                            <div style="font-size:12px; color:#64748b;">${nft.collection}</div>
                        </div>
                        <span class="badge-rarity" style="background:rgba(59,130,246,0.2); color:#60a5fa; font-size:10px; padding:2px 8px; border-radius:12px; font-weight:600;">
                            ${nft.rarity}
                        </span>
                    </div>
                    <div style="margin-top:14px; display:flex; justify-content:space-between; align-items:center;">
                        <div>
                            <div style="font-size:10px; color:#94a3b8;">Price</div>
                            <div style="font-weight:700; color:#10b981;">${nft.price}</div>
                        </div>
                        <button class="btn-buy-nft" data-id="${nft.id}" style="background:#3b82f6; color:#fff; border:none; padding:6px 14px; border-radius:6px; cursor:pointer; font-size:12px; font-weight:600;">
                            Buy Now
                        </button>
                    </div>
                </div>
            `).join('');

            gridEl.querySelectorAll('.btn-buy-nft').forEach(btn => {
                btn.addEventListener('click', (e) => {
                    const id = parseInt(e.target.getAttribute('data-id'));
                    const nft = state.nfts.find(item => item.id === id);
                    if (nft) {
                        Toast.show('NFT Purchased', `Acquired ${nft.name} for ${nft.price}!`, 'success');
                        SoundEngine.play('success');
                    }
                });
            });
        }
    };

    // Transaction History Controller
    const TransactionController = {
        init() {
            this.render();
        },
        render() {
            const listEl = document.getElementById('transaction-history-list');
            if (!listEl) return;

            listEl.innerHTML = state.transactions.map(tx => `
                <div style="display:flex; justify-content:space-between; align-items:center; padding:12px 16px; border-bottom:1px solid rgba(255,255,255,0.05); font-size:13px;">
                    <div style="display:flex; align-items:center; gap:12px;">
                        <span style="background:rgba(59,130,246,0.15); color:#60a5fa; width:36px; height:36px; border-radius:8px; display:flex; align-items:center; justify-content:center; font-weight:bold;">
                            ${tx.type.substring(0, 2)}
                        </span>
                        <div>
                            <div style="font-weight:600;">${tx.description}</div>
                            <div style="font-size:11px; color:#64748b;">${tx.displayHash} • Block #${tx.blockNumber}</div>
                        </div>
                    </div>
                    <div style="text-align:right;">
                        <div style="font-weight:600; color:${tx.amount.startsWith('+') ? '#10b981' : '#f8fafc'}">${tx.amount}</div>
                        <div style="font-size:11px; color:#10b981;">${tx.status}</div>
                    </div>
                </div>
            `).join('');
        }
    };

    // Real-Time Simulation Engine (Tickers, Gas Fluctuation, Mempool)
    const LiveEngine = {
        start() {
            setInterval(() => {
                this.updateMarketPrice();
                this.updateGasFees();
            }, state.settings.autoRefreshInterval);
        },
        updateMarketPrice() {
            const delta = (Math.random() - 0.49) * 4.5;
            state.market.price += delta;
            state.market.chartData.prices.shift();
            state.market.chartData.prices.push(state.market.price);
            
            MarketController.render();
            OrderBookController.generateOrderBookData();
            OrderBookController.render();
        },
        updateGasFees() {
            const fluctuation = Math.floor((Math.random() - 0.5) * 3);
            state.gas.standard = Math.max(10, state.gas.standard + fluctuation);
            state.gas.slow = Math.max(8, state.gas.standard - 4);
            state.gas.fast = state.gas.standard + 6;

            const gasBadge = document.getElementById('header-gas-indicator');
            if (gasBadge) {
                gasBadge.textContent = `⛽ ${state.gas.standard} Gwei`;
            }
        }
    };

    // Tab Navigation & Modal Handlers
    function setupNavigation() {
        const navItems = document.querySelectorAll('.nav-tab');
        const sections = document.querySelectorAll('.view-section');

        navItems.forEach(item => {
            item.addEventListener('click', (e) => {
                e.preventDefault();
                const targetTab = item.getAttribute('data-tab');
                
                navItems.forEach(n => n.classList.remove('active'));
                item.classList.add('active');

                sections.forEach(sec => {
                    if (sec.id === `section-${targetTab}`) {
                        sec.style.display = 'block';
                    } else {
                        sec.style.display = 'none';
                    }
                });

                SoundEngine.play('click');
            });
        });
    }

    // Main Entry Initialization
    function initApp() {
        console.log('%c MAGNUM OPUS // Web3 & DeFi Nexus Engine initialized ', 'background: #030611; color: #60a5fa; font-weight: bold; font-size: 14px;');
        
        setupNavigation();
        WalletController.init();
        MarketController.init();
        OrderBookController.init();
        SwapController.init();
        StakingController.init();
        NFTController.init();
        TransactionController.init();
        LiveEngine.start();
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', initApp);
    } else {
        initApp();
    }
})();
