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
            portfolioTable: document.getElementById('portfolio-table'),
            transactionsTable: document.getElementById('transactions-table'),
            notificationsContainer: document.getElementById('notifications-container'),
            settingsModal: document.getElementById('settings-modal'),
            settingsForm: document.getElementById('settings-form'),
            themeToggle: document.getElementById('theme-toggle'),
            currencySelect: document.getElementById('currency-select'),
            languageSelect: document.getElementById('language-select'),
            slippageInput: document.getElementById('slippage-input'),
            soundsToggle: document.getElementById('sounds-toggle'),
            refreshIntervalInput: document.getElementById('refresh-interval-input'),
            saveSettingsBtn: document.getElementById('save-settings-btn'),
            cancelSettingsBtn: document.getElementById('cancel-settings-btn'),
            chartCanvas: document.getElementById('price-chart'),
            buyForm: document.getElementById('buy-form'),
            sellForm: document.getElementById('sell-form'),
            buyAmountInput: document.getElementById('buy-amount-input'),
            sellAmountInput: document.getElementById('sell-amount-input'),
            buyPriceInput: document.getElementById('buy-price-input'),
            sellPriceInput: document.getElementById('sell-price-input'),
            buyTotalInput: document.getElementById('buy-total-input'),
            sellTotalInput: document.getElementById('sell-total-input'),
            buySubmitBtn: document.getElementById('buy-submit-btn'),
            sellSubmitBtn: document.getElementById('sell-submit-btn'),
            stakingBalance: document.getElementById('staking-balance'),
            stakingRewards: document.getElementById('staking-rewards'),
            stakeForm: document.getElementById('stake-form'),
            unstakeForm: document.getElementById('unstake-form'),
            stakeAmountInput: document.getElementById('stake-amount-input'),
            unstakeAmountInput: document.getElementById('unstake-amount-input'),
            stakeSubmitBtn: document.getElementById('stake-submit-btn'),
            unstakeSubmitBtn: document.getElementById('unstake-submit-btn'),
            claimRewardsBtn: document.getElementById('claim-rewards-btn')
        };
    }

    function initChartData() {
        const now = new Date();
        const labels = [];
        const prices = [];

        for (let i = 0; i < 60; i++) {
            const time = new Date(now.getTime() - (60 - i) * 60 * 1000);
            labels.push(time.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }));
            prices.push(state.market.price);
        }

        state.market.chartData.labels = labels;
        state.market.chartData.prices = prices;
    }

    function setupEventListeners() {
        DOM.connectBtn.addEventListener('click', connectWallet);
        DOM.pairSelect.addEventListener('change', changePair);
        DOM.themeToggle.addEventListener('change', toggleTheme);
        DOM.currencySelect.addEventListener('change', changeCurrency);
        DOM.languageSelect.addEventListener('change', changeLanguage);
        DOM.slippageInput.addEventListener('change', changeSlippage);
        DOM.soundsToggle.addEventListener('change', toggleSounds);
        DOM.refreshIntervalInput.addEventListener('change', changeRefreshInterval);
        DOM.saveSettingsBtn.addEventListener('click', saveSettings);
        DOM.cancelSettingsBtn.addEventListener('click', cancelSettings);
        DOM.buyForm.addEventListener('submit', submitBuyOrder);
        DOM.sellForm.addEventListener('submit', submitSellOrder);
        DOM.stakeForm.addEventListener('submit', submitStake);
        DOM.unstakeForm.addEventListener('submit', submitUnstake);
        DOM.claimRewardsBtn.addEventListener('click', claimRewards);

        // Add event listeners for input fields to update totals
        DOM.buyAmountInput.addEventListener('input', updateBuyTotal);
        DOM.buyPriceInput.addEventListener('input', updateBuyTotal);
        DOM.sellAmountInput.addEventListener('input', updateSellTotal);
        DOM.sellPriceInput.addEventListener('input', updateSellTotal);
    }

    function initializeChart() {
        const ctx = DOM.chartCanvas.getContext('2d');
        priceChart = new Chart(ctx, {
            type: 'line',
            data: {
                labels: state.market.chartData.labels,
                datasets: [{
                    label: 'Price',
                    data: state.market.chartData.prices,
                    borderColor: '#4f46e5',
                    backgroundColor: 'rgba(79, 70, 229, 0.1)',
                    borderWidth: 2,
                    tension: 0.4,
                    pointRadius: 0,
                    pointHoverRadius: 0
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                scales: {
                    x: {
                        grid: {
                            display: false
                        }
                    },
                    y: {
                        grid: {
                            color: 'rgba(255, 255, 255, 0.1)'
                        }
                    }
                },
                plugins: {
                    legend: {
                        display: false
                    }
                }
            }
        });
    }

    function populateOrderBook() {
        const pair = PAIR_RATES[state.market.selectedPair];
        const price = pair.price;
        const decimals = pair.decimals;

        // Generate random order book data
        const bids = [];
        const asks = [];

        for (let i = 0; i < state.orderBook.maxDepth; i++) {
            const bidPrice = (price - (i * 0.01)).toFixed(decimals);
            const bidAmount = (Math.random() * 10).toFixed(4);
            bids.push({ price: bidPrice, amount: bidAmount });

            const askPrice = (price + (i * 0.01)).toFixed(decimals);
            const askAmount = (Math.random() * 10).toFixed(4);
            asks.push({ price: askPrice, amount: askAmount });
        }

        state.orderBook.bids = bids;
        state.orderBook.asks = asks;
    }

    function renderOrderBook() {
        DOM.orderBookBids.innerHTML = '';
        DOM.orderBookAsks.innerHTML = '';

        state.orderBook.bids.forEach(bid => {
            const bidElement = document.createElement('div');
            bidElement.className = 'orderbook-row';
            bidElement.innerHTML = `
                <div class="orderbook-price">${bid.price}</div>
                <div class="orderbook-amount">${bid.amount}</div>
                <div class="orderbook-total">${(bid.price * bid.amount).toFixed(2)}</div>
            `;
            DOM.orderBookBids.appendChild(bidElement);
        });

        state.orderBook.asks.forEach(ask => {
            const askElement = document.createElement('div');
            askElement.className = 'orderbook-row';
            askElement.innerHTML = `
                <div class="orderbook-price">${ask.price}</div>
                <div class="orderbook-amount">${ask.amount}</div>
                <div class="orderbook-total">${(ask.price * ask.amount).toFixed(2)}</div>
            `;
            DOM.orderBookAsks.appendChild(askElement);
        });
    }

    function renderPortfolio() {
        DOM.portfolioTable.innerHTML = '';

        state.portfolio.forEach(asset => {
            const row = document.createElement('tr');
            row.innerHTML = `
                <td>${asset.symbol}</td>
                <td>${asset.name}</td>
                <td>${asset.balance.toFixed(4)}</td>
                <td>${asset.price.toFixed(2)}</td>
                <td>${asset.value.toFixed(2)}</td>
                <td>${asset.allocation.toFixed(1)}%</td>
            `;
            DOM.portfolioTable.appendChild(row);
        });
    }

    function renderTransactions() {
        DOM.transactionsTable.innerHTML = '';

        state.transactions.forEach(tx => {
            const row = document.createElement('tr');
            row.innerHTML = `
                <td>${tx.type}</td>
                <td>${tx.pair}</td>
                <td>${tx.amount.toFixed(4)}</td>
                <td>${tx.price.toFixed(2)}</td>
                <td>${tx.total.toFixed(2)}</td>
                <td>${tx.timestamp.toLocaleTimeString()}</td>
            `;
            DOM.transactionsTable.appendChild(row);
        });
    }

    function updateUI() {
        // Update wallet information
        if (state.wallet.connected) {
            DOM.connectBtn.textContent = 'Disconnect Wallet';
            DOM.walletAddress.textContent = state.wallet.address;
            DOM.walletBalance.textContent = `${state.wallet.balanceEth.toFixed(4)} ETH`;
        } else {
            DOM.connectBtn.textContent = 'Connect Wallet';
            DOM.walletAddress.textContent = 'Not Connected';
            DOM.walletBalance.textContent = '0.0000 ETH';
        }

        // Update gas price
        DOM.gasPrice.textContent = `${state.gas.current} Gwei`;

        // Update market information
        DOM.currentPrice.textContent = `${state.market.price.toFixed(2)} USD`;
        DOM.priceChange.textContent = `${state.market.change24h.toFixed(2)}%`;

        // Update staking information
        DOM.stakingBalance.textContent = `${state.staking.stakedOpus.toFixed(2)} OPUS`;
        DOM.stakingRewards.textContent = `${state.staking.pendingRewards.toFixed(2)} OPUS`;

        // Update chart
        if (priceChart) {
            priceChart.update();
        }
    }

    function startSimulationEngines() {
        // Simulate market data updates
        marketInterval = setInterval(() => {
            simulateMarketData();
            updateUI();
        }, state.settings.autoRefreshInterval);

        // Simulate gas price updates
        gasInterval = setInterval(() => {
            simulateGasPrice();
            updateUI();
        }, 15000);

        // Simulate order book updates
        orderBookInterval = setInterval(() => {
            populateOrderBook();
            renderOrderBook();
        }, 5000);
    }

    function simulateMarketData() {
        const pair = PAIR_RATES[state.market.selectedPair];
        const price = pair.price;
        const decimals = pair.decimals;

        // Simulate price change
        const change = (Math.random() * 2 - 1) * 0.01;
        const newPrice = price + change;
        pair.price = newPrice;
        state.market.price = newPrice;

        // Simulate 24h change
        state.market.change24h += change;

        // Simulate volume
        state.market.volume24h += Math.random() * 1000000;

        // Update high and low
        if (newPrice > state.market.high24h) {
            state.market.high24h = newPrice;
        } else if (newPrice < state.market.low24h) {
            state.market.low24h = newPrice;
        }

        // Update chart data
        const now = new Date();
        const timeLabel = now.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
        state.market.chartData.labels.push(timeLabel);
        state.market.chartData.prices.push(newPrice);

        // Keep only the last 60 data points
        if (state.market.chartData.labels.length > 60) {
            state.market.chartData.labels.shift();
            state.market.chartData.prices.shift();
        }
    }

    function simulateGasPrice() {
        // Simulate gas price changes
        state.gas.slow = Math.max(10, state.gas.slow + (Math.random() * 2 - 1));
        state.gas.standard = Math.max(15, state.gas.standard + (Math.random() * 2 - 1));
        state.gas.fast = Math.max(20, state.gas.fast + (Math.random() * 2 - 1));
        state.gas.current = state.gas.standard;
    }

    function setupWeb3Listeners() {
        // In a real implementation, this would set up listeners for Web3 events
        // For this simulation, we'll just log to the console
        console.log('Web3 listeners set up');
    }

    function addNotification(title, message, type) {
        const notification = {
            id: Date.now(),
            title,
            message,
            type,
            timestamp: new Date()
        };

        state.notifications.unshift(notification);

        // Keep only the last 10 notifications
        if (state.notifications.length > 10) {
            state.notifications.pop();
        }

        renderNotifications();

        // Play sound if enabled
        if (state.settings.enableSounds) {
            playNotificationSound();
        }
    }

    function renderNotifications() {
        DOM.notificationsContainer.innerHTML = '';

        state.notifications.forEach(notification => {
            const notificationElement = document.createElement('div');
            notificationElement.className = `notification ${notification.type}`;
            notificationElement.innerHTML = `
                <div class="notification-title">${notification.title}</div>
                <div class="notification-message">${notification.message}</div>
                <div class="notification-time">${notification.timestamp.toLocaleTimeString()}</div>
            `;
            DOM.notificationsContainer.appendChild(notificationElement);
        });
    }

    function playNotificationSound() {
        if (!audioCtx) {
            audioCtx = new (window.AudioContext || window.webkitAudioContext)();
        }

        const oscillator = audioCtx.createOscillator();
        const gainNode = audioCtx.createGain();

        oscillator.connect(gainNode);
        gainNode.connect(audioCtx.destination);

        oscillator.type = 'sine';
        oscillator.frequency.value = 800;
        gainNode.gain.value = 0.1;

        oscillator.start();
        oscillator.stop(audioCtx.currentTime + 0.1);
    }

    function connectWallet() {
        if (state.wallet.connected) {
            state.wallet.connected = false;
            state.wallet.address = null;
            addNotification('Wallet Disconnected', 'Your wallet has been disconnected.', 'info');
        } else {
            // Simulate wallet connection
            state.wallet.connected = true;
            state.wallet.address = '0x' + Math.random().toString(16).substr(2, 40);
            addNotification('Wallet Connected', `Connected to wallet: ${state.wallet.address}`, 'success');
        }

        updateUI();
    }

    function changePair(event) {
        const selectedPair = event.target.value;
        state.market.selectedPair = selectedPair;
        state.market.price = PAIR_RATES[selectedPair].price;
        state.market.change24h = 0;
        state.market.volume24h = 0;
        state.market.high24h = state.market.price;
        state.market.low24h = state.market.price;

        // Reset chart data
        initChartData();
        if (priceChart) {
            priceChart.data.labels = state.market.chartData.labels;
            priceChart.data.datasets[0].data = state.market.chartData.prices;
            priceChart.update();
        }

        // Repopulate order book
        populateOrderBook();
        renderOrderBook();

        updateUI();
    }

    function toggleTheme(event) {
        const theme = event.target.checked ? 'dark' : 'light';
        state.settings.theme = theme;
        document.documentElement.setAttribute('data-theme', theme);
    }

    function changeCurrency(event) {
        state.settings.currency = event.target.value;
    }

    function changeLanguage(event) {
        state.settings.language = event.target.value;
    }

    function changeSlippage(event) {
        state.settings.slippageTolerance = parseFloat(event.target.value);
    }

    function toggleSounds(event) {
        state.settings.enableSounds = event.target.checked;
    }

    function changeRefreshInterval(event) {
        state.settings.autoRefreshInterval = parseInt(event.target.value);
        clearInterval(marketInterval);
        marketInterval = setInterval(() => {
            simulateMarketData();
            updateUI();
        }, state.settings.autoRefreshInterval);
    }

    function saveSettings(event) {
        event.preventDefault();
        saveSettingsToStorage();
        addNotification('Settings Saved', 'Your settings have been saved.', 'success');
        DOM.settingsModal.style.display = 'none';
    }

    function cancelSettings(event) {
        event.preventDefault();
        DOM.settingsModal.style.display = 'none';
    }

    function submitBuyOrder(event) {
        event.preventDefault();

        const amount = parseFloat(DOM.buyAmountInput.value);
        const price = parseFloat(DOM.buyPriceInput.value);
        const total = amount * price;

        if (isNaN(amount) || isNaN(price) || amount <= 0 || price <= 0) {
            addNotification('Invalid Order', 'Please enter valid amount and price.', 'error');
            return;
        }

        if (state.wallet.balanceUsdt < total) {
            addNotification('Insufficient Funds', 'You do not have enough USDT to place this order.', 'error');
            return;
        }

        // Simulate order execution
        const pair = PAIR_RATES[state.market.selectedPair];
        const baseToken = state.wallet.tokens.find(token => token.symbol === pair.base);
        const quoteToken = state.wallet.tokens.find(token => token.symbol === pair.quote);

        baseToken.balance += amount;
        quoteToken.balance -= total;

        // Update portfolio
        updatePortfolio();

        // Add transaction
        state.transactions.unshift({
            type: 'Buy',
            pair: state.market.selectedPair,
            amount,
            price,
            total,
            timestamp: new Date()
        });

        // Keep only the last 20 transactions
        if (state.transactions.length > 20) {
            state.transactions.pop();
        }

        renderTransactions();
        updateUI();

        addNotification('Order Executed', `Bought ${amount.toFixed(4)} ${pair.base} at ${price.toFixed(2)} ${pair.quote}`, 'success');

        // Reset form
        DOM.buyForm.reset();
        DOM.buyTotalInput.value = '0.00';
    }

    function submitSellOrder(event) {
        event.preventDefault();

        const amount = parseFloat(DOM.sellAmountInput.value);
        const price = parseFloat(DOM.sellPriceInput.value);
        const total = amount * price;

        if (isNaN(amount) || isNaN(price) || amount <= 0 || price <= 0) {
            addNotification('Invalid Order', 'Please enter valid amount and price.', 'error');
            return;
        }

        const pair = PAIR_RATES[state.market.selectedPair];
        const baseToken = state.wallet.tokens.find(token => token.symbol === pair.base);

        if (baseToken.balance < amount) {
            addNotification('Insufficient Funds', `You do not have enough ${pair.base} to place this order.`, 'error');
            return;
        }

        // Simulate order execution
        const quoteToken = state.wallet.tokens.find(token => token.symbol === pair.quote);

        baseToken.balance -= amount;
        quoteToken.balance += total;

        // Update portfolio
        updatePortfolio();

        // Add transaction
        state.transactions.unshift({
            type: 'Sell',
            pair: state.market.selectedPair,
            amount,
            price,
            total,
            timestamp: new Date()
        });

        // Keep only the last 20 transactions
        if (state.transactions.length > 20) {
            state.transactions.pop();
        }

        renderTransactions();
        updateUI();

        addNotification('Order Executed', `Sold ${amount.toFixed(4)} ${pair.base} at ${price.toFixed(2)} ${pair.quote}`, 'success');

        // Reset form
        DOM.sellForm.reset();
        DOM.sellTotalInput.value = '0.00';
    }

    function updateBuyTotal() {
        const amount = parseFloat(DOM.buyAmountInput.value) || 0;
        const price = parseFloat(DOM.buyPriceInput.value) || 0;
        const total = amount * price;
        DOM.buyTotalInput.value = total.toFixed(2);
    }

    function updateSellTotal() {
        const amount = parseFloat(DOM.sellAmountInput.value) || 0;
        const price = parseFloat(DOM.sellPriceInput.value) || 0;
        const total = amount * price;
        DOM.sellTotalInput.value = total.toFixed(2);
    }

    function submitStake(event) {
        event.preventDefault();

        const amount = parseFloat(DOM.stakeAmountInput.value);

        if (isNaN(amount) || amount <= 0) {
            addNotification('Invalid Stake', 'Please enter a valid amount to stake.', 'error');
            return;
        }

        const opusToken = state.wallet.tokens.find(token => token.symbol === 'OPUS');

        if (opusToken.balance < amount) {
            addNotification('Insufficient Funds', 'You do not have enough OPUS to stake this amount.', 'error');
            return;
        }

        // Simulate staking
        opusToken.balance -= amount;
        state.staking.stakedOpus += amount;

        // Update portfolio
        updatePortfolio();

        updateUI();

        addNotification('Stake Successful', `Staked ${amount.toFixed(2)} OPUS`, 'success');

        // Reset form
        DOM.stakeForm.reset();
    }

    function submitUnstake(event) {
        event.preventDefault();

        const amount = parseFloat(DOM.unstakeAmountInput.value);

        if (isNaN(amount) || amount <= 0) {
            addNotification('Invalid Unstake', 'Please enter a valid amount to unstake.', 'error');
            return;
        }

        if (state.staking.stakedOpus < amount) {
            addNotification('Insufficient Stake', 'You do not have enough OPUS staked to unstake this amount.', 'error');
            return;
        }

        // Simulate unstaking
        const opusToken = state.wallet.tokens.find(token => token.symbol === 'OPUS');
        opusToken.balance += amount;
        state.staking.stakedOpus -= amount;

        // Update portfolio
        updatePortfolio();

        updateUI();

        addNotification('Unstake Successful', `Unstaked ${amount.toFixed(2)} OPUS`, 'success');

        // Reset form
        DOM.unstakeForm.reset();
    }

    function claimRewards() {
        if (state.staking.pendingRewards <= 0) {
            addNotification('No Rewards', 'You have no pending rewards to claim.', 'info');
            return;
        }

        // Simulate claiming rewards
        const opusToken = state.wallet.tokens.find(token => token.symbol === 'OPUS');
        opusToken.balance += state.staking.pendingRewards;
        state.staking.pendingRewards = 0;

        // Update portfolio
        updatePortfolio();

        updateUI();

        addNotification('Rewards Claimed', `Claimed ${state.staking.pendingRewards.toFixed(2)} OPUS rewards`, 'success');
    }

    function updatePortfolio() {
        const totalValue = state.wallet.tokens.reduce((sum, token) => {
            const pair = Object.values(PAIR_RATES).find(p => p.base === token.symbol);
            const price = pair ? pair.price : 0;
            return sum + (token.balance * price);
        }, 0);

        state.portfolio = state.wallet.tokens.map(token => {
            const pair = Object.values(PAIR_RATES).find(p => p.base === token.symbol);
            const price = pair ? pair.price : 0;
            const value = token.balance * price;
            const allocation = (value / totalValue) * 100;

            return {
                symbol: token.symbol,
                name: token.name,
                balance: token.balance,
                price,
                value,
                allocation
            };
        });

        renderPortfolio();
    }

    // Initialize the application
    init();

    // Expose functions to global scope for debugging
    window.magnumOpus = {
        state,
        addNotification,
        updateUI,
        simulateMarketData,
        simulateGasPrice,
        populateOrderBook,
        renderOrderBook,
        renderPortfolio,
        renderTransactions,
        updatePortfolio
    };

})();