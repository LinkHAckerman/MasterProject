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
    const DOM = {};

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
     * @param {number} frequency Hz
     * @param {number} duration  ms
     */
    function playTone(frequency, duration) {
        if (!state.settings.enableSounds) return;
        if (!audioCtx) audioCtx = new (window.AudioContext || window.webkitAudioContext)();
        const oscillator = audioCtx.createOscillator();
        const gain = audioCtx.createGain();
        oscillator.type = 'sine';
        oscillator.frequency.setValueAtTime(frequency, audioCtx.currentTime);
        gain.gain.setValueAtTime(0.001, audioCtx.currentTime);
        oscillator.connect(gain).connect(audioCtx.destination);
        oscillator.start();
        gain.gain.exponentialRampToValueAtTime(0.2, audioCtx.currentTime + 0.01);
        gain.gain.exponentialRampToValueAtTime(0.001, audioCtx.currentTime + duration / 1000);
        oscillator.stop(audioCtx.currentTime + duration / 1000 + 0.02);
    }

    // ---------------------------------------------------------------------
    // Initialization – cache DOM nodes and bind UI events
    // ---------------------------------------------------------------------
    function initDOM() {
        DOM.walletBtn = document.getElementById('wallet-connect');
        DOM.themeToggle = document.getElementById('theme-toggle');
        DOM.marketPrice = document.getElementById('market-price');
        DOM.marketChange = document.getElementById('market-change');
        DOM.gasSelect = document.getElementById('gas-select');
        DOM.orderBookBids = document.getElementById('orderbook-bids');
        DOM.orderBookAsks = document.getElementById('orderbook-asks');
        DOM.txList = document.getElementById('transaction-list');
        DOM.portfolioTable = document.getElementById('portfolio-table');
        DOM.stakeInfo = document.getElementById('stake-info');
        DOM.notificationArea = document.getElementById('notification-area');
    }

    function bindEvents() {
        if (DOM.walletBtn) {
            DOM.walletBtn.addEventListener('click', () => {
                toggleWalletConnection();
                playTone(440, 120);
            });
        }
        if (DOM.themeToggle) {
            DOM.themeToggle.addEventListener('click', () => {
                state.settings.theme = state.settings.theme === 'dark' ? 'light' : 'dark';
                document.documentElement.setAttribute('data-theme', state.settings.theme);
                playTone(660, 80);
            });
        }
        if (DOM.gasSelect) {
            DOM.gasSelect.addEventListener('change', (e) => {
                const val = parseInt(e.target.value, 10);
                if (!isNaN(val)) state.gas.current = val;
                playTone(550, 100);
            });
        }
    }

    // ---------------------------------------------------------------------
    // Wallet connection mock – toggles state.wallet.connected
    // ---------------------------------------------------------------------
    function toggleWalletConnection() {
        state.wallet.connected = !state.wallet.connected;
        if (state.wallet.connected) {
            // mock address generation
            state.wallet.address = '0x' + [...Array(40)].map(() => Math.floor(Math.random() * 16).toString(16)).join('');
            addNotification('Wallet connected: ' + state.wallet.address, 'info');
        } else {
            addNotification('Wallet disconnected', 'warning');
            state.wallet.address = null;
        }
        renderWalletStatus();
    }

    // ---------------------------------------------------------------------
    // Notification helper
    // ---------------------------------------------------------------------
    function addNotification(message, type = 'info', ttl = 5000) {
        const id = Date.now() + Math.random();
        const note = { id, message, type, timestamp: Date.now() };
        state.notifications.push(note);
        renderNotifications();
        setTimeout(() => {
            state.notifications = state.notifications.filter(n => n.id !== id);
            renderNotifications();
        }, ttl);
    }

    // ---------------------------------------------------------------------
    // Rendering functions – keep UI in sync with state
    // ---------------------------------------------------------------------
    function renderWalletStatus() {
        if (!DOM.walletBtn) return;
        DOM.walletBtn.textContent = state.wallet.connected ? 'Disconnect (' + state.wallet.address.slice(0, 6) + '…)': 'Connect Wallet';
    }

    function renderMarket() {
        if (!DOM.marketPrice || !DOM.marketChange) return;
        const fmt = new Intl.NumberFormat('en-US', { style: 'currency', currency: state.settings.currency });
        DOM.marketPrice.textContent = fmt.format(state.market.price);
        const change = state.market.change24h.toFixed(2);
        DOM.marketChange.textContent = (state.market.change24h >= 0 ? '+' : '') + change + '%';
        DOM.marketChange.style.color = state.market.change24h >= 0 ? '#4caf50' : '#e53935';
    }

    function renderGas() {
        if (!DOM.gasSelect) return;
        const options = ['slow', 'standard', 'fast'];
        DOM.gasSelect.innerHTML = '';
        options.forEach(opt => {
            const value = state.gas[opt];
            const el = document.createElement('option');
            el.value = value;
            el.textContent = `${opt.charAt(0).toUpperCase() + opt.slice(1)} (${value} ${state.gas.unit})`;
            if (value === state.gas.current) el.selected = true;
            DOM.gasSelect.appendChild(el);
        });
    }

    function renderOrderBook() {
        if (!DOM.orderBookBids || !DOM.orderBookAsks) return;
        const { bids, asks, maxDepth } = state.orderBook;
        DOM.orderBookBids.innerHTML = '';
        DOM.orderBookAsks.innerHTML = '';
        bids.slice(0, maxDepth).forEach(b => {
            const row = document.createElement('tr');
            row.innerHTML = `<td>${b.price.toFixed(2)}</td><td>${b.amount}</td>`;
            DOM.orderBookBids.appendChild(row);
        });
        asks.slice(0, maxDepth).forEach(a => {
            const row = document.createElement('tr');
            row.innerHTML = `<td>${a.price.toFixed(2)}</td><td>${a.amount}</td>`;
            DOM.orderBookAsks.appendChild(row);
        });
    }

    function renderTransactions() {
        if (!DOM.txList) return;
        DOM.txList.innerHTML = '';
        state.transactions.slice().reverse().forEach(tx => {
            const li = document.createElement('li');
            li.className = 'tx-item ' + tx.status.toLowerCase();
            li.textContent = `[${new Date(tx.timestamp).toLocaleTimeString()}] ${tx.type}: ${tx.description} (${tx.status})`;
            DOM.txList.appendChild(li);
        });
    }

    function renderPortfolio() {
        if (!DOM.portfolioTable) return;
        const tbody = DOM.portfolioTable.querySelector('tbody');
        if (!tbody) return;
        tbody.innerHTML = '';
        state.portfolio.forEach(p => {
            const row = document.createElement('tr');
            const fmt = new Intl.NumberFormat('en-US', { style: 'currency', currency: state.settings.currency });
            row.innerHTML = `
                <td>${p.symbol}</td>
                <td>${p.balance.toLocaleString(undefined, {minimumFractionDigits: 2, maximumFractionDigits: 6})}</td>
                <td>${fmt.format(p.price)}</td>
                <td>${fmt.format(p.value)}</td>
                <td>${p.allocation.toFixed(1)}%</td>
            `;
            tbody.appendChild(row);
        });
    }

    function renderStaking() {
        if (!DOM.stakeInfo) return;
        const { stakedOpus, rewardRateApy, pendingRewards, lastClaimed } = state.staking;
        const fmt = new Intl.NumberFormat('en-US', { style: 'currency', currency: state.settings.currency });
        DOM.stakeInfo.innerHTML = `
            <p>Staked: ${stakedOpus.toLocaleString()} OPUS</p>
            <p>APY: ${rewardRateApy}%</p>
            <p>Pending Rewards: ${pendingRewards.toFixed(4)} OPUS (${fmt.format(pendingRewards * PAIR_RATES['OPUS/USDT'].price)})</p>
            <p>Last Claimed: ${new Date(lastClaimed).toLocaleString()}</p>
        `;
    }

    function renderNotifications() {
        if (!DOM.notificationArea) return;
        DOM.notificationArea.innerHTML = '';
        state.notifications.forEach(n => {
            const div = document.createElement('div');
            div.className = `notification ${n.type}`;
            div.textContent = n.message;
            DOM.notificationArea.appendChild(div);
        });
    }

    // ---------------------------------------------------------------------
    // Mock data generators – replace with real API calls in production
    // ---------------------------------------------------------------------
    function mockMarketUpdate() {
        const pair = PAIR_RATES[state.market.selectedPair];
        // simulate small random walk
        const delta = (Math.random() - 0.5) * 0.02 * pair.price;
        state.market.price = Math.max(pair.price * 0.5, pair.price + delta);
        state.market.change24h = ((state.market.price - pair.price) / pair.price) * 100;
        state.market.volume24h = Math.round(state.market.volume24h * (0.95 + Math.random() * 0.1));
        state.market.high24h = Math.max(state.market.high24h, state.market.price);
        state.market.low24h = Math.min(state.market.low24h, state.market.price);
        // push a dummy candle for chart (timestamp, open, high, low, close)
        const now = Date.now();
        const candle = {
            time: now,
            open: state.market.price - delta,
            high: state.market.price + Math.abs(delta) * 0.5,
            low: state.market.price - Math.abs(delta) * 0.5,
            close: state.market.price
        };
        state.market.chartData.candles.push(candle);
        if (state.market.chartData.candles.length > 100) state.market.chartData.candles.shift();
    }

    function mockGasUpdate() {
        // random jitter around standard
        const jitter = Math.floor(Math.random() * 5) - 2; // -2..+2
        state.gas.slow = Math.max(5, state.gas.standard - 6 + jitter);
        state.gas.standard = Math.max(10, state.gas.standard + jitter);
        state.gas.fast = Math.max(15, state.gas.standard + 6 + jitter);
        // keep current within bounds
        if (state.gas.current < state.gas.slow) state.gas.current = state.gas.slow;
        if (state.gas.current > state.gas.fast) state.gas.current = state.gas.fast;
    }

    function mockOrderBookUpdate() {
        const depth = state.orderBook.maxDepth;
        const basePrice = state.market.price;
        const spread = basePrice * 0.001; // 0.1% spread
        const bids = [];
        const asks = [];
        for (let i = 0; i < depth; i++) {
            const priceBid = basePrice - spread * (i + 1) - Math.random() * spread;
            const priceAsk = basePrice + spread * (i + 1) + Math.random() * spread;
            bids.push({ price: priceBid, amount: (Math.random() * 5).toFixed(4) });
            asks.push({ price: priceAsk, amount: (Math.random() * 5).toFixed(4) });
        }
        state.orderBook.bids = bids;
        state.orderBook.asks = asks;
    }

    function mockStakingUpdate() {
        // accrue rewards based on APY and time elapsed since last claim
        const now = Date.now();
        const seconds = (now - state.staking.lastClaimed) / 1000;
        const yearlySeconds = 365 * 24 * 60 * 60;
        const accrued = state.staking.stakedOpus * (state.staking.rewardRateApy / 100) * (seconds / yearlySeconds);
        state.staking.pendingRewards += accrued;
        // simulate occasional claim (10% chance per tick)
        if (Math.random() < 0.1) {
            state.staking.stakedOpus += state.staking.pendingRewards;
            state.staking.pendingRewards = 0;
            state.staking.lastClaimed = now;
            addNotification('Staking rewards auto‑claimed', 'success');
        }
    }

    // ---------------------------------------------------------------------
    // Interval management – start/stop tickers based on settings
    // ---------------------------------------------------------------------
    function startTickers() {
        const interval = state.settings.autoRefreshInterval;
        marketInterval = setInterval(() => { mockMarketUpdate(); renderMarket(); }, interval);
        gasInterval = setInterval(() => { mockGasUpdate(); renderGas(); }, interval * 2);
        orderBookInterval = setInterval(() => { mockOrderBookUpdate(); renderOrderBook(); }, interval * 3);
        stakingInterval = setInterval(() => { mockStakingUpdate(); renderStaking(); }, interval * 5);
    }

    function stopTickers() {
        clearInterval(marketInterval);
        clearInterval(gasInterval);
        clearInterval(orderBookInterval);
        clearInterval(stakingInterval);
    }

    // ---------------------------------------------------------------------
    // Public API – expose for debugging / external modules
    // ---------------------------------------------------------------------
    window.MagnumOpus = {
        state,
        playTone,
        addNotification,
        renderAll: function () {
            renderWalletStatus();
            renderMarket();
            renderGas();
            renderOrderBook();
            renderTransactions();
            renderPortfolio();
            renderStaking();
            renderNotifications();
        }
    };

    // ---------------------------------------------------------------------
    // Bootstrap – run once DOM is ready
    // ---------------------------------------------------------------------
    document.addEventListener('DOMContentLoaded', () => {
        initDOM();
        bindEvents();
        renderAll();
        startTickers();
    });

    // Helper to render everything in correct order
    function renderAll() {
        window.MagnumOpus.renderAll();
    }

    // Graceful shutdown – stop intervals when page unloads
    window.addEventListener('beforeunload', stopTickers);

})();