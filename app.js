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

        oscillator.type = 'sine';
        oscillator.frequency.value = frequency;

        gainNode.gain.value = 0.1;
        gainNode.gain.exponentialRampToValueAtTime(0.00001, audioCtx.currentTime + duration / 1000);

        oscillator.connect(gainNode);
        gainNode.connect(audioCtx.destination);

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
    function formatCurrency(value, currency = '$', decimals = 2) {
        return `${currency}${value.toFixed(decimals).replace(/\B(?=(\d{3})+(?!\d))/g, ',')}`;
    }

    /**
     * Format a number as percentage
     * @param {number} value - The value to format
     * @param {number} decimals - Number of decimal places
     * @returns {string} Formatted percentage string
     */
    function formatPercentage(value, decimals = 2) {
        return `${value.toFixed(decimals)}%`;
    }

    /**
     * Format a timestamp as a relative time string
     * @param {number} timestamp - The timestamp to format
     * @returns {string} Relative time string
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

    // ---------------------------------------------------------------------
    // Core Application Functions
    // ---------------------------------------------------------------------

    /**
     * Initialize the DOM elements cache
     */
    function initDOM() {
        // Wallet section
        DOM.walletConnectBtn = document.getElementById('wallet-connect-btn');
        DOM.walletAddress = document.getElementById('wallet-address');
        DOM.walletBalanceEth = document.getElementById('wallet-balance-eth');
        DOM.walletBalanceUsdt = document.getElementById('wallet-balance-usdt');
        DOM.walletBalanceBtc = document.getElementById('wallet-balance-btc');
        DOM.walletBalanceSol = document.getElementById('wallet-balance-sol');
        DOM.walletNetwork = document.getElementById('wallet-network');
        DOM.walletTokensList = document.getElementById('wallet-tokens-list');

        // Market section
        DOM.marketPairSelect = document.getElementById('market-pair-select');
        DOM.marketPrice = document.getElementById('market-price');
        DOM.marketChange24h = document.getElementById('market-change-24h');
        DOM.marketVolume24h = document.getElementById('market-volume-24h');
        DOM.marketHigh24h = document.getElementById('market-high-24h');
        DOM.marketLow24h = document.getElementById('market-low-24h');
        DOM.marketChart = document.getElementById('market-chart');

        // Order book section
        DOM.orderBookBids = document.getElementById('order-book-bids');
        DOM.orderBookAsks = document.getElementById('order-book-asks');

        // Transactions section
        DOM.transactionsList = document.getElementById('transactions-list');

        // Portfolio section
        DOM.portfolioList = document.getElementById('portfolio-list');
        DOM.portfolioChart = document.getElementById('portfolio-chart');

        // Staking section
        DOM.stakingStakedOpus = document.getElementById('staking-staked-opus');
        DOM.stakingRewardRateApy = document.getElementById('staking-reward-rate-apy');
        DOM.stakingPendingRewards = document.getElementById('staking-pending-rewards');
        DOM.stakingLastClaimed = document.getElementById('staking-last-claimed');
        DOM.stakingClaimBtn = document.getElementById('staking-claim-btn');

        // Notifications section
        DOM.notificationsList = document.getElementById('notifications-list');

        // Settings section
        DOM.settingsTheme = document.getElementById('settings-theme');
        DOM.settingsCurrency = document.getElementById('settings-currency');
        DOM.settingsLanguage = document.getElementById('settings-language');
        DOM.settingsSlippageTolerance = document.getElementById('settings-slippage-tolerance');
        DOM.settingsEnableSounds = document.getElementById('settings-enable-sounds');
        DOM.settingsAutoRefreshInterval = document.getElementById('settings-auto-refresh-interval');
    }

    /**
     * Update the wallet section in the UI
     */
    function updateWalletUI() {
        if (state.wallet.connected) {
            DOM.walletConnectBtn.textContent = 'Disconnect Wallet';
            DOM.walletAddress.textContent = state.wallet.address;
            DOM.walletAddress.classList.remove('hidden');
        } else {
            DOM.walletConnectBtn.textContent = 'Connect Wallet';
            DOM.walletAddress.textContent = '';
            DOM.walletAddress.classList.add('hidden');
        }

        DOM.walletBalanceEth.textContent = `${state.wallet.balanceEth.toFixed(4)} ETH`;
        DOM.walletBalanceUsdt.textContent = `${formatCurrency(state.wallet.balanceUsdt)}`;
        DOM.walletBalanceBtc.textContent = `${state.wallet.balanceBtc.toFixed(4)} BTC`;
        DOM.walletBalanceSol.textContent = `${state.wallet.balanceSol.toFixed(4)} SOL`;
        DOM.walletNetwork.textContent = state.wallet.networkName;

        // Update tokens list
        DOM.walletTokensList.innerHTML = '';
        state.wallet.tokens.forEach(token => {
            const li = document.createElement('li');
            li.className = 'wallet-token';
            li.innerHTML = `
                <div class="token-symbol">${token.symbol}</div>
                <div class="token-name">${token.name}</div>
                <div class="token-balance">${token.balance.toFixed(4)}</div>
                <div class="token-value">${formatCurrency(token.balance * token.price)}</div>
            `;
            DOM.walletTokensList.appendChild(li);
        });
    }

    /**
     * Update the market section in the UI
     */
    function updateMarketUI() {
        const pair = state.market.selectedPair;
        const rate = PAIR_RATES[pair];

        DOM.marketPairSelect.value = pair;
        DOM.marketPrice.textContent = formatCurrency(state.market.price, '', rate.decimals);
        DOM.marketChange24h.textContent = `${formatPercentage(state.market.change24h)} (${formatCurrency(state.market.change24h * state.market.price / 100, '', rate.decimals)})`;
        DOM.marketVolume24h.textContent = formatCurrency(state.market.volume24h, '', rate.decimals);
        DOM.marketHigh24h.textContent = formatCurrency(state.market.high24h, '', rate.decimals);
        DOM.marketLow24h.textContent = formatCurrency(state.market.low24h, '', rate.decimals);

        // Update chart
        renderChart();
    }

    /**
     * Update the order book section in the UI
     */
    function updateOrderBookUI() {
        // Update bids
        DOM.orderBookBids.innerHTML = '';
        state.orderBook.bids.slice(0, state.orderBook.maxDepth).forEach(bid => {
            const li = document.createElement('li');
            li.className = 'order-book-item';
            li.innerHTML = `
                <div class="order-book-price">${formatCurrency(bid.price, '', PAIR_RATES[state.market.selectedPair].decimals)}</div>
                <div class="order-book-amount">${bid.amount.toFixed(4)}</div>
                <div class="order-book-total">${formatCurrency(bid.total, '', PAIR_RATES[state.market.selectedPair].decimals)}</div>
            `;
            DOM.orderBookBids.appendChild(li);
        });

        // Update asks
        DOM.orderBookAsks.innerHTML = '';
        state.orderBook.asks.slice(0, state.orderBook.maxDepth).forEach(ask => {
            const li = document.createElement('li');
            li.className = 'order-book-item';
            li.innerHTML = `
                <div class="order-book-price">${formatCurrency(ask.price, '', PAIR_RATES[state.market.selectedPair].decimals)}</div>
                <div class="order-book-amount">${ask.amount.toFixed(4)}</div>
                <div class="order-book-total">${formatCurrency(ask.total, '', PAIR_RATES[state.market.selectedPair].decimals)}</div>
            `;
            DOM.orderBookAsks.appendChild(li);
        });
    }

    /**
     * Update the transactions section in the UI
     */
    function updateTransactionsUI() {
        DOM.transactionsList.innerHTML = '';
        state.transactions.forEach(tx => {
            const li = document.createElement('li');
            li.className = 'transaction-item';
            li.innerHTML = `
                <div class="transaction-hash">${tx.hash}</div>
                <div class="transaction-type">${tx.type}</div>
                <div class="transaction-description">${tx.description}</div>
                <div class="transaction-amount">${tx.amount}</div>
                <div class="transaction-status">${tx.status}</div>
                <div class="transaction-timestamp">${formatRelativeTime(tx.timestamp)}</div>
                <div class="transaction-block-number">Block #${tx.blockNumber}</div>
            `;
            DOM.transactionsList.appendChild(li);
        });
    }

    /**
     * Update the portfolio section in the UI
     */
    function updatePortfolioUI() {
        // Update portfolio list
        DOM.portfolioList.innerHTML = '';
        state.portfolio.forEach(asset => {
            const li = document.createElement('li');
            li.className = 'portfolio-item';
            li.innerHTML = `
                <div class="portfolio-symbol">${asset.symbol}</div>
                <div class="portfolio-name">${asset.name}</div>
                <div class="portfolio-balance">${asset.balance.toFixed(4)}</div>
                <div class="portfolio-price">${formatCurrency(asset.price)}</div>
                <div class="portfolio-value">${formatCurrency(asset.value)}</div>
                <div class="portfolio-allocation">${formatPercentage(asset.allocation)}</div>
            `;
            DOM.portfolioList.appendChild(li);
        });

        // Update portfolio chart
        renderPortfolioChart();
    }

    /**
     * Update the staking section in the UI
     */
    function updateStakingUI() {
        DOM.stakingStakedOpus.textContent = `${state.staking.stakedOpus.toFixed(2)} OPUS`;
        DOM.stakingRewardRateApy.textContent = `${formatPercentage(state.staking.rewardRateApy)}`;
        DOM.stakingPendingRewards.textContent = `${state.staking.pendingRewards.toFixed(2)} OPUS`;
        DOM.stakingLastClaimed.textContent = formatRelativeTime(state.staking.lastClaimed);
    }

    /**
     * Update the notifications section in the UI
     */
    function updateNotificationsUI() {
        DOM.notificationsList.innerHTML = '';
        state.notifications.forEach(notification => {
            const li = document.createElement('li');
            li.className = 'notification-item';
            li.innerHTML = `
                <div class="notification-message">${notification.message}</div>
                <div class="notification-timestamp">${formatRelativeTime(notification.timestamp)}</div>
            `;
            DOM.notificationsList.appendChild(li);
        });
    }

    /**
     * Update the settings section in the UI
     */
    function updateSettingsUI() {
        DOM.settingsTheme.value = state.settings.theme;
        DOM.settingsCurrency.value = state.settings.currency;
        DOM.settingsLanguage.value = state.settings.language;
        DOM.settingsSlippageTolerance.value = state.settings.slippageTolerance;
        DOM.settingsEnableSounds.checked = state.settings.enableSounds;
        DOM.settingsAutoRefreshInterval.value = state.settings.autoRefreshInterval;
    }

    // ---------------------------------------------------------------------
    // Event Handlers
    // ---------------------------------------------------------------------

    /**
     * Handle wallet connect/disconnect button click
     */
    function handleWalletConnectClick() {
        state.wallet.connected = !state.wallet.connected;
        if (state.wallet.connected) {
            state.wallet.address = '0x1234...5678';
            playTone(440, 200); // Play a tone when wallet is connected
        } else {
            state.wallet.address = null;
            playTone(220, 200); // Play a lower tone when wallet is disconnected
        }
        updateWalletUI();
    }

    /**
     * Handle market pair selection change
     */
    function handleMarketPairChange() {
        state.market.selectedPair = DOM.marketPairSelect.value;
        updateMarketUI();
        updateOrderBookUI();
    }

    /**
     * Handle staking claim button click
     */
    function handleStakingClaimClick() {
        if (state.staking.pendingRewards > 0) {
            state.staking.stakedOpus += state.staking.pendingRewards;
            state.staking.pendingRewards = 0;
            state.staking.lastClaimed = Date.now();
            playTone(523, 200); // Play a higher tone when rewards are claimed
            updateStakingUI();
            addNotification('Rewards claimed successfully!');
        }
    }

    /**
     * Handle settings change
     */
    function handleSettingsChange() {
        state.settings.theme = DOM.settingsTheme.value;
        state.settings.currency = DOM.settingsCurrency.value;
        state.settings.language = DOM.settingsLanguage.value;
        state.settings.slippageTolerance = parseFloat(DOM.settingsSlippageTolerance.value);
        state.settings.enableSounds = DOM.settingsEnableSounds.checked;
        state.settings.autoRefreshInterval = parseInt(DOM.settingsAutoRefreshInterval.value);

        // Update auto-refresh intervals
        clearInterval(marketInterval);
        clearInterval(gasInterval);
        clearInterval(orderBookInterval);
        clearInterval(stakingInterval);

        marketInterval = setInterval(updateMarketData, state.settings.autoRefreshInterval);
        gasInterval = setInterval(updateGasPrices, state.settings.autoRefreshInterval);
        orderBookInterval = setInterval(updateOrderBook, state.settings.autoRefreshInterval);
        stakingInterval = setInterval(updateStakingData, state.settings.autoRefreshInterval);
    }

    // ---------------------------------------------------------------------
    // Data Simulation Functions
    // ---------------------------------------------------------------------

    /**
     * Simulate market data updates
     */
    function updateMarketData() {
        const pair = state.market.selectedPair;
        const rate = PAIR_RATES[pair];

        // Simulate price change
        const change = (Math.random() - 0.5) * 0.01;
        state.market.price = rate.price * (1 + change);
        state.market.change24h = change * 100;
        state.market.volume24h = Math.random() * 1000000000;
        state.market.high24h = state.market.price * (1 + Math.random() * 0.02);
        state.market.low24h = state.market.price * (1 - Math.random() * 0.02);

        // Simulate chart data
        const now = new Date();
        state.market.chartData.labels.push(now.toISOString());
        state.market.chartData.prices.push(state.market.price);
        state.market.chartData.candles.push({
            open: state.market.price * (1 - Math.random() * 0.01),
            high: state.market.high24h,
            low: state.market.low24h,
            close: state.market.price
        });

        // Keep only the last 100 data points
        if (state.market.chartData.labels.length > 100) {
            state.market.chartData.labels.shift();
            state.market.chartData.prices.shift();
            state.market.chartData.candles.shift();
        }

        updateMarketUI();
    }

    /**
     * Simulate gas price updates
     */
    function updateGasPrices() {
        state.gas.slow = Math.max(10, state.gas.slow + (Math.random() - 0.5) * 2);
        state.gas.standard = Math.max(15, state.gas.standard + (Math.random() - 0.5) * 3);
        state.gas.fast = Math.max(20, state.gas.fast + (Math.random() - 0.5) * 4);
        state.gas.current = state.gas.standard;
    }

    /**
     * Simulate order book updates
     */
    function updateOrderBook() {
        const pair = state.market.selectedPair;
        const rate = PAIR_RATES[pair];

        // Simulate bids
        state.orderBook.bids = [];
        for (let i = 0; i < state.orderBook.maxDepth; i++) {
            const price = state.market.price * (1 - Math.random() * 0.02);
            const amount = Math.random() * 10;
            state.orderBook.bids.push({
                price: price,
                amount: amount,
                total: price * amount
            });
        }
        state.orderBook.bids.sort((a, b) => b.price - a.price);

        // Simulate asks
        state.orderBook.asks = [];
        for (let i = 0; i < state.orderBook.maxDepth; i++) {
            const price = state.market.price * (1 + Math.random() * 0.02);
            const amount = Math.random() * 10;
            state.orderBook.asks.push({
                price: price,
                amount: amount,
                total: price * amount
            });
        }
        state.orderBook.asks.sort((a, b) => a.price - b.price);

        updateOrderBookUI();
    }

    /**
     * Simulate staking data updates
     */
    function updateStakingData() {
        state.staking.pendingRewards += state.staking.stakedOpus * state.staking.rewardRateApy / 100 / 365 / 24;
        updateStakingUI();
    }

    // ---------------------------------------------------------------------
    // Chart Rendering Functions
    // ---------------------------------------------------------------------

    /**
     * Render the market chart
     */
    function renderChart() {
        const ctx = DOM.marketChart.getContext('2d');
        const width = DOM.marketChart.width;
        const height = DOM.marketChart.height;

        // Clear the canvas
        ctx.clearRect(0, 0, width, height);

        // Draw the chart
        if (state.market.chartData.prices.length > 0) {
            const minPrice = Math.min(...state.market.chartData.prices);
            const maxPrice = Math.max(...state.market.chartData.prices);
            const priceRange = maxPrice - minPrice;

            // Draw the price line
            ctx.beginPath();
            ctx.strokeStyle = '#4f46e5';
            ctx.lineWidth = 2;

            const xStep = width / (state.market.chartData.prices.length - 1);
            for (let i = 0; i < state.market.chartData.prices.length; i++) {
                const x = i * xStep;
                const y = height - ((state.market.chartData.prices[i] - minPrice) / priceRange) * height;
                if (i === 0) {
                    ctx.moveTo(x, y);
                } else {
                    ctx.lineTo(x, y);
                }
            }
            ctx.stroke();
        }
    }

    /**
     * Render the portfolio chart
     */
    function renderPortfolioChart() {
        const ctx = DOM.portfolioChart.getContext('2d');
        const width = DOM.portfolioChart.width;
        const height = DOM.portfolioChart.height;

        // Clear the canvas
        ctx.clearRect(0, 0, width, height);

        // Draw the chart
        if (state.portfolio.length > 0) {
            const totalValue = state.portfolio.reduce((sum, asset) => sum + asset.value, 0);
            let startAngle = 0;

            state.portfolio.forEach(asset => {
                const sliceAngle = (asset.value / totalValue) * 2 * Math.PI;
                const endAngle = startAngle + sliceAngle;

                // Draw the pie slice
                ctx.beginPath();
                ctx.moveTo(width / 2, height / 2);
                ctx.arc(width / 2, height / 2, Math.min(width, height) / 2, startAngle, endAngle);
                ctx.closePath();
                ctx.fillStyle = getColorForAsset(asset.symbol);
                ctx.fill();

                startAngle = endAngle;
            });
        }
    }

    /**
     * Get a color for an asset based on its symbol
     * @param {string} symbol - The asset symbol
     * @returns {string} The color in hex format
     */
    function getColorForAsset(symbol) {
        const colors = {
            'ETH': '#4f46e5',
            'BTC': '#f59e0b',
            'SOL': '#10b981',
            'OPUS': '#8b5cf6'
        };
        return colors[symbol] || '#6b7280';
    }

    // ---------------------------------------------------------------------
    // Notification Functions
    // ---------------------------------------------------------------------

    /**
     * Add a notification to the state and UI
     * @param {string} message - The notification message
     */
    function addNotification(message) {
        state.notifications.unshift({
            message: message,
            timestamp: Date.now()
        });
        if (state.notifications.length > 10) {
            state.notifications.pop();
        }
        updateNotificationsUI();
    }

    // ---------------------------------------------------------------------
    // Initialization
    // ---------------------------------------------------------------------

    /**
     * Initialize the application
     */
    function init() {
        initDOM();
        updateWalletUI();
        updateMarketUI();
        updateOrderBookUI();
        updateTransactionsUI();
        updatePortfolioUI();
        updateStakingUI();
        updateNotificationsUI();
        updateSettingsUI();

        // Set up event listeners
        DOM.walletConnectBtn.addEventListener('click', handleWalletConnectClick);
        DOM.marketPairSelect.addEventListener('change', handleMarketPairChange);
        DOM.stakingClaimBtn.addEventListener('click', handleStakingClaimClick);
        DOM.settingsTheme.addEventListener('change', handleSettingsChange);
        DOM.settingsCurrency.addEventListener('change', handleSettingsChange);
        DOM.settingsLanguage.addEventListener('change', handleSettingsChange);
        DOM.settingsSlippageTolerance.addEventListener('change', handleSettingsChange);
        DOM.settingsEnableSounds.addEventListener('change', handleSettingsChange);
        DOM.settingsAutoRefreshInterval.addEventListener('change', handleSettingsChange);

        // Set up data simulation intervals
        marketInterval = setInterval(updateMarketData, state.settings.autoRefreshInterval);
        gasInterval = setInterval(updateGasPrices, state.settings.autoRefreshInterval);
        orderBookInterval = setInterval(updateOrderBook, state.settings.autoRefreshInterval);
        stakingInterval = setInterval(updateStakingData, state.settings.autoRefreshInterval);
    }

    // Initialize the application when the DOM is loaded
    document.addEventListener('DOMContentLoaded', init);

    // Expose the state and functions for debugging and testing
    window.MagnumOpus = {
        state: state,
        updateWalletUI: updateWalletUI,
        updateMarketUI: updateMarketUI,
        updateOrderBookUI: updateOrderBookUI,
        updateTransactionsUI: updateTransactionsUI,
        updatePortfolioUI: updatePortfolioUI,
        updateStakingUI: updateStakingUI,
        updateNotificationsUI: updateNotificationsUI,
        updateSettingsUI: updateSettingsUI,
        addNotification: addNotification,
        playTone: playTone
    };

})();