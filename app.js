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
     * Play a short tone for UI feedback
     * @param {number} frequency - Tone frequency in Hz
     * @param {number} duration - Tone duration in milliseconds
     */
    function playTone(frequency, duration) {
        if (!state.settings.enableSounds) return;

        if (!audioCtx) {
            audioCtx = new (window.AudioContext || window.webkitAudioContext)();
        }

        const oscillator = audioCtx.createOscillator();
        const gainNode = audioCtx.createGain();

        oscillator.connect(gainNode);
        gainNode.connect(audioCtx.destination);

        oscillator.type = 'sine';
        oscillator.frequency.value = frequency;

        gainNode.gain.setValueAtTime(0, audioCtx.currentTime);
        gainNode.gain.linearRampToValueAtTime(0.1, audioCtx.currentTime + 0.01);
        gainNode.gain.linearRampToValueAtTime(0, audioCtx.currentTime + duration / 1000);

        oscillator.start();
        oscillator.stop(audioCtx.currentTime + duration / 1000);
    }

    // ---------------------------------------------------------------------
    // Utility Functions
    // ---------------------------------------------------------------------

    /**
     * Format a number as currency
     * @param {number} value - The value to format
     * @param {string} currency - The currency symbol
     * @param {number} decimals - Number of decimal places
     * @returns {string} Formatted currency string
     */
    function formatCurrency(value, currency = state.settings.currency, decimals = 2) {
        return new Intl.NumberFormat('en-US', {
            style: 'currency',
            currency: currency,
            minimumFractionDigits: decimals,
            maximumFractionDigits: decimals
        }).format(value);
    }

    /**
     * Format a number with thousands separators
     * @param {number} value - The value to format
     * @param {number} decimals - Number of decimal places
     * @returns {string} Formatted number string
     */
    function formatNumber(value, decimals = 2) {
        return new Intl.NumberFormat('en-US', {
            minimumFractionDigits: decimals,
            maximumFractionDigits: decimals
        }).format(value);
    }

    /**
     * Format a timestamp as a relative time string
     * @param {number} timestamp - The timestamp to format
     * @returns {string} Formatted relative time string
     */
    function formatRelativeTime(timestamp) {
        const now = Date.now();
        const diff = now - timestamp;

        if (diff < 60000) {
            return `${Math.floor(diff / 1000)} seconds ago`;
        } else if (diff < 3600000) {
            return `${Math.floor(diff / 60000)} minutes ago`;
        } else if (diff < 86400000) {
            return `${Math.floor(diff / 3600000)} hours ago`;
        } else {
            return `${Math.floor(diff / 86400000)} days ago`;
        }
    }

    /**
     * Generate a random transaction hash
     * @returns {string} Random transaction hash
     */
    function generateTxHash() {
        return '0x' + Array.from({ length: 64 }, () => Math.floor(Math.random() * 16).toString(16)).join('');
    }

    // ---------------------------------------------------------------------
    // Wallet Functions
    // ---------------------------------------------------------------------

    /**
     * Connect to a wallet
     */
    async function connectWallet() {
        // Simulate wallet connection
        state.wallet.connected = true;
        state.wallet.address = '0x' + Array.from({ length: 40 }, () => Math.floor(Math.random() * 16).toString(16)).join('');

        // Update UI
        DOM.connectWalletBtn.textContent = 'Disconnect Wallet';
        DOM.walletAddress.textContent = `${state.wallet.address.slice(0, 6)}...${state.wallet.address.slice(-4)}`;
        DOM.walletBalance.textContent = formatCurrency(state.wallet.balanceEth * PAIR_RATES['ETH/USDT'].price);

        // Play connection sound
        playTone(880, 200);

        // Add notification
        addNotification('Wallet connected successfully', 'success');
    }

    /**
     * Disconnect from a wallet
     */
    function disconnectWallet() {
        state.wallet.connected = false;
        state.wallet.address = null;

        // Update UI
        DOM.connectWalletBtn.textContent = 'Connect Wallet';
        DOM.walletAddress.textContent = 'Not connected';
        DOM.walletBalance.textContent = '$0.00';

        // Play disconnection sound
        playTone(440, 200);

        // Add notification
        addNotification('Wallet disconnected', 'info');
    }

    // ---------------------------------------------------------------------
    // Market Functions
    // ---------------------------------------------------------------------

    /**
     * Update market data
     */
    function updateMarketData() {
        const pair = state.market.selectedPair;
        const rate = PAIR_RATES[pair];

        // Simulate market data changes
        const change = (Math.random() - 0.5) * 0.01;
        state.market.price = rate.price * (1 + change);
        state.market.change24h = change * 100;
        state.market.volume24h = Math.floor(Math.random() * 1000000000);
        state.market.high24h = Math.max(state.market.high24h, state.market.price);
        state.market.low24h = Math.min(state.market.low24h, state.market.price);

        // Update UI
        DOM.marketPrice.textContent = formatCurrency(state.market.price);
        DOM.marketChange.textContent = `${state.market.change24h > 0 ? '+' : ''}${state.market.change24h.toFixed(2)}%`;
        DOM.marketChange.className = state.market.change24h > 0 ? 'positive' : 'negative';
        DOM.marketVolume.textContent = formatNumber(state.market.volume24h);
        DOM.marketHigh.textContent = formatCurrency(state.market.high24h);
        DOM.marketLow.textContent = formatCurrency(state.market.low24h);

        // Update chart data
        updateChartData();
    }

    /**
     * Update chart data
     */
    function updateChartData() {
        const now = Date.now();
        const labels = state.market.chartData.labels;
        const prices = state.market.chartData.prices;

        // Add new data point
        labels.push(now);
        prices.push(state.market.price);

        // Keep only the last 60 data points
        if (labels.length > 60) {
            labels.shift();
            prices.shift();
        }

        // Update chart
        renderChart();
    }

    /**
     * Render the chart
     */
    function renderChart() {
        const canvas = DOM.marketChart;
        const ctx = canvas.getContext('2d');
        const width = canvas.width;
        const height = canvas.height;

        // Clear canvas
        ctx.clearRect(0, 0, width, height);

        // Draw grid
        ctx.strokeStyle = '#1e293b';
        ctx.lineWidth = 1;

        for (let i = 0; i < 5; i++) {
            const y = (i / 4) * height;
            ctx.beginPath();
            ctx.moveTo(0, y);
            ctx.lineTo(width, y);
            ctx.stroke();
        }

        // Draw chart
        if (state.market.chartData.prices.length > 1) {
            ctx.strokeStyle = state.market.change24h > 0 ? '#10b981' : '#ef4444';
            ctx.lineWidth = 2;

            ctx.beginPath();
            const prices = state.market.chartData.prices;
            const minPrice = Math.min(...prices);
            const maxPrice = Math.max(...prices);

            for (let i = 0; i < prices.length; i++) {
                const x = (i / (prices.length - 1)) * width;
                const y = height - ((prices[i] - minPrice) / (maxPrice - minPrice)) * height;

                if (i === 0) {
                    ctx.moveTo(x, y);
                } else {
                    ctx.lineTo(x, y);
                }
            }

            ctx.stroke();
        }
    }

    // ---------------------------------------------------------------------
    // Order Book Functions
    // ---------------------------------------------------------------------

    /**
     * Update order book data
     */
    function updateOrderBook() {
        const bids = state.orderBook.bids;
        const asks = state.orderBook.asks;

        // Clear existing orders
        bids.length = 0;
        asks.length = 0;

        // Generate new orders
        const basePrice = state.market.price;
        const maxDepth = state.orderBook.maxDepth;

        for (let i = 0; i < maxDepth; i++) {
            const bidPrice = basePrice * (1 - (i / maxDepth) * 0.05);
            const askPrice = basePrice * (1 + (i / maxDepth) * 0.05);
            const bidAmount = Math.random() * 10;
            const askAmount = Math.random() * 10;

            bids.push({ price: bidPrice, amount: bidAmount });
            asks.push({ price: askPrice, amount: askAmount });
        }

        // Sort orders
        bids.sort((a, b) => b.price - a.price);
        asks.sort((a, b) => a.price - b.price);

        // Update UI
        renderOrderBook();
    }

    /**
     * Render the order book
     */
    function renderOrderBook() {
        const bids = state.orderBook.bids;
        const asks = state.orderBook.asks;
        const maxDepth = state.orderBook.maxDepth;

        // Clear existing rows
        DOM.orderBookBids.innerHTML = '';
        DOM.orderBookAsks.innerHTML = '';

        // Add new rows
        for (let i = 0; i < maxDepth; i++) {
            const bid = bids[i] || { price: 0, amount: 0 };
            const ask = asks[i] || { price: 0, amount: 0 };

            const bidRow = document.createElement('tr');
            bidRow.innerHTML = `
                <td>${formatCurrency(bid.price)}</td>
                <td>${formatNumber(bid.amount)}</td>
                <td class="order-book-bar">
                    <div class="order-book-bar-fill" style="width: ${bid.amount * 10}%"></div>
                </td>
            `;
            DOM.orderBookBids.appendChild(bidRow);

            const askRow = document.createElement('tr');
            askRow.innerHTML = `
                <td>${formatCurrency(ask.price)}</td>
                <td>${formatNumber(ask.amount)}</td>
                <td class="order-book-bar">
                    <div class="order-book-bar-fill" style="width: ${ask.amount * 10}%"></div>
                </td>
            `;
            DOM.orderBookAsks.appendChild(askRow);
        }
    }

    // ---------------------------------------------------------------------
    // Transaction Functions
    // ---------------------------------------------------------------------

    /**
     * Add a new transaction
     * @param {string} type - Transaction type
     * @param {string} description - Transaction description
     * @param {string} amount - Transaction amount
     */
    function addTransaction(type, description, amount) {
        const tx = {
            hash: generateTxHash(),
            type: type,
            description: description,
            amount: amount,
            status: 'Pending',
            timestamp: Date.now(),
            blockNumber: null
        };

        state.transactions.unshift(tx);

        // Update UI
        renderTransactions();

        // Simulate transaction confirmation
        setTimeout(() => {
            tx.status = 'Confirmed';
            tx.blockNumber = Math.floor(Math.random() * 10000000);
            renderTransactions();

            // Play confirmation sound
            playTone(660, 200);
        }, 5000);
    }

    /**
     * Render the transactions
     */
    function renderTransactions() {
        DOM.transactionsList.innerHTML = '';

        state.transactions.forEach(tx => {
            const row = document.createElement('tr');
            row.innerHTML = `
                <td>${tx.hash.slice(0, 6)}...${tx.hash.slice(-4)}</td>
                <td>${tx.type}</td>
                <td>${tx.description}</td>
                <td>${tx.amount}</td>
                <td class="${tx.status.toLowerCase()}">${tx.status}</td>
                <td>${formatRelativeTime(tx.timestamp)}</td>
                <td>${tx.blockNumber || 'N/A'}</td>
            `;
            DOM.transactionsList.appendChild(row);
        });
    }

    // ---------------------------------------------------------------------
    // Portfolio Functions
    // ---------------------------------------------------------------------

    /**
     * Update portfolio data
     */
    function updatePortfolio() {
        const portfolio = state.portfolio;
        let totalValue = 0;

        // Calculate token values and total portfolio value
        portfolio.forEach(token => {
            token.value = token.balance * token.price;
            totalValue += token.value;
        });

        // Calculate token allocations
        portfolio.forEach(token => {
            token.allocation = (token.value / totalValue) * 100;
        });

        // Update UI
        renderPortfolio();
    }

    /**
     * Render the portfolio
     */
    function renderPortfolio() {
        DOM.portfolioList.innerHTML = '';

        state.portfolio.forEach(token => {
            const row = document.createElement('tr');
            row.innerHTML = `
                <td>${token.symbol}</td>
                <td>${token.name}</td>
                <td>${formatNumber(token.balance)}</td>
                <td>${formatCurrency(token.price)}</td>
                <td>${formatCurrency(token.value)}</td>
                <td>${token.allocation.toFixed(1)}%</td>
            `;
            DOM.portfolioList.appendChild(row);
        });
    }

    // ---------------------------------------------------------------------
    // Staking Functions
    // ---------------------------------------------------------------------

    /**
     * Update staking data
     */
    function updateStaking() {
        const staking = state.staking;
        const now = Date.now();
        const timeSinceLastClaim = now - staking.lastClaimed;

        // Calculate pending rewards
        staking.pendingRewards = (staking.stakedOpus * staking.rewardRateApy / 100 / 365 / 24 / 60 / 60) * (timeSinceLastClaim / 1000);

        // Update UI
        renderStaking();
    }

    /**
     * Render the staking
     */
    function renderStaking() {
        DOM.stakingStaked.textContent = formatNumber(state.staking.stakedOpus);
        DOM.stakingRewards.textContent = formatNumber(state.staking.pendingRewards, 4);
        DOM.stakingRate.textContent = `${state.staking.rewardRateApy.toFixed(1)}% APY`;
    }

    /**
     * Claim staking rewards
     */
    function claimStakingRewards() {
        const staking = state.staking;

        // Add rewards to OPUS balance
        const opusToken = state.wallet.tokens.find(token => token.symbol === 'OPUS');
        opusToken.balance += staking.pendingRewards;

        // Reset pending rewards and last claimed time
        staking.pendingRewards = 0;
        staking.lastClaimed = Date.now();

        // Update UI
        renderStaking();
        updatePortfolio();

        // Add notification
        addNotification('Staking rewards claimed successfully', 'success');

        // Play claim sound
        playTone(784, 200);
    }

    // ---------------------------------------------------------------------
    // Notification Functions
    // ---------------------------------------------------------------------

    /**
     * Add a new notification
     * @param {string} message - Notification message
     * @param {string} type - Notification type (success, error, info, warning)
     */
    function addNotification(message, type) {
        const notification = {
            id: Date.now(),
            message: message,
            type: type,
            timestamp: Date.now()
        };

        state.notifications.unshift(notification);

        // Update UI
        renderNotifications();

        // Auto-dismiss after 5 seconds
        setTimeout(() => {
            removeNotification(notification.id);
        }, 5000);
    }

    /**
     * Remove a notification
     * @param {number} id - Notification ID
     */
    function removeNotification(id) {
        state.notifications = state.notifications.filter(notification => notification.id !== id);

        // Update UI
        renderNotifications();
    }

    /**
     * Render the notifications
     */
    function renderNotifications() {
        DOM.notificationsList.innerHTML = '';

        state.notifications.forEach(notification => {
            const item = document.createElement('li');
            item.className = `notification ${notification.type}`;
            item.innerHTML = `
                <span>${notification.message}</span>
                <button class="close-btn" data-id="${notification.id}">×</button>
            `;
            DOM.notificationsList.appendChild(item);
        });
    }

    // ---------------------------------------------------------------------
    // Settings Functions
    // ---------------------------------------------------------------------

    /**
     * Update settings
     * @param {string} key - Setting key
     * @param {*} value - Setting value
     */
    function updateSettings(key, value) {
        state.settings[key] = value;

        // Update UI
        renderSettings();

        // Save settings to local storage
        localStorage.setItem('magnumOpusSettings', JSON.stringify(state.settings));
    }

    /**
     * Render the settings
     */
    function renderSettings() {
        DOM.themeSelect.value = state.settings.theme;
        DOM.currencySelect.value = state.settings.currency;
        DOM.languageSelect.value = state.settings.language;
        DOM.slippageInput.value = state.settings.slippageTolerance;
        DOM.soundsCheckbox.checked = state.settings.enableSounds;
        DOM.refreshIntervalInput.value = state.settings.autoRefreshInterval;
    }

    // ---------------------------------------------------------------------
    // Event Handlers
    // ---------------------------------------------------------------------

    /**
     * Initialize DOM elements
     */
    function initDOM() {
        // Wallet
        DOM.connectWalletBtn = document.getElementById('connect-wallet-btn');
        DOM.walletAddress = document.getElementById('wallet-address');
        DOM.walletBalance = document.getElementById('wallet-balance');

        // Market
        DOM.marketPrice = document.getElementById('market-price');
        DOM.marketChange = document.getElementById('market-change');
        DOM.marketVolume = document.getElementById('market-volume');
        DOM.marketHigh = document.getElementById('market-high');
        DOM.marketLow = document.getElementById('market-low');
        DOM.marketChart = document.getElementById('market-chart');

        // Order Book
        DOM.orderBookBids = document.getElementById('order-book-bids');
        DOM.orderBookAsks = document.getElementById('order-book-asks');

        // Transactions
        DOM.transactionsList = document.getElementById('transactions-list');

        // Portfolio
        DOM.portfolioList = document.getElementById('portfolio-list');

        // Staking
        DOM.stakingStaked = document.getElementById('staking-staked');
        DOM.stakingRewards = document.getElementById('staking-rewards');
        DOM.stakingRate = document.getElementById('staking-rate');
        DOM.claimRewardsBtn = document.getElementById('claim-rewards-btn');

        // Notifications
        DOM.notificationsList = document.getElementById('notifications-list');

        // Settings
        DOM.themeSelect = document.getElementById('theme-select');
        DOM.currencySelect = document.getElementById('currency-select');
        DOM.languageSelect = document.getElementById('language-select');
        DOM.slippageInput = document.getElementById('slippage-input');
        DOM.soundsCheckbox = document.getElementById('sounds-checkbox');
        DOM.refreshIntervalInput = document.getElementById('refresh-interval-input');
    }

    /**
     * Initialize event listeners
     */
    function initEventListeners() {
        // Wallet
        DOM.connectWalletBtn.addEventListener('click', () => {
            if (state.wallet.connected) {
                disconnectWallet();
            } else {
                connectWallet();
            }
        });

        // Staking
        DOM.claimRewardsBtn.addEventListener('click', claimStakingRewards);

        // Notifications
        DOM.notificationsList.addEventListener('click', (e) => {
            if (e.target.classList.contains('close-btn')) {
                const id = parseInt(e.target.getAttribute('data-id'));
                removeNotification(id);
            }
        });

        // Settings
        DOM.themeSelect.addEventListener('change', (e) => updateSettings('theme', e.target.value));
        DOM.currencySelect.addEventListener('change', (e) => updateSettings('currency', e.target.value));
        DOM.languageSelect.addEventListener('change', (e) => updateSettings('language', e.target.value));
        DOM.slippageInput.addEventListener('change', (e) => updateSettings('slippageTolerance', parseFloat(e.target.value)));
        DOM.soundsCheckbox.addEventListener('change', (e) => updateSettings('enableSounds', e.target.checked));
        DOM.refreshIntervalInput.addEventListener('change', (e) => {
            updateSettings('autoRefreshInterval', parseInt(e.target.value));
            restartTickers();
        });
    }

    /**
     * Initialize tickers
     */
    function initTickers() {
        marketInterval = setInterval(updateMarketData, state.settings.autoRefreshInterval);
        orderBookInterval = setInterval(updateOrderBook, state.settings.autoRefreshInterval);
        stakingInterval = setInterval(updateStaking, state.settings.autoRefreshInterval);
    }

    /**
     * Restart tickers
     */
    function restartTickers() {
        clearInterval(marketInterval);
        clearInterval(orderBookInterval);
        clearInterval(stakingInterval);
        initTickers();
    }

    // ---------------------------------------------------------------------
    // Initialization
    // ---------------------------------------------------------------------

    /**
     * Initialize the application
     */
    function init() {
        // Load settings from local storage
        const savedSettings = localStorage.getItem('magnumOpusSettings');
        if (savedSettings) {
            state.settings = JSON.parse(savedSettings);
        }

        // Initialize DOM elements
        initDOM();

        // Initialize event listeners
        initEventListeners();

        // Initialize tickers
        initTickers();

        // Render initial UI
        renderSettings();
        renderTransactions();
        renderPortfolio();
        renderStaking();
        renderNotifications();
    }

    // Start the application
    init();

    // Expose functions to global scope for debugging
    window.magnumOpus = {
        state,
        playTone,
        formatCurrency,
        formatNumber,
        formatRelativeTime,
        generateTxHash,
        connectWallet,
        disconnectWallet,
        updateMarketData,
        updateOrderBook,
        addTransaction,
        updatePortfolio,
        updateStaking,
        claimStakingRewards,
        addNotification,
        removeNotification,
        updateSettings,
        restartTickers
    };

})();
