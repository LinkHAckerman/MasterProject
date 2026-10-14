/**
 * MAGNUM OPUS // Web3 & DeFi Nexus Engine - Core Dashboard Application Logic
 * High-performance interactive dashboard engine with real-time data feeds,
 * simulated wallet interactions, orderbook engine, and smart contract event listeners.
 */

(function () {
    'use strict';

    // State Store
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
                { symbol: 'ETH', name: 'Ethereum', balance: 14.852, decimals: 18 },
                { symbol: 'USDT', name: 'Tether USD', balance: 42500.00, decimals: 6 },
                { symbol: 'BTC', name: 'Bitcoin', balance: 0.65, decimals: 8 },
                { symbol: 'SOL', name: 'Solana', balance: 12.5, decimals: 9 },
                { symbol: 'OPUS', name: 'Magnum Opus Governance', balance: 10000.0, decimals: 18 }
            ]
        },
        gas: {
            slow: 12,
            standard: 18,
            fast: 24,
            current: 18
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
                prices: []
            }
        },
        orderBook: {
            bids: [],
            asks: [],
            maxDepth: 12
        },
        transactions: [],
        portfolio: [
            { symbol: 'ETH', name: 'Ethereum', balance: 14.852, price: 3450.75, value: 51249.54, allocation: 53.8 },
            { symbol: 'BTC', name: 'Bitcoin', balance: 0.65, price: 64200.00, value: 41730.00, allocation: 43.8 },
            { symbol: 'SOL', name: 'Solana', balance: 12.5, price: 145.20, value: 1815.00, allocation: 1.9 },
            { symbol: 'OPUS', name: 'Magnum Opus', balance: 1000.0, price: 0.45, value: 450.00, allocation: 0.5 }
        ],
        staking: {
            stakedOpus: 2500.0,
            rewardRateApy: 18.5,
            pendingRewards: 14.82
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

    // Pair exchange rates dictionary
    const PAIR_RATES = {
        'ETH/USDT': { base: 'ETH', quote: 'USDT', price: 3450.75, decimals: 2 },
        'BTC/USDT': { base: 'BTC', quote: 'USDT', price: 64200.00, decimals: 2 },
        'SOL/USDT': { base: 'SOL', quote: 'USDT', price: 145.20, decimals: 2 },
        'OPUS/USDT': { base: 'OPUS', quote: 'USDT', price: 0.45, decimals: 4 },
        'ETH/BTC': { base: 'ETH', quote: 'BTC', price: 0.0537, decimals: 6 }
    };

    // DOM Elements Cache
    let DOM = {};

    // Chart instance
    let priceChart = null;

    // Tickers & intervals
    let marketInterval = null;
    let gasInterval = null;
    let orderBookInterval = null;

    // Audio context for sound effects
    let audioCtx = null;

    /**
     * Initialization
     */
    function init() {
        loadPersistedSettings();
        initDOM();
        initChartData();
        setupEventListeners();
        initializeChart();
        populateOrderBook();
        renderOrderBook();
        renderPortfolio();
        renderTransactions();
        updateUI();
        startSimulationEngines();
        setupWeb3Listeners();

        addNotification('System Initialized', 'Magnum Opus Web3 & DeFi Nexus Engine is live.', 'info');
    }

    function loadPersistedSettings() {
        try {
            const saved = localStorage.getItem('magnum_opus_settings');
            if (saved) {
                Object.assign(state.settings, JSON.parse(saved));
            }
        } catch (e) {
            console.warn('Could not read settings from localStorage', e);
        }
    }

    function saveSettingsToStorage() {
        try {
            localStorage.setItem('magnum_opus_settings', JSON.stringify(state.settings));
        } catch (e) {
            console.warn('Could not persist settings', e);
        }
    }

    function initDOM() {
        DOM = {
            connectBtn: document.getElementById('connect-wallet-btn'),
            walletAddress: document.getElementById('wallet-address-display'),
            walletBalance: document.getElementById('wallet-balance-display'),
            gasPrice: document.getElementById('gas-price-display'),
            pairSelect: document.getElementById('pair-select'),
            currentPrice: document.getElementById('current-price-display'),
            priceChange: document.getElementById('price-change-display'),
            orderBookAsks: document.getElementById('orderbook-asks'),
            orderBookBids: document.getElementById('orderbook-bids'),
            transactionList: document.getElementById('transaction-list'),
            notificationContainer: document.getElementById('notification-container'),
            portfolioList: document.getElementById('portfolio-list'),
            chartContainer: document.getElementById('price-chart-container')
        };
    }

    function initChartData() {
        const now = new Date();
        for (let i = 30; i >= 0; i--) {
            const time = new Date(now.getTime() - i * 60000);
            state.market.chartData.labels.push(time.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }));
            state.market.chartData.prices.push(state.market.price * (1 + (Math.random() * 0.02 - 0.01)));
        }
    }

    function setupEventListeners() {
        if (DOM.connectBtn) {
            DOM.connectBtn.addEventListener('click', toggleWalletConnection);
        }
        if (DOM.pairSelect) {
            DOM.pairSelect.addEventListener('change', (e) => {
                state.market.selectedPair = e.target.value;
                updateMarketData();
            });
        }
    }

    function initializeChart() {
        const ctx = document.createElement('canvas');
        if (DOM.chartContainer) {
            DOM.chartContainer.appendChild(ctx);
            // In a real app, we would use Chart.js here. 
            // For this architecture, we simulate the visual update.
            console.log('Chart initialized for', state.market.selectedPair);
        }
    }

    function populateOrderBook() {
        // Generate initial mock orderbook
        for (let i = 0; i < state.orderBook.maxDepth; i++) {
            const askPrice = state.market.price * (1 + (i * 0.001) + 0.001);
            const bidPrice = state.market.price * (1 - (i * 0.001) - 0.001);
            state.orderBook.asks.push({ price: askPrice, amount: Math.random() * 2 });
            state.orderBook.bids.push({ price: bidPrice, amount: Math.random() * 2 });
        }
        state.orderBook.asks.sort((a, b) => a.price - b.price);
        state.orderBook.bids.sort((a, b) => b.price - a.price);
    }

    function renderOrderBook() {
        if (!DOM.orderBookAsks || !DOM.orderBookBids) return;

        DOM.orderBookAsks.innerHTML = state.orderBook.asks.map(ask => `
            <div class="order-row ask">
                <span class="price">${ask.price.toFixed(2)}</span>
                <span class="amount">${ask.amount.toFixed(4)}</span>
            </div>
        `).join('');

        DOM.orderBookBids.innerHTML = state.orderBook.bids.map(bid => `
            <div class="order-row bid">
                <span class="price">${bid.price.toFixed(2)}</span>
                <span class="amount">${bid.amount.toFixed(4)}</span>
            </div>
        `).join('');
    }

    function renderPortfolio() {
        if (!DOM.portfolioList) return;
        DOM.portfolioList.innerHTML = state.portfolio.map(item => `
            <div class="portfolio-item">
                <div class="item-info">
                    <span class="symbol">${item.symbol}</span>
                    <span class="name">${item.name}</span>
                </div>
                <div class="item-values">
                    <span class="balance">${item.balance.toFixed(4)}</span>
                    <span class="value">$${item.value.toLocaleString()}</span>
                </div>
            </div>
        `).join('');
    }

    function renderTransactions() {
        if (!DOM.transactionList) return;
        DOM.transactionList.innerHTML = state.transactions.map(tx => `
            <div class="tx-row ${tx.type}">
                <span class="tx-time">${tx.time}</span>
                <span class="tx-hash">${tx.hash.substring(0, 8)}...</span>
                <span class="tx-status">${tx.status}</span>
                <span class="tx-amount">${tx.amount}</span>
            </div>
        `).join('');
    }

    function updateUI() {
        if (DOM.walletAddress) {
            DOM.walletAddress.textContent = state.wallet.connected ? state.wallet.address : 'Not Connected';
            DOM.walletAddress.classList.toggle('connected', state.wallet.connected);
        }
        if (DOM.walletBalance) {
            DOM.walletBalance.textContent = state.wallet.connected ? `${state.wallet.balanceEth} ETH` : '0.00 ETH';
        }
        if (DOM.currentPrice) {
            DOM.currentPrice.textContent = `$${state.market.price.toLocaleString()}`;
        }
        if (DOM.priceChange) {
            DOM.priceChange.textContent = `${state.market.change24h > 0 ? '+' : ''}${state.market.change24h}%`;
            DOM.priceChange.className = state.market.change24h >= 0 ? 'price-up' : 'price-down';
        }
        if (DOM.gasPrice) {
            DOM.gasPrice.textContent = `${state.gas.current} Gwei`;
        }
    }

    function startSimulationEngines() {
        // Market Price Fluctuation
        marketInterval = setInterval(() => {
            const volatility = 0.002;
            const change = 1 + (Math.random() * volatility * 2 - volatility);
            state.market.price *= change;
            state.market.chartData.prices.push(state.market.price);
            state.market.chartData.prices.shift();
            updateUI();
        }, 2000);

        // Gas Price Fluctuation
        gasInterval = setInterval(() => {
            state.gas.current = Math.max(10, Math.min(50, state.gas.current + (Math.floor(Math.random() * 3) - 1)));
            updateUI();
        }, 5000);

        // Orderbook Fluctuation
        orderBookInterval = setInterval(() => {
            state.orderBook.asks.forEach(ask => ask.amount = Math.max(0.1, ask.amount + (Math.random() * 0.2 - 0.1)));
            state.orderBook.bids.forEach(bid => bid.amount = Math.max(0.1, bid.amount + (Math.random() * 0.2 - 0.1)));
            renderOrderBook();
        }, 1500);
    }

    function toggleWalletConnection() {
        if (!state.wallet.connected) {
            state.wallet.connected = true;
            state.wallet.address = '0x' + Array.from({length: 40}, () => Math.floor(Math.random() * 16).toString(16)).join('');
            addNotification('Wallet Connected', `Connected to ${state.wallet.networkName}`, 'success');
        } else {
            state.wallet.connected = false;
            state.wallet.address = null;
            addNotification('Wallet Disconnected', 'Session ended.', 'warning');
        }
        updateUI();
    }

    function addNotification(title, message, type) {
        const id = Date.now();
        const notification = {
            id,
            title,
            message,
            type,
            time: new Date().toLocaleTimeString()
        };
        state.notifications.unshift(notification);
        if (DOM.notificationContainer) {
            const el = document.createElement('div');
            el.className = `notification notification-${type} animate-in`;
            el.id = `notif-${id}`;
            el.innerHTML = `
                <div class="notif-header"><strong>${title}</strong></div>
                <div class="notif-body">${message}</div>
            `;
            DOM.notificationContainer.prepend(el);
            setTimeout(() => {
                el.classList.add('animate-out');
                setTimeout(() => el.remove(), 500);
            }, 4000);
        }
    }

    function updateMarketData() {
        // Simulate fetching new pair data
        const pair = PAIR_RATES[state.market.selectedPair] || PAIR_RATES['ETH/USDT'];
        state.market.price = pair.price;
        addNotification('Market Switched', `Now viewing ${state.market.selectedPair}`, 'info');
        updateUI();
    }

    function setupWeb3Listeners() {
        // Mocking EIP-1193 provider events
        window.addEventListener('magnum:accountChanged', (e) => {
            state.wallet.address = e.detail.address;
            updateUI();
        });
    }

    // Run Application
    document.addEventListener('DOMContentLoaded', init);

})();