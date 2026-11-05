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
     * @param {number} duration - Duration in milliseconds
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

        oscillator.frequency.value = frequency;
        gainNode.gain.value = 0.1;

        oscillator.start();

        setTimeout(() => {
            gainNode.gain.exponentialRampToValueAtTime(0.0001, audioCtx.currentTime + 0.1);
            oscillator.stop(audioCtx.currentTime + 0.2);
        }, duration);
    }

    // ---------------------------------------------------------------------
    // Utility Functions
    // ---------------------------------------------------------------------

    /**
     * Format a number with the specified number of decimal places
     * @param {number} num - The number to format
     * @param {number} decimals - Number of decimal places
     * @returns {string} Formatted number string
     */
    function formatNumber(num, decimals) {
        return num.toLocaleString('en-US', {
            minimumFractionDigits: decimals,
            maximumFractionDigits: decimals
        });
    }

    /**
     * Format a cryptocurrency amount with the appropriate decimal places
     * @param {number} amount - The amount to format
     * @param {number} decimals - Number of decimal places
     * @returns {string} Formatted cryptocurrency string
     */
    function formatCrypto(amount, decimals) {
        return formatNumber(amount, decimals);
    }

    /**
     * Format a currency amount with the appropriate decimal places
     * @param {number} amount - The amount to format
     * @returns {string} Formatted currency string
     */
    function formatCurrency(amount) {
        return formatNumber(amount, 2);
    }

    /**
     * Format a percentage value
     * @param {number} value - The percentage value to format
     * @returns {string} Formatted percentage string
     */
    function formatPercentage(value) {
        return `${formatNumber(value, 2)}%`;
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
    function generateRandomHash() {
        return `0x${Math.random().toString(16).substr(2, 10)}...${Math.random().toString(16).substr(2, 4)}`;
    }

    /**
     * Generate a random block number
     * @returns {number} Random block number
     */
    function generateRandomBlockNumber() {
        return Math.floor(Math.random() * 10000000) + 19800000;
    }

    // ---------------------------------------------------------------------
    // DOM Initialization
    // ---------------------------------------------------------------------

    /**
     * Initialize DOM elements and cache references
     */
    function initDOM() {
        // Wallet Section
        DOM.walletConnectBtn = document.getElementById('wallet-connect-btn');
        DOM.walletAddress = document.getElementById('wallet-address');
        DOM.walletBalanceEth = document.getElementById('wallet-balance-eth');
        DOM.walletBalanceUsdt = document.getElementById('wallet-balance-usdt');
        DOM.walletBalanceBtc = document.getElementById('wallet-balance-btc');
        DOM.walletBalanceSol = document.getElementById('wallet-balance-sol');
        DOM.walletNetwork = document.getElementById('wallet-network');
        DOM.walletTokensList = document.getElementById('wallet-tokens-list');

        // Market Section
        DOM.marketPairSelect = document.getElementById('market-pair-select');
        DOM.marketPrice = document.getElementById('market-price');
        DOM.marketChange24h = document.getElementById('market-change-24h');
        DOM.marketVolume24h = document.getElementById('market-volume-24h');
        DOM.marketHigh24h = document.getElementById('market-high-24h');
        DOM.marketLow24h = document.getElementById('market-low-24h');
        DOM.marketChartCanvas = document.getElementById('market-chart-canvas');

        // Order Book Section
        DOM.orderBookBids = document.getElementById('order-book-bids');
        DOM.orderBookAsks = document.getElementById('order-book-asks');

        // Transactions Section
        DOM.transactionsList = document.getElementById('transactions-list');

        // Portfolio Section
        DOM.portfolioList = document.getElementById('portfolio-list');
        DOM.portfolioChartCanvas = document.getElementById('portfolio-chart-canvas');

        // Staking Section
        DOM.stakingStakedOpus = document.getElementById('staking-staked-opus');
        DOM.stakingRewardRateApy = document.getElementById('staking-reward-rate-apy');
        DOM.stakingPendingRewards = document.getElementById('staking-pending-rewards');
        DOM.stakingLastClaimed = document.getElementById('staking-last-claimed');
        DOM.stakingClaimBtn = document.getElementById('staking-claim-btn');

        // Notifications Section
        DOM.notificationsList = document.getElementById('notifications-list');

        // Settings Section
        DOM.settingsThemeSelect = document.getElementById('settings-theme-select');
        DOM.settingsCurrencySelect = document.getElementById('settings-currency-select');
        DOM.settingsLanguageSelect = document.getElementById('settings-language-select');
        DOM.settingsSlippageInput = document.getElementById('settings-slippage-input');
        DOM.settingsSoundsCheckbox = document.getElementById('settings-sounds-checkbox');
        DOM.settingsAutoRefreshInput = document.getElementById('settings-auto-refresh-input');

        // Event Listeners
        DOM.walletConnectBtn.addEventListener('click', handleWalletConnect);
        DOM.marketPairSelect.addEventListener('change', handleMarketPairChange);
        DOM.stakingClaimBtn.addEventListener('click', handleStakingClaim);
        DOM.settingsThemeSelect.addEventListener('change', handleSettingsThemeChange);
        DOM.settingsCurrencySelect.addEventListener('change', handleSettingsCurrencyChange);
        DOM.settingsLanguageSelect.addEventListener('change', handleSettingsLanguageChange);
        DOM.settingsSlippageInput.addEventListener('change', handleSettingsSlippageChange);
        DOM.settingsSoundsCheckbox.addEventListener('change', handleSettingsSoundsChange);
        DOM.settingsAutoRefreshInput.addEventListener('change', handleSettingsAutoRefreshChange);
    }

    // ---------------------------------------------------------------------
    // Event Handlers
    // ---------------------------------------------------------------------

    /**
     * Handle wallet connect button click
     */
    function handleWalletConnect() {
        state.wallet.connected = true;
        state.wallet.address = `0x${Math.random().toString(16).substr(2, 10)}...${Math.random().toString(16).substr(2, 4)}`;
        updateWalletUI();
        playTone(880, 200);
    }

    /**
     * Handle market pair selection change
     */
    function handleMarketPairChange() {
        state.market.selectedPair = DOM.marketPairSelect.value;
        updateMarketUI();
        playTone(660, 200);
    }

    /**
     * Handle staking claim button click
     */
    function handleStakingClaim() {
        const rewards = state.staking.pendingRewards;
        state.staking.pendingRewards = 0;
        state.staking.lastClaimed = Date.now();
        updateStakingUI();
        addNotification(`Claimed ${formatCrypto(rewards, 2)} OPUS rewards`);
        playTone(1046, 200);
    }

    /**
     * Handle theme setting change
     */
    function handleSettingsThemeChange() {
        state.settings.theme = DOM.settingsThemeSelect.value;
        updateTheme();
        playTone(784, 200);
    }

    /**
     * Handle currency setting change
     */
    function handleSettingsCurrencyChange() {
        state.settings.currency = DOM.settingsCurrencySelect.value;
        updateMarketUI();
        updatePortfolioUI();
        playTone(784, 200);
    }

    /**
     * Handle language setting change
     */
    function handleSettingsLanguageChange() {
        state.settings.language = DOM.settingsLanguageSelect.value;
        updateLanguage();
        playTone(784, 200);
    }

    /**
     * Handle slippage tolerance setting change
     */
    function handleSettingsSlippageChange() {
        state.settings.slippageTolerance = parseFloat(DOM.settingsSlippageInput.value);
        playTone(784, 200);
    }

    /**
     * Handle sounds setting change
     */
    function handleSettingsSoundsChange() {
        state.settings.enableSounds = DOM.settingsSoundsCheckbox.checked;
        playTone(784, 200);
    }

    /**
     * Handle auto-refresh interval setting change
     */
    function handleSettingsAutoRefreshChange() {
        state.settings.autoRefreshInterval = parseInt(DOM.settingsAutoRefreshInput.value);
        restartEngineTickers();
        playTone(784, 200);
    }

    // ---------------------------------------------------------------------
    // UI Update Functions
    // ---------------------------------------------------------------------

    /**
     * Update the wallet UI with current state
     */
    function updateWalletUI() {
        if (state.wallet.connected) {
            DOM.walletConnectBtn.textContent = 'Disconnect Wallet';
            DOM.walletAddress.textContent = state.wallet.address;
            DOM.walletAddress.style.display = 'block';
        } else {
            DOM.walletConnectBtn.textContent = 'Connect Wallet';
            DOM.walletAddress.style.display = 'none';
        }

        DOM.walletBalanceEth.textContent = formatCrypto(state.wallet.balanceEth, 3);
        DOM.walletBalanceUsdt.textContent = formatCurrency(state.wallet.balanceUsdt);
        DOM.walletBalanceBtc.textContent = formatCrypto(state.wallet.balanceBtc, 4);
        DOM.walletBalanceSol.textContent = formatCrypto(state.wallet.balanceSol, 1);
        DOM.walletNetwork.textContent = state.wallet.networkName;

        // Update tokens list
        DOM.walletTokensList.innerHTML = '';
        state.wallet.tokens.forEach(token => {
            const li = document.createElement('li');
            li.innerHTML = `
                <span class="token-symbol">${token.symbol}</span>
                <span class="token-name">${token.name}</span>
                <span class="token-balance">${formatCrypto(token.balance, token.decimals)}</span>
                <span class="token-value">${formatCurrency(token.balance * token.price)}</span>
            `;
            DOM.walletTokensList.appendChild(li);
        });
    }

    /**
     * Update the market UI with current state
     */
    function updateMarketUI() {
        const pair = state.market.selectedPair;
        const rate = PAIR_RATES[pair];

        DOM.marketPrice.textContent = formatCurrency(rate.price);
        DOM.marketChange24h.textContent = formatPercentage(state.market.change24h);
        DOM.marketVolume24h.textContent = formatCurrency(state.market.volume24h);
        DOM.marketHigh24h.textContent = formatCurrency(state.market.high24h);
        DOM.marketLow24h.textContent = formatCurrency(state.market.low24h);

        // Update chart
        renderMarketChart();
    }

    /**
     * Update the order book UI with current state
     */
    function updateOrderBookUI() {
        // Update bids
        DOM.orderBookBids.innerHTML = '';
        state.orderBook.bids.slice(0, state.orderBook.maxDepth).forEach(bid => {
            const li = document.createElement('li');
            li.innerHTML = `
                <span class="order-price">${formatCurrency(bid.price)}</span>
                <span class="order-amount">${formatCrypto(bid.amount, 4)}</span>
                <span class="order-total">${formatCurrency(bid.price * bid.amount)}</span>
            `;
            DOM.orderBookBids.appendChild(li);
        });

        // Update asks
        DOM.orderBookAsks.innerHTML = '';
        state.orderBook.asks.slice(0, state.orderBook.maxDepth).forEach(ask => {
            const li = document.createElement('li');
            li.innerHTML = `
                <span class="order-price">${formatCurrency(ask.price)}</span>
                <span class="order-amount">${formatCrypto(ask.amount, 4)}</span>
                <span class="order-total">${formatCurrency(ask.price * ask.amount)}</span>
            `;
            DOM.orderBookAsks.appendChild(li);
        });
    }

    /**
     * Update the transactions UI with current state
     */
    function updateTransactionsUI() {
        DOM.transactionsList.innerHTML = '';
        state.transactions.forEach(tx => {
            const li = document.createElement('li');
            li.innerHTML = `
                <span class="tx-hash">${tx.hash}</span>
                <span class="tx-type">${tx.type}</span>
                <span class="tx-description">${tx.description}</span>
                <span class="tx-amount">${tx.amount}</span>
                <span class="tx-status">${tx.status}</span>
                <span class="tx-timestamp">${formatRelativeTime(tx.timestamp)}</span>
                <span class="tx-block">Block ${tx.blockNumber}</span>
            `;
            DOM.transactionsList.appendChild(li);
        });
    }

    /**
     * Update the portfolio UI with current state
     */
    function updatePortfolioUI() {
        DOM.portfolioList.innerHTML = '';
        state.portfolio.forEach(asset => {
            const li = document.createElement('li');
            li.innerHTML = `
                <span class="asset-symbol">${asset.symbol}</span>
                <span class="asset-name">${asset.name}</span>
                <span class="asset-balance">${formatCrypto(asset.balance, 4)}</span>
                <span class="asset-price">${formatCurrency(asset.price)}</span>
                <span class="asset-value">${formatCurrency(asset.value)}</span>
                <span class="asset-allocation">${formatPercentage(asset.allocation)}</span>
            `;
            DOM.portfolioList.appendChild(li);
        });

        // Update chart
        renderPortfolioChart();
    }

    /**
     * Update the staking UI with current state
     */
    function updateStakingUI() {
        DOM.stakingStakedOpus.textContent = formatCrypto(state.staking.stakedOpus, 2);
        DOM.stakingRewardRateApy.textContent = formatPercentage(state.staking.rewardRateApy);
        DOM.stakingPendingRewards.textContent = formatCrypto(state.staking.pendingRewards, 2);
        DOM.stakingLastClaimed.textContent = formatRelativeTime(state.staking.lastClaimed);
    }

    /**
     * Update the notifications UI with current state
     */
    function updateNotificationsUI() {
        DOM.notificationsList.innerHTML = '';
        state.notifications.forEach(notification => {
            const li = document.createElement('li');
            li.textContent = notification;
            DOM.notificationsList.appendChild(li);
        });
    }

    /**
     * Update the settings UI with current state
     */
    function updateSettingsUI() {
        DOM.settingsThemeSelect.value = state.settings.theme;
        DOM.settingsCurrencySelect.value = state.settings.currency;
        DOM.settingsLanguageSelect.value = state.settings.language;
        DOM.settingsSlippageInput.value = state.settings.slippageTolerance;
        DOM.settingsSoundsCheckbox.checked = state.settings.enableSounds;
        DOM.settingsAutoRefreshInput.value = state.settings.autoRefreshInterval;
    }

    /**
     * Update the entire UI with current state
     */
    function updateUI() {
        updateWalletUI();
        updateMarketUI();
        updateOrderBookUI();
        updateTransactionsUI();
        updatePortfolioUI();
        updateStakingUI();
        updateNotificationsUI();
        updateSettingsUI();
    }

    // ---------------------------------------------------------------------
    // Chart Rendering Functions
    // ---------------------------------------------------------------------

    /**
     * Render the market chart
     */
    function renderMarketChart() {
        const ctx = DOM.marketChartCanvas.getContext('2d');
        const width = DOM.marketChartCanvas.width;
        const height = DOM.marketChartCanvas.height;

        // Clear canvas
        ctx.clearRect(0, 0, width, height);

        // Draw chart
        // ... (chart rendering logic)
    }

    /**
     * Render the portfolio chart
     */
    function renderPortfolioChart() {
        const ctx = DOM.portfolioChartCanvas.getContext('2d');
        const width = DOM.portfolioChartCanvas.width;
        const height = DOM.portfolioChartCanvas.height;

        // Clear canvas
        ctx.clearRect(0, 0, width, height);

        // Draw chart
        // ... (chart rendering logic)
    }

    // ---------------------------------------------------------------------
    // Engine Tickers
    // ---------------------------------------------------------------------

    /**
     * Start the market data ticker
     */
    function startMarketTicker() {
        marketInterval = setInterval(() => {
            // Simulate market data updates
            state.market.price = PAIR_RATES[state.market.selectedPair].price * (1 + (Math.random() - 0.5) * 0.01);
            state.market.change24h = (Math.random() - 0.5) * 10;
            state.market.volume24h = Math.random() * 1000000000;
            state.market.high24h = state.market.price * (1 + Math.random() * 0.1);
            state.market.low24h = state.market.price * (1 - Math.random() * 0.1);

            // Update chart data
            // ... (update chart data logic)

            updateMarketUI();
        }, state.settings.autoRefreshInterval);
    }

    /**
     * Start the gas price ticker
     */
    function startGasTicker() {
        gasInterval = setInterval(() => {
            // Simulate gas price updates
            state.gas.slow = Math.max(10, state.gas.slow + (Math.random() - 0.5) * 2);
            state.gas.standard = Math.max(15, state.gas.standard + (Math.random() - 0.5) * 3);
            state.gas.fast = Math.max(20, state.gas.fast + (Math.random() - 0.5) * 4);
            state.gas.current = state.gas.standard;

            // Update UI
            // ... (update gas price UI logic)
        }, state.settings.autoRefreshInterval);
    }

    /**
     * Start the order book ticker
     */
    function startOrderBookTicker() {
        orderBookInterval = setInterval(() => {
            // Simulate order book updates
            state.orderBook.bids = Array.from({ length: 20 }, () => ({
                price: state.market.price * (1 - Math.random() * 0.05),
                amount: Math.random() * 10
            })).sort((a, b) => b.price - a.price);

            state.orderBook.asks = Array.from({ length: 20 }, () => ({
                price: state.market.price * (1 + Math.random() * 0.05),
                amount: Math.random() * 10
            })).sort((a, b) => a.price - b.price);

            updateOrderBookUI();
        }, state.settings.autoRefreshInterval);
    }

    /**
     * Start the staking ticker
     */
    function startStakingTicker() {
        stakingInterval = setInterval(() => {
            // Simulate staking updates
            state.staking.pendingRewards += state.staking.stakedOpus * (state.staking.rewardRateApy / 100 / 365 / 24 / 60 / 60);
            updateStakingUI();
        }, 1000);
    }

    /**
     * Start all engine tickers
     */
    function startEngineTickers() {
        startMarketTicker();
        startGasTicker();
        startOrderBookTicker();
        startStakingTicker();
    }

    /**
     * Stop all engine tickers
     */
    function stopEngineTickers() {
        clearInterval(marketInterval);
        clearInterval(gasInterval);
        clearInterval(orderBookInterval);
        clearInterval(stakingInterval);
    }

    /**
     * Restart all engine tickers
     */
    function restartEngineTickers() {
        stopEngineTickers();
        startEngineTickers();
    }

    // ---------------------------------------------------------------------
    // Notification Functions
    // ---------------------------------------------------------------------

    /**
     * Add a notification to the notifications list
     * @param {string} message - The notification message
     */
    function addNotification(message) {
        state.notifications.unshift(message);
        if (state.notifications.length > 10) {
            state.notifications.pop();
        }
        updateNotificationsUI();
    }

    // ---------------------------------------------------------------------
    // Theme Functions
    // ---------------------------------------------------------------------

    /**
     * Update the theme based on the current settings
     */
    function updateTheme() {
        document.documentElement.setAttribute('data-theme', state.settings.theme);
    }

    // ---------------------------------------------------------------------
    // Language Functions
    // ---------------------------------------------------------------------

    /**
     * Update the language based on the current settings
     */
    function updateLanguage() {
        // Update UI text based on the selected language
        // ... (language update logic)
    }

    // ---------------------------------------------------------------------
    // Initialization
    // ---------------------------------------------------------------------

    /**
     * Initialize the application
     */
    function init() {
        initDOM();
        updateTheme();
        updateLanguage();
        updateUI();
        startEngineTickers();
    }

    // Start the application when the DOM is loaded
    document.addEventListener('DOMContentLoaded', init);

})();
