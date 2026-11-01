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
    // UI Component Renderers
    // ---------------------------------------------------------------------

    /**
     * Render wallet balance information
     */
    function renderWallet() {
        if (!state.wallet.connected) {
            DOM.walletStatus.textContent = 'Not Connected';
            DOM.walletAddress.textContent = '—';
            DOM.walletBalance.textContent = '—';
            return;
        }

        DOM.walletStatus.textContent = 'Connected';
        DOM.walletAddress.textContent = `${state.wallet.address.slice(0, 6)}...${state.wallet.address.slice(-4)}`;
        DOM.walletBalance.textContent = `${state.wallet.balanceEth.toFixed(4)} ETH`;

        // Update token balances
        DOM.tokenBalances.innerHTML = '';
        state.wallet.tokens.forEach(token => {
            const tokenElement = document.createElement('div');
            tokenElement.className = 'token-balance';
            tokenElement.innerHTML = `
                <div class="token-symbol">${token.symbol}</div>
                <div class="token-name">${token.name}</div>
                <div class="token-balance-value">${token.balance.toFixed(4)}</div>
                <div class="token-value">$${(token.balance * token.price).toFixed(2)}</div>
            `;
            DOM.tokenBalances.appendChild(tokenElement);
        });
    }

    /**
     * Render market data
     */
    function renderMarket() {
        const pair = state.market.selectedPair;
        const pairData = PAIR_RATES[pair];

        DOM.marketPair.textContent = pair;
        DOM.marketPrice.textContent = `$${state.market.price.toFixed(pairData.decimals)}`;
        DOM.marketChange.textContent = `${state.market.change24h.toFixed(2)}%`;
        DOM.marketChange.className = state.market.change24h >= 0 ? 'positive' : 'negative';
        DOM.marketVolume.textContent = `$${(state.market.volume24h / 1000000).toFixed(2)}M`;
        DOM.marketHigh.textContent = `$${state.market.high24h.toFixed(pairData.decimals)}`;
        DOM.marketLow.textContent = `$${state.market.low24h.toFixed(pairData.decimals)}`;

        // Update chart
        renderChart();
    }

    /**
     * Render order book
     */
    function renderOrderBook() {
        DOM.orderBookBids.innerHTML = '';
        DOM.orderBookAsks.innerHTML = '';

        // Render bids
        state.orderBook.bids.slice(0, state.orderBook.maxDepth).forEach(bid => {
            const bidElement = document.createElement('div');
            bidElement.className = 'order-book-row';
            bidElement.innerHTML = `
                <div class="order-book-price">${bid.price.toFixed(2)}</div>
                <div class="order-book-amount">${bid.amount.toFixed(4)}</div>
                <div class="order-book-total">${bid.total.toFixed(4)}</div>
            `;
            DOM.orderBookBids.appendChild(bidElement);
        });

        // Render asks
        state.orderBook.asks.slice(0, state.orderBook.maxDepth).forEach(ask => {
            const askElement = document.createElement('div');
            askElement.className = 'order-book-row';
            askElement.innerHTML = `
                <div class="order-book-price">${ask.price.toFixed(2)}</div>
                <div class="order-book-amount">${ask.amount.toFixed(4)}</div>
                <div class="order-book-total">${ask.total.toFixed(4)}</div>
            `;
            DOM.orderBookAsks.appendChild(askElement);
        });
    }

    /**
     * Render transaction history
     */
    function renderTransactions() {
        DOM.transactionHistory.innerHTML = '';

        state.transactions.forEach(tx => {
            const txElement = document.createElement('div');
            txElement.className = 'transaction-row';
            txElement.innerHTML = `
                <div class="transaction-type">${tx.type}</div>
                <div class="transaction-description">${tx.description}</div>
                <div class="transaction-amount">${tx.amount}</div>
                <div class="transaction-status ${tx.status.toLowerCase()}">${tx.status}</div>
                <div class="transaction-timestamp">${new Date(tx.timestamp).toLocaleString()}</div>
            `;
            DOM.transactionHistory.appendChild(txElement);
        });
    }

    /**
     * Render portfolio
     */
    function renderPortfolio() {
        DOM.portfolioItems.innerHTML = '';

        state.portfolio.forEach(item => {
            const portfolioElement = document.createElement('div');
            portfolioElement.className = 'portfolio-item';
            portfolioElement.innerHTML = `
                <div class="portfolio-symbol">${item.symbol}</div>
                <div class="portfolio-name">${item.name}</div>
                <div class="portfolio-balance">${item.balance.toFixed(4)}</div>
                <div class="portfolio-value">$${item.value.toFixed(2)}</div>
                <div class="portfolio-allocation">${item.allocation.toFixed(1)}%</div>
            `;
            DOM.portfolioItems.appendChild(portfolioElement);
        });
    }

    /**
     * Render staking information
     */
    function renderStaking() {
        DOM.stakingBalance.textContent = `${state.staking.stakedOpus.toFixed(2)} OPUS`;
        DOM.stakingApy.textContent = `${state.staking.rewardRateApy.toFixed(1)}%`;
        DOM.stakingRewards.textContent = `${state.staking.pendingRewards.toFixed(2)} OPUS`;
        DOM.stakingLastClaimed.textContent = new Date(state.staking.lastClaimed).toLocaleString();
    }

    /**
     * Render notifications
     */
    function renderNotifications() {
        DOM.notifications.innerHTML = '';

        state.notifications.forEach(notification => {
            const notificationElement = document.createElement('div');
            notificationElement.className = `notification ${notification.type}`;
            notificationElement.innerHTML = `
                <div class="notification-message">${notification.message}</div>
                <div class="notification-timestamp">${new Date(notification.timestamp).toLocaleString()}</div>
            `;
            DOM.notifications.appendChild(notificationElement);
        });
    }

    // ---------------------------------------------------------------------
    // Chart Rendering
    // ---------------------------------------------------------------------

    /**
     * Render price chart using Canvas API
     */
    function renderChart() {
        const ctx = DOM.chartCanvas.getContext('2d');
        const width = DOM.chartCanvas.width;
        const height = DOM.chartCanvas.height;

        // Clear canvas
        ctx.clearRect(0, 0, width, height);

        // Draw chart background
        ctx.fillStyle = 'rgba(13, 20, 48, 0.6)';
        ctx.fillRect(0, 0, width, height);

        // Draw grid lines
        ctx.strokeStyle = 'rgba(255, 255, 255, 0.1)';
        ctx.lineWidth = 1;

        // Vertical grid lines
        for (let i = 0; i < 5; i++) {
            const x = (i * width) / 4;
            ctx.beginPath();
            ctx.moveTo(x, 0);
            ctx.lineTo(x, height);
            ctx.stroke();
        }

        // Horizontal grid lines
        for (let i = 0; i < 5; i++) {
            const y = (i * height) / 4;
            ctx.beginPath();
            ctx.moveTo(0, y);
            ctx.lineTo(width, y);
            ctx.stroke();
        }

        // Draw price line
        if (state.market.chartData.prices.length > 1) {
            ctx.strokeStyle = '#4f46e5';
            ctx.lineWidth = 2;
            ctx.beginPath();

            const minPrice = Math.min(...state.market.chartData.prices);
            const maxPrice = Math.max(...state.market.chartData.prices);
            const priceRange = maxPrice - minPrice;

            for (let i = 0; i < state.market.chartData.prices.length; i++) {
                const x = (i * width) / (state.market.chartData.prices.length - 1);
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

    // ---------------------------------------------------------------------
    // Data Fetchers
    // ---------------------------------------------------------------------

    /**
     * Fetch market data
     */
    function fetchMarketData() {
        // In a real application, this would fetch data from an API
        // For this demo, we'll simulate data updates
        const pair = state.market.selectedPair;
        const pairData = PAIR_RATES[pair];

        // Simulate price change
        const change = (Math.random() - 0.5) * 0.02;
        state.market.price = Math.max(0, state.market.price * (1 + change));
        state.market.change24h = change * 100;

        // Update chart data
        state.market.chartData.prices.push(state.market.price);
        if (state.market.chartData.prices.length > 100) {
            state.market.chartData.prices.shift();
        }

        // Update order book
        updateOrderBook();

        renderMarket();
    }

    /**
     * Update order book with simulated data
     */
    function updateOrderBook() {
        const pair = state.market.selectedPair;
        const pairData = PAIR_RATES[pair];

        // Clear existing order book
        state.orderBook.bids = [];
        state.orderBook.asks = [];

        // Generate bids
        for (let i = 0; i < state.orderBook.maxDepth; i++) {
            const price = state.market.price * (1 - (i + 1) * 0.001);
            const amount = Math.random() * 10;
            const total = price * amount;
            state.orderBook.bids.push({ price, amount, total });
        }

        // Generate asks
        for (let i = 0; i < state.orderBook.maxDepth; i++) {
            const price = state.market.price * (1 + (i + 1) * 0.001);
            const amount = Math.random() * 10;
            const total = price * amount;
            state.orderBook.asks.push({ price, amount, total });
        }

        // Sort bids and asks
        state.orderBook.bids.sort((a, b) => b.price - a.price);
        state.orderBook.asks.sort((a, b) => a.price - b.price);

        renderOrderBook();
    }

    /**
     * Fetch gas prices
     */
    function fetchGasPrices() {
        // In a real application, this would fetch data from an API
        // For this demo, we'll simulate gas price changes
        state.gas.slow = Math.max(10, state.gas.slow + (Math.random() - 0.5) * 2);
        state.gas.standard = Math.max(15, state.gas.standard + (Math.random() - 0.5) * 3);
        state.gas.fast = Math.max(20, state.gas.fast + (Math.random() - 0.5) * 4);

        // Update current gas price
        state.gas.current = state.gas.standard;

        // Update UI
        DOM.gasSlow.textContent = `${state.gas.slow} ${state.gas.unit}`;
        DOM.gasStandard.textContent = `${state.gas.standard} ${state.gas.unit}`;
        DOM.gasFast.textContent = `${state.gas.fast} ${state.gas.unit}`;
    }

    /**
     * Fetch staking data
     */
    function fetchStakingData() {
        // In a real application, this would fetch data from an API
        // For this demo, we'll simulate staking data changes
        state.staking.pendingRewards += state.staking.stakedOpus * (state.staking.rewardRateApy / 100 / 365);

        renderStaking();
    }

    // ---------------------------------------------------------------------
    // Event Handlers
    // ---------------------------------------------------------------------

    /**
     * Initialize DOM elements
     */
    function initDOM() {
        // Wallet section
        DOM.walletStatus = document.getElementById('wallet-status');
        DOM.walletAddress = document.getElementById('wallet-address');
        DOM.walletBalance = document.getElementById('wallet-balance');
        DOM.connectWalletBtn = document.getElementById('connect-wallet');
        DOM.tokenBalances = document.getElementById('token-balances');

        // Market section
        DOM.marketPair = document.getElementById('market-pair');
        DOM.marketPrice = document.getElementById('market-price');
        DOM.marketChange = document.getElementById('market-change');
        DOM.marketVolume = document.getElementById('market-volume');
        DOM.marketHigh = document.getElementById('market-high');
        DOM.marketLow = document.getElementById('market-low');
        DOM.chartCanvas = document.getElementById('chart-canvas');

        // Order book
        DOM.orderBookBids = document.getElementById('order-book-bids');
        DOM.orderBookAsks = document.getElementById('order-book-asks');

        // Transaction history
        DOM.transactionHistory = document.getElementById('transaction-history');

        // Portfolio
        DOM.portfolioItems = document.getElementById('portfolio-items');

        // Staking
        DOM.stakingBalance = document.getElementById('staking-balance');
        DOM.stakingApy = document.getElementById('staking-apy');
        DOM.stakingRewards = document.getElementById('staking-rewards');
        DOM.stakingLastClaimed = document.getElementById('staking-last-claimed');
        DOM.claimRewardsBtn = document.getElementById('claim-rewards');

        // Gas prices
        DOM.gasSlow = document.getElementById('gas-slow');
        DOM.gasStandard = document.getElementById('gas-standard');
        DOM.gasFast = document.getElementById('gas-fast');

        // Notifications
        DOM.notifications = document.getElementById('notifications');

        // Settings
        DOM.themeToggle = document.getElementById('theme-toggle');
        DOM.soundsToggle = document.getElementById('sounds-toggle');

        // Initialize chart canvas
        DOM.chartCanvas.width = DOM.chartCanvas.parentElement.clientWidth;
        DOM.chartCanvas.height = DOM.chartCanvas.parentElement.clientHeight;
    }

    /**
     * Connect wallet handler
     */
    function connectWallet() {
        // In a real application, this would connect to a wallet provider
        // For this demo, we'll simulate a wallet connection
        state.wallet.connected = true;
        state.wallet.address = '0x' + Math.random().toString(16).slice(2, 12);

        // Add a notification
        state.notifications.push({
            type: 'success',
            message: 'Wallet connected successfully',
            timestamp: Date.now()
        });

        // Play a tone
        playTone(440, 200);

        // Update UI
        renderWallet();
        renderNotifications();
    }

    /**
     * Claim rewards handler
     */
    function claimRewards() {
        if (state.staking.pendingRewards <= 0) return;

        // In a real application, this would send a transaction to claim rewards
        // For this demo, we'll simulate claiming rewards
        const rewards = state.staking.pendingRewards;
        state.staking.pendingRewards = 0;
        state.staking.lastClaimed = Date.now();

        // Add a notification
        state.notifications.push({
            type: 'success',
            message: `Claimed ${rewards.toFixed(2)} OPUS rewards`,
            timestamp: Date.now()
        });

        // Play a tone
        playTone(523.25, 200);

        // Update UI
        renderStaking();
        renderNotifications();
    }

    /**
     * Toggle theme
     */
    function toggleTheme() {
        state.settings.theme = state.settings.theme === 'dark' ? 'light' : 'dark';
        document.documentElement.setAttribute('data-theme', state.settings.theme);

        // Play a tone
        playTone(330, 100);
    }

    /**
     * Toggle sounds
     */
    function toggleSounds() {
        state.settings.enableSounds = !state.settings.enableSounds;

        // Play a tone if sounds are enabled
        if (state.settings.enableSounds) {
            playTone(261.63, 100);
        }
    }

    // ---------------------------------------------------------------------
    // Initialization
    // ---------------------------------------------------------------------

    /**
     * Initialize the application
     */
    function init() {
        // Initialize DOM elements
        initDOM();

        // Set initial theme
        document.documentElement.setAttribute('data-theme', state.settings.theme);

        // Render initial UI
        renderWallet();
        renderMarket();
        renderOrderBook();
        renderTransactions();
        renderPortfolio();
        renderStaking();
        renderNotifications();

        // Set up event listeners
        DOM.connectWalletBtn.addEventListener('click', connectWallet);
        DOM.claimRewardsBtn.addEventListener('click', claimRewards);
        DOM.themeToggle.addEventListener('click', toggleTheme);
        DOM.soundsToggle.addEventListener('click', toggleSounds);

        // Set up data fetchers
        marketInterval = setInterval(fetchMarketData, state.settings.autoRefreshInterval);
        gasInterval = setInterval(fetchGasPrices, state.settings.autoRefreshInterval * 2);
        stakingInterval = setInterval(fetchStakingData, state.settings.autoRefreshInterval * 3);

        // Initial data fetch
        fetchMarketData();
        fetchGasPrices();
        fetchStakingData();
    }

    // Start the application
    document.addEventListener('DOMContentLoaded', init);

    // Expose state and functions for debugging
    window.MagnumOpus = {
        state,
        renderWallet,
        renderMarket,
        renderOrderBook,
        renderTransactions,
        renderPortfolio,
        renderStaking,
        renderNotifications,
        playTone
    };

})();