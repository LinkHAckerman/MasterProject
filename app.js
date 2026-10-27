/**
 * MAGNUM OPUS // Web3 & DeFi Nexus Engine - Core Dashboard Application Logic
 * High-performance interactive dashboard engine with real-time data feeds,
 * simulated wallet interactions, orderbook engine, canvas chart renderer,
 * DEX swap routing, yield staking, and Web Audio sound engine.
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

    // Engine Tickers
    let marketInterval = null;
    let gasInterval = null;
    let orderBookInterval = null;
    let stakingInterval = null;

    // Audio context for procedural Web Audio sound synthesis
    let audioCtx = null;

    /**
     * Web Audio Sound Synthesizer
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
            gain.gain.exponentialRampToValueAtTime(0.0001, audioCtx.currentTime + duration);
            osc.connect(gain);
            gain.connect(audioCtx.destination);
            osc.start(audioCtx.currentTime);
            osc.stop(audioCtx.currentTime + duration);
        } catch (error) {
            console.error('Audio synthesis failed:', error);
        }
    }

    /**
     * Initialize the application
     */
    function init() {
        // Cache DOM elements
        cacheDomElements();
        // Initialize UI components
        initUI();
        // Initialize event listeners
        initEventListeners();
        // Start engine tickers
        startEngineTickers();
        // Load initial data
        loadInitialData();
        // Initialize Web Audio context
        initAudioContext();
    }

    /**
     * Cache DOM elements for later use
     */
    function cacheDomElements() {
        DOM = {
            walletConnectBtn: document.getElementById('wallet-connect-btn'),
            walletAddress: document.getElementById('wallet-address'),
            walletBalanceEth: document.getElementById('wallet-balance-eth'),
            walletBalanceUsdt: document.getElementById('wallet-balance-usdt'),
            walletBalanceBtc: document.getElementById('wallet-balance-btc'),
            walletBalanceSol: document.getElementById('wallet-balance-sol'),
            marketPrice: document.getElementById('market-price'),
            marketChange24h: document.getElementById('market-change-24h'),
            marketVolume24h: document.getElementById('market-volume-24h'),
            marketHigh24h: document.getElementById('market-high-24h'),
            marketLow24h: document.getElementById('market-low-24h'),
            marketChart: document.getElementById('market-chart'),
            orderBookBids: document.getElementById('order-book-bids'),
            orderBookAsks: document.getElementById('order-book-asks'),
            transactionsList: document.getElementById('transactions-list'),
            portfolioList: document.getElementById('portfolio-list'),
            stakingStakedOpus: document.getElementById('staking-staked-opus'),
            stakingRewardRateApy: document.getElementById('staking-reward-rate-apy'),
            stakingPendingRewards: document.getElementById('staking-pending-rewards'),
            stakingLastClaimed: document.getElementById('staking-last-claimed'),
            notificationsList: document.getElementById('notifications-list'),
            settingsForm: document.getElementById('settings-form'),
            settingsTheme: document.getElementById('settings-theme'),
            settingsCurrency: document.getElementById('settings-currency'),
            settingsLanguage: document.getElementById('settings-language'),
            settingsSlippageTolerance: document.getElementById('settings-slippage-tolerance'),
            settingsEnableSounds: document.getElementById('settings-enable-sounds'),
            settingsAutoRefreshInterval: document.getElementById('settings-auto-refresh-interval')
        };
    }

    /**
     * Initialize UI components
     */
    function initUI() {
        // Initialize market chart
        initMarketChart();
        // Update UI with initial state
        updateUI();
    }

    /**
     * Initialize event listeners
     */
    function initEventListeners() {
        // Wallet connect button
        DOM.walletConnectBtn.addEventListener('click', connectWallet);
        // Settings form
        DOM.settingsForm.addEventListener('submit', saveSettings);
    }

    /**
     * Start engine tickers
     */
    function startEngineTickers() {
        // Market data ticker
        marketInterval = setInterval(updateMarketData, state.settings.autoRefreshInterval);
        // Gas price ticker
        gasInterval = setInterval(updateGasPrices, state.settings.autoRefreshInterval * 2);
        // Order book ticker
        orderBookInterval = setInterval(updateOrderBook, state.settings.autoRefreshInterval);
        // Staking ticker
        stakingInterval = setInterval(updateStakingData, state.settings.autoRefreshInterval * 3);
    }

    /**
     * Load initial data
     */
    function loadInitialData() {
        // Load market data
        updateMarketData();
        // Load gas prices
        updateGasPrices();
        // Load order book
        updateOrderBook();
        // Load transactions
        updateTransactions();
        // Load portfolio
        updatePortfolio();
        // Load staking data
        updateStakingData();
    }

    /**
     * Initialize Web Audio context
     */
    function initAudioContext() {
        try {
            audioCtx = new (window.AudioContext || window.webkitAudioContext)();
        } catch (error) {
            console.error('Web Audio API is not supported in this browser:', error);
        }
    }

    /**
     * Connect wallet
     */
    function connectWallet() {
        // Simulate wallet connection
        state.wallet.connected = true;
        state.wallet.address = '0x123...456';
        // Update UI
        updateUI();
        // Play sound
        playAudioTone(440, 'sine', 0.1, 0.1);
    }

    /**
     * Save settings
     */
    function saveSettings(event) {
        event.preventDefault();
        // Update state with form values
        state.settings.theme = DOM.settingsTheme.value;
        state.settings.currency = DOM.settingsCurrency.value;
        state.settings.language = DOM.settingsLanguage.value;
        state.settings.slippageTolerance = parseFloat(DOM.settingsSlippageTolerance.value);
        state.settings.enableSounds = DOM.settingsEnableSounds.checked;
        state.settings.autoRefreshInterval = parseInt(DOM.settingsAutoRefreshInterval.value);
        // Update UI
        updateUI();
        // Restart engine tickers with new interval
        clearInterval(marketInterval);
        clearInterval(gasInterval);
        clearInterval(orderBookInterval);
        clearInterval(stakingInterval);
        startEngineTickers();
        // Play sound
        playAudioTone(523.25, 'sine', 0.1, 0.1);
    }

    /**
     * Update UI with current state
     */
    function updateUI() {
        // Update wallet section
        updateWalletSection();
        // Update market section
        updateMarketSection();
        // Update order book section
        updateOrderBookSection();
        // Update transactions section
        updateTransactionsSection();
        // Update portfolio section
        updatePortfolioSection();
        // Update staking section
        updateStakingSection();
        // Update notifications section
        updateNotificationsSection();
        // Update settings form
        updateSettingsForm();
    }

    /**
     * Update wallet section
     */
    function updateWalletSection() {
        if (state.wallet.connected) {
            DOM.walletConnectBtn.textContent = 'Disconnect';
            DOM.walletAddress.textContent = state.wallet.address;
            DOM.walletBalanceEth.textContent = state.wallet.balanceEth.toFixed(4);
            DOM.walletBalanceUsdt.textContent = state.wallet.balanceUsdt.toFixed(2);
            DOM.walletBalanceBtc.textContent = state.wallet.balanceBtc.toFixed(6);
            DOM.walletBalanceSol.textContent = state.wallet.balanceSol.toFixed(2);
        } else {
            DOM.walletConnectBtn.textContent = 'Connect Wallet';
            DOM.walletAddress.textContent = 'Not connected';
            DOM.walletBalanceEth.textContent = '0.0000';
            DOM.walletBalanceUsdt.textContent = '0.00';
            DOM.walletBalanceBtc.textContent = '0.000000';
            DOM.walletBalanceSol.textContent = '0.00';
        }
    }

    /**
     * Update market section
     */
    function updateMarketSection() {
        DOM.marketPrice.textContent = state.market.price.toFixed(2);
        DOM.marketChange24h.textContent = state.market.change24h.toFixed(2) + '%';
        DOM.marketVolume24h.textContent = formatNumber(state.market.volume24h);
        DOM.marketHigh24h.textContent = state.market.high24h.toFixed(2);
        DOM.marketLow24h.textContent = state.market.low24h.toFixed(2);
        // Update market chart
        updateMarketChart();
    }

    /**
     * Update order book section
     */
    function updateOrderBookSection() {
        // Clear order book
        DOM.orderBookBids.innerHTML = '';
        DOM.orderBookAsks.innerHTML = '';
        // Add bids
        state.orderBook.bids.forEach(bid => {
            const bidElement = document.createElement('div');
            bidElement.className = 'order-book-item';
            bidElement.innerHTML = `
                <span class="order-book-price">${bid.price.toFixed(2)}</span>
                <span class="order-book-amount">${bid.amount.toFixed(4)}</span>
                <span class="order-book-total">${bid.total.toFixed(4)}</span>
            `;
            DOM.orderBookBids.appendChild(bidElement);
        });
        // Add asks
        state.orderBook.asks.forEach(ask => {
            const askElement = document.createElement('div');
            askElement.className = 'order-book-item';
            askElement.innerHTML = `
                <span class="order-book-price">${ask.price.toFixed(2)}</span>
                <span class="order-book-amount">${ask.amount.toFixed(4)}</span>
                <span class="order-book-total">${ask.total.toFixed(4)}</span>
            `;
            DOM.orderBookAsks.appendChild(askElement);
        });
    }

    /**
     * Update transactions section
     */
    function updateTransactionsSection() {
        // Clear transactions list
        DOM.transactionsList.innerHTML = '';
        // Add transactions
        state.transactions.forEach(transaction => {
            const transactionElement = document.createElement('div');
            transactionElement.className = 'transaction-item';
            transactionElement.innerHTML = `
                <span class="transaction-hash">${transaction.hash}</span>
                <span class="transaction-type">${transaction.type}</span>
                <span class="transaction-description">${transaction.description}</span>
                <span class="transaction-amount">${transaction.amount}</span>
                <span class="transaction-status">${transaction.status}</span>
                <span class="transaction-timestamp">${new Date(transaction.timestamp).toLocaleString()}</span>
                <span class="transaction-block-number">${transaction.blockNumber}</span>
            `;
            DOM.transactionsList.appendChild(transactionElement);
        });
    }

    /**
     * Update portfolio section
     */
    function updatePortfolioSection() {
        // Clear portfolio list
        DOM.portfolioList.innerHTML = '';
        // Add portfolio items
        state.portfolio.forEach(item => {
            const portfolioItemElement = document.createElement('div');
            portfolioItemElement.className = 'portfolio-item';
            portfolioItemElement.innerHTML = `
                <span class="portfolio-symbol">${item.symbol}</span>
                <span class="portfolio-name">${item.name}</span>
                <span class="portfolio-balance">${item.balance.toFixed(4)}</span>
                <span class="portfolio-price">${item.price.toFixed(2)}</span>
                <span class="portfolio-value">${item.value.toFixed(2)}</span>
                <span class="portfolio-allocation">${item.allocation.toFixed(1)}%</span>
            `;
            DOM.portfolioList.appendChild(portfolioItemElement);
        });
    }

    /**
     * Update staking section
     */
    function updateStakingSection() {
        DOM.stakingStakedOpus.textContent = state.staking.stakedOpus.toFixed(2);
        DOM.stakingRewardRateApy.textContent = state.staking.rewardRateApy.toFixed(2) + '%';
        DOM.stakingPendingRewards.textContent = state.staking.pendingRewards.toFixed(2);
        DOM.stakingLastClaimed.textContent = new Date(state.staking.lastClaimed).toLocaleString();
    }

    /**
     * Update notifications section
     */
    function updateNotificationsSection() {
        // Clear notifications list
        DOM.notificationsList.innerHTML = '';
        // Add notifications
        state.notifications.forEach(notification => {
            const notificationElement = document.createElement('div');
            notificationElement.className = 'notification-item';
            notificationElement.innerHTML = `
                <span class="notification-message">${notification.message}</span>
                <span class="notification-timestamp">${new Date(notification.timestamp).toLocaleString()}</span>
            `;
            DOM.notificationsList.appendChild(notificationElement);
        });
    }

    /**
     * Update settings form
     */
    function updateSettingsForm() {
        DOM.settingsTheme.value = state.settings.theme;
        DOM.settingsCurrency.value = state.settings.currency;
        DOM.settingsLanguage.value = state.settings.language;
        DOM.settingsSlippageTolerance.value = state.settings.slippageTolerance;
        DOM.settingsEnableSounds.checked = state.settings.enableSounds;
        DOM.settingsAutoRefreshInterval.value = state.settings.autoRefreshInterval;
    }

    /**
     * Initialize market chart
     */
    function initMarketChart() {
        // Initialize chart data
        state.market.chartData.labels = Array.from({ length: 60 }, (_, i) => i);
        state.market.chartData.prices = Array.from({ length: 60 }, () => state.market.price);
        state.market.chartData.candles = Array.from({ length: 60 }, () => ({
            open: state.market.price,
            high: state.market.price,
            low: state.market.price,
            close: state.market.price
        }));
        // Draw initial chart
        drawMarketChart();
    }

    /**
     * Update market chart
     */
    function updateMarketChart() {
        // Update chart data
        state.market.chartData.labels.push(state.market.chartData.labels.length);
        state.market.chartData.prices.push(state.market.price);
        state.market.chartData.candles.push({
            open: state.market.price,
            high: state.market.price,
            low: state.market.price,
            close: state.market.price
        });
        // Keep chart data length within limits
        if (state.market.chartData.labels.length > 60) {
            state.market.chartData.labels.shift();
            state.market.chartData.prices.shift();
            state.market.chartData.candles.shift();
        }
        // Draw chart
        drawMarketChart();
    }

    /**
     * Draw market chart
     */
    function drawMarketChart() {
        const ctx = DOM.marketChart.getContext('2d');
        const width = DOM.marketChart.width;
        const height = DOM.marketChart.height;
        const padding = 20;
        const chartWidth = width - padding * 2;
        const chartHeight = height - padding * 2;

        // Clear canvas
        ctx.clearRect(0, 0, width, height);

        // Draw grid
        ctx.strokeStyle = '#333';
        ctx.lineWidth = 1;
        ctx.beginPath();
        for (let i = 0; i <= 5; i++) {
            const y = padding + (chartHeight / 5) * i;
            ctx.moveTo(padding, y);
            ctx.lineTo(width - padding, y);
        }
        for (let i = 0; i <= 10; i++) {
            const x = padding + (chartWidth / 10) * i;
            ctx.moveTo(x, padding);
            ctx.lineTo(x, height - padding);
        }
        ctx.stroke();

        // Draw chart
        ctx.strokeStyle = '#4f46e5';
        ctx.lineWidth = 2;
        ctx.beginPath();
        const minPrice = Math.min(...state.market.chartData.prices);
        const maxPrice = Math.max(...state.market.chartData.prices);
        const priceRange = maxPrice - minPrice;
        state.market.chartData.prices.forEach((price, index) => {
            const x = padding + (chartWidth / (state.market.chartData.prices.length - 1)) * index;
            const y = height - padding - ((price - minPrice) / priceRange) * chartHeight;
            if (index === 0) {
                ctx.moveTo(x, y);
            } else {
                ctx.lineTo(x, y);
            }
        });
        ctx.stroke();
    }

    /**
     * Update market data
     */
    function updateMarketData() {
        // Simulate market data update
        const pair = PAIR_RATES[state.market.selectedPair];
        const change = (Math.random() - 0.5) * 0.1;
        state.market.price = pair.price * (1 + change);
        state.market.change24h = change * 100;
        state.market.volume24h += Math.random() * 1000000;
        state.market.high24h = Math.max(state.market.high24h, state.market.price);
        state.market.low24h = Math.min(state.market.low24h, state.market.price);
        // Update UI
        updateUI();
    }

    /**
     * Update gas prices
     */
    function updateGasPrices() {
        // Simulate gas price update
        state.gas.slow = Math.max(10, state.gas.slow + (Math.random() - 0.5) * 2);
        state.gas.standard = Math.max(15, state.gas.standard + (Math.random() - 0.5) * 3);
        state.gas.fast = Math.max(20, state.gas.fast + (Math.random() - 0.5) * 4);
        state.gas.current = state.gas.standard;
        // Update UI
        updateUI();
    }

    /**
     * Update order book
     */
    function updateOrderBook() {
        // Simulate order book update
        state.orderBook.bids = [];
        state.orderBook.asks = [];
        const pair = PAIR_RATES[state.market.selectedPair];
        const basePrice = pair.price;
        const decimals = pair.decimals;
        // Generate bids
        for (let i = 0; i < state.orderBook.maxDepth; i++) {
            const price = basePrice - (i * 0.01);
            const amount = Math.random() * 10;
            const total = price * amount;
            state.orderBook.bids.push({ price, amount, total });
        }
        // Generate asks
        for (let i = 0; i < state.orderBook.maxDepth; i++) {
            const price = basePrice + (i * 0.01);
            const amount = Math.random() * 10;
            const total = price * amount;
            state.orderBook.asks.push({ price, amount, total });
        }
        // Update UI
        updateUI();
    }

    /**
     * Update transactions
     */
    function updateTransactions() {
        // Simulate transactions update
        // Update UI
        updateUI();
    }

    /**
     * Update portfolio
     */
    function updatePortfolio() {
        // Simulate portfolio update
        // Update UI
        updateUI();
    }

    /**
     * Update staking data
     */
    function updateStakingData() {
        // Simulate staking data update
        state.staking.pendingRewards += state.staking.stakedOpus * (state.staking.rewardRateApy / 100 / 365);
        // Update UI
        updateUI();
    }

    /**
     * Format number with commas
     */
    function formatNumber(num) {
        return num.toString().replace(/(\d)(?=(\d{3})+(?!\d))/g, '$1,');
    }

    // Initialize the application
    init();
})();
