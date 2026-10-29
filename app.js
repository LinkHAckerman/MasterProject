/**
 * MAGNUM OPUS // Web3 & DeFi Nexus Engine - Core Dashboard Application Logic
 * High-performance interactive dashboard engine with real-time data feeds,
 * simulated wallet interactions, orderbook engine, canvas chart renderer,
 * DEX swap routing, yield staking, and Web Audio sound engine.
 */

(function () {
    'use strict';

    // ---------------------------------------------------------------------
    // State Store
    // ---------------------------------------------------------------------
    const state = {
        wallet: {
            connected: false,
            address: null,
            balanceEth: 14.852,
            balanceUsdt: 42500.00,
            balanceBtc: 0.65,
            balanceSol: 12.5,
            chainId: '0x1',
            networkName: 'Ethereum Mainnet',
            tokens: [
                { symbol: 'ETH', name: 'Ethereum', balance: 14.852, decimals: 18, price: 3450.75 },
                { symbol: 'USDT', name: 'Tether USD', balance: 42500.00, decimals: 6, price: 1.00 },
                { symbol: 'BTC', name: 'Bitcoin', balance: 0.65, decimals: 8, price: 64200.00 },
                { symbol: 'SOL', name: 'Solana', balance: 12.5, decimals: 9, price: 145.20 },
                { symbol: 'OPUS', name: 'Magnum Opus Governance', balance: 10000.0, decimals: 18, price: 0.45 }
            ]
        },
        gas: {
            slow: 12,
            standard: 18,
            fast: 24,
            current: 18,
            unit: 'Gwei'
        },
        market: {
            selectedPair: 'ETH/USDT',
            price: 3450.75,
            change24h: 4.82,
            volume24h: 1284509000,
            high24h: 3520.00,
            low24h: 3310.50,
            chartData: {
                labels: [],
                prices: [],
                candles: []
            }
        },
        orderBook: {
            bids: [],
            asks: [],
            maxDepth: 12
        },
        transactions: [
            {
                hash: '0x71a...f89e',
                type: 'Swap',
                description: 'Swapped 1.5 ETH for 5,176.12 USDT',
                amount: '1.5 ETH',
                status: 'Confirmed',
                timestamp: Date.now() - 3600000,
                blockNumber: 19842105
            },
            {
                hash: '0x32c...e11b',
                type: 'Stake',
                description: 'Staked 2,500 OPUS in Vault',
                amount: '2,500 OPUS',
                status: 'Confirmed',
                timestamp: Date.now() - 86400000,
                blockNumber: 19835012
            }
        ],
        portfolio: [
            { symbol: 'ETH', name: 'Ethereum', balance: 14.852, price: 3450.75, value: 51249.54, allocation: 53.8 },
            { symbol: 'BTC', name: 'Bitcoin', balance: 0.65, price: 64200.00, value: 41730.00, allocation: 43.8 },
            { symbol: 'SOL', name: 'Solana', balance: 12.5, price: 145.20, value: 1815.00, allocation: 1.9 },
            { symbol: 'OPUS', name: 'Magnum Opus', balance: 1000.0, price: 0.45, value: 450.00, allocation: 0.5 }
        ],
        staking: {
            stakedOpus: 2500.0,
            rewardRateApy: 18.5,
            pendingRewards: 14.82,
            lastClaimed: Date.now() - 432000000
        },
        notifications: [],
        settings: {
            theme: 'dark',
            currency: 'USD',
            language: 'en',
            slippageTolerance: 0.5,
            enableSounds: true,
            autoRefreshInterval: 3000
        }
    };

    // ---------------------------------------------------------------------
    // Pair exchange rates dictionary (static mock data)
    // ---------------------------------------------------------------------
    const PAIR_RATES = {
        'ETH/USDT': { base: 'ETH', quote: 'USDT', price: 3450.75, decimals: 2 },
        'BTC/USDT': { base: 'BTC', quote: 'USDT', price: 64200.00, decimals: 2 },
        'SOL/USDT': { base: 'SOL', quote: 'USDT', price: 145.20, decimals: 2 },
        'OPUS/USDT': { base: 'OPUS', quote: 'USDT', price: 0.45, decimals: 4 },
        'ETH/BTC': { base: 'ETH', quote: 'BTC', price: 0.0537, decimals: 6 }
    };

    // ---------------------------------------------------------------------
    // DOM Elements Cache – populated in initDOM()
    // ---------------------------------------------------------------------
    let DOM = {};

    // ---------------------------------------------------------------------
    // Engine Tickers (interval handles)
    // ---------------------------------------------------------------------
    let marketInterval = null;
    let gasInterval = null;
    let orderBookInterval = null;
    let stakingInterval = null;

    // ---------------------------------------------------------------------
    // Web Audio – procedural sound synthesis
    // ---------------------------------------------------------------------
    let audioCtx = null;

    /**
     * Play a short tone for UI feedback.
     * @param {number} freq Frequency in Hz
     * @param {string} type Oscillator type (sine, square, sawtooth, triangle)
     * @param {number} duration Seconds
     * @param {number} gainVal Linear gain (0‑1)
     */
    function playAudioTone(freq, type = 'sine', duration = 0.15, gainVal = 0.05) {
        if (!state.settings.enableSounds) return;
        try {
            if (!audioCtx) {
                audioCtx = new (window.AudioContext || window.webkitAudioContext)();
            }
            if (audioCtx.state === 'suspended') {
                audioCtx.resume();
            }
            const osc = audioCtx.createOscillator();
            const gain = audioCtx.createGain();
            osc.type = type;
            osc.frequency.setValueAtTime(freq, audioCtx.currentTime);
            gain.gain.setValueAtTime(gainVal, audioCtx.currentTime);
            // Exponential fade‑out to avoid clicks
            gain.gain.exponentialRampToValueAtTime(0.0001, audioCtx.currentTime + duration);
            osc.connect(gain);
            gain.connect(audioCtx.destination);
            osc.start();
            osc.stop(audioCtx.currentTime + duration);
        } catch (e) {
            console.error('Audio tone error:', e);
        }
    }

    // ---------------------------------------------------------------------
    // UI Rendering Helpers
    // ---------------------------------------------------------------------
    function renderWallet() {
        if (!DOM.walletAddress) return;
        DOM.walletAddress.textContent = state.wallet.connected ? state.wallet.address : 'Not Connected';
        DOM.walletBalance.textContent = state.wallet.connected ? `${state.wallet.balanceEth.toFixed(4)} ETH` : '--';
    }

    function renderMarket() {
        if (!DOM.marketPair) return;
        const m = state.market;
        DOM.marketPair.textContent = m.selectedPair;
        DOM.marketPrice.textContent = `$${m.price.toLocaleString(undefined, {minimumFractionDigits: 2, maximumFractionDigits: 2})}`;
        DOM.marketChange.textContent = `${m.change24h.toFixed(2)}%`;
        DOM.marketChange.className = m.change24h >= 0 ? 'positive' : 'negative';
        DOM.marketVolume.textContent = `${(m.volume24h / 1e6).toFixed(2)}M`; // display in millions
    }

    function renderOrderBook() {
        if (!DOM.orderBookBids || !DOM.orderBookAsks) return;
        const { bids, asks, maxDepth } = state.orderBook;
        const renderSide = (container, rows) => {
            container.innerHTML = '';
            rows.slice(0, maxDepth).forEach(r => {
                const div = document.createElement('div');
                div.className = 'order-row';
                div.textContent = `${r.price.toFixed(2)} @ ${r.amount}`;
                container.appendChild(div);
            });
        };
        renderSide(DOM.orderBookBids, bids);
        renderSide(DOM.orderBookAsks, asks);
    }

    function renderPortfolio() {
        if (!DOM.portfolioTable) return;
        const tbody = DOM.portfolioTable.querySelector('tbody');
        tbody.innerHTML = '';
        state.portfolio.forEach(p => {
            const tr = document.createElement('tr');
            tr.innerHTML = `
                <td>${p.symbol}</td>
                <td>${p.balance.toLocaleString(undefined, {maximumFractionDigits: 4})}</td>
                <td>$${p.price.toLocaleString(undefined, {minimumFractionDigits: 2, maximumFractionDigits: 2})}</td>
                <td>$${p.value.toLocaleString(undefined, {minimumFractionDigits: 2, maximumFractionDigits: 2})}</td>
                <td>${p.allocation.toFixed(1)}%</td>
            `;
            tbody.appendChild(tr);
        });
    }

    function renderStaking() {
        if (!DOM.stakingInfo) return;
        const s = state.staking;
        DOM.stakingInfo.textContent = `Staked: ${s.stakedOpus.toLocaleString()} OPUS | APY: ${s.rewardRateApy}% | Pending: ${s.pendingRewards.toFixed(2)} OPUS`;
    }

    function renderNotifications() {
        if (!DOM.notificationList) return;
        const list = DOM.notificationList;
        list.innerHTML = '';
        state.notifications.slice(-5).reverse().forEach(n => {
            const li = document.createElement('li');
            li.textContent = n;
            list.appendChild(li);
        });
    }

    function renderSettings() {
        if (!DOM.themeToggle) return;
        document.body.dataset.theme = state.settings.theme;
        DOM.themeToggle.checked = state.settings.theme === 'dark';
        DOM.slippageInput.value = state.settings.slippageTolerance;
    }

    // ---------------------------------------------------------------------
    // Mock Data Updaters – in a real product these would call APIs
    // ---------------------------------------------------------------------
    function updateMarketData() {
        const pair = state.market.selectedPair;
        const rate = PAIR_RATES[pair];
        // Simulate small random walk
        const delta = (Math.random() - 0.5) * rate.price * 0.005; // ±0.25%
        rate.price = Math.max(rate.price + delta, 0.01);
        state.market.price = parseFloat(rate.price.toFixed(rate.decimals));
        // Simulate 24h change based on price drift
        state.market.change24h = ((rate.price - PAIR_RATES[pair].price) / PAIR_RATES[pair].price) * 100;
        state.market.volume24h = Math.floor(Math.random() * 5e9) + 1e9; // 1‑5B
        renderMarket();
        // Play a subtle tick sound on price update
        playAudioTone(440, 'sine', 0.07, 0.02);
    }

    function updateGasData() {
        const base = 12;
        const jitter = Math.random() * 6; // 0‑6 Gwei
        state.gas.slow = Math.round(base + jitter * 0.5);
        state.gas.standard = Math.round(base + jitter);
        state.gas.fast = Math.round(base + jitter * 1.5);
        state.gas.current = state.gas.standard;
        if (DOM.gasCurrent) {
            DOM.gasCurrent.textContent = `${state.gas.current} ${state.gas.unit}`;
        }
    }

    function updateOrderBook() {
        const generateSide = (type) => {
            const side = [];
            const basePrice = state.market.price;
            for (let i = 0; i < state.orderBook.maxDepth; i++) {
                const priceFluct = (Math.random() - 0.5) * 0.02 * basePrice; // ±1%
                const price = type === 'bid' ? basePrice - Math.abs(priceFluct) : basePrice + Math.abs(priceFluct);
                const amount = (Math.random() * 10).toFixed(4);
                side.push({ price: parseFloat(price.toFixed(2)), amount });
            }
            // Sort appropriately
            side.sort((a, b) => type === 'bid' ? b.price - a.price : a.price - b.price);
            return side;
        };
        state.orderBook.bids = generateSide('bid');
        state.orderBook.asks = generateSide('ask');
        renderOrderBook();
    }

    function updateStaking() {
        const now = Date.now();
        const elapsed = (now - state.staking.lastClaimed) / 1000; // seconds
        const rewardPerSec = (state.staking.stakedOpus * state.staking.rewardRateApy) / (365 * 24 * 3600 * 100);
        const accrued = rewardPerSec * elapsed;
        state.staking.pendingRewards = parseFloat((state.staking.pendingRewards + accrued).toFixed(4));
        renderStaking();
    }

    // ---------------------------------------------------------------------
    // Event Handlers
    // ---------------------------------------------------------------------
    function bindUIEvents() {
        if (DOM.connectBtn) {
            DOM.connectBtn.addEventListener('click', () => {
                // Mock wallet connection
                state.wallet.connected = true;
                state.wallet.address = '0x' + Math.random().toString(16).substr(2, 40);
                renderWallet();
                playAudioTone(660, 'triangle', 0.12, 0.04);
            });
        }
        if (DOM.themeToggle) {
            DOM.themeToggle.addEventListener('change', (e) => {
                state.settings.theme = e.target.checked ? 'dark' : 'light';
                renderSettings();
                playAudioTone(880, 'sine', 0.08, 0.03);
            });
        }
        if (DOM.slippageInput) {
            DOM.slippageInput.addEventListener('input', (e) => {
                const val = parseFloat(e.target.value);
                if (!isNaN(val) && val >= 0 && val <= 5) {
                    state.settings.slippageTolerance = val;
                }
            });
        }
        if (DOM.claimRewardsBtn) {
            DOM.claimRewardsBtn.addEventListener('click', () => {
                state.staking.pendingRewards = 0;
                state.staking.lastClaimed = Date.now();
                renderStaking();
                state.notifications.unshift('Staking rewards claimed');
                renderNotifications();
                playAudioTone(1200, 'square', 0.15, 0.05);
            });
        }
    }

    // ---------------------------------------------------------------------
    // Interval Management
    // ---------------------------------------------------------------------
    function startIntervals() {
        const refresh = state.settings.autoRefreshInterval;
        marketInterval = setInterval(updateMarketData, refresh);
        gasInterval = setInterval(updateGasData, refresh * 2);
        orderBookInterval = setInterval(updateOrderBook, refresh * 3);
        stakingInterval = setInterval(updateStaking, 5000);
    }

    function stopIntervals() {
        clearInterval(marketInterval);
        clearInterval(gasInterval);
        clearInterval(orderBookInterval);
        clearInterval(stakingInterval);
    }

    // ---------------------------------------------------------------------
    // DOM Cache Initialization
    // ---------------------------------------------------------------------
    function initDOM() {
        DOM.walletAddress = document.getElementById('wallet-address');
        DOM.walletBalance = document.getElementById('wallet-balance');
        DOM.connectBtn = document.getElementById('connect-wallet');
        DOM.marketPair = document.getElementById('market-pair');
        DOM.marketPrice = document.getElementById('market-price');
        DOM.marketChange = document.getElementById('market-change');
        DOM.marketVolume = document.getElementById('market-volume');
        DOM.gasCurrent = document.getElementById('gas-current');
        DOM.orderBookBids = document.getElementById('orderbook-bids');
        DOM.orderBookAsks = document.getElementById('orderbook-asks');
        DOM.portfolioTable = document.getElementById('portfolio-table');
        DOM.stakingInfo = document.getElementById('staking-info');
        DOM.claimRewardsBtn = document.getElementById('claim-rewards');
        DOM.notificationList = document.getElementById('notification-list');
        DOM.themeToggle = document.getElementById('theme-toggle');
        DOM.slippageInput = document.getElementById('slippage-input');
    }

    // ---------------------------------------------------------------------
    // Application Bootstrap
    // ---------------------------------------------------------------------
    function init() {
        initDOM();
        renderWallet();
        renderMarket();
        renderOrderBook();
        renderPortfolio();
        renderStaking();
        renderSettings();
        bindUIEvents();
        startIntervals();
        console.log('Magnum Opus dashboard initialized');
    }

    // Kick off when DOM is ready
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
    } else {
        init();
    }

    // Expose a minimal debug API on window for developers
    window.MagnumOpus = {
        state,
        playAudioTone,
        updateMarketData,
        updateGasData,
        updateOrderBook,
        updateStaking
    };

})();