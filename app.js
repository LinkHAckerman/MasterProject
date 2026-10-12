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
            portfolioContainer: document.getElementById('portfolio-container'),
            transactionsContainer: document.getElementById('transactions-container'),
            notificationsContainer: document.getElementById('notifications-container'),
            settingsBtn: document.getElementById('settings-btn'),
            themeToggle: document.getElementById('theme-toggle'),
            currencySelect: document.getElementById('currency-select'),
            slippageInput: document.getElementById('slippage-input'),
            soundToggle: document.getElementById('sound-toggle'),
            refreshIntervalInput: document.getElementById('refresh-interval-input'),
            stakingContainer: document.getElementById('staking-container'),
            chartCanvas: document.getElementById('price-chart'),
            volumeDisplay: document.getElementById('volume-display'),
            highLowDisplay: document.getElementById('high-low-display')
        };
    }

    function initChartData() {
        const now = Date.now();
        for (let i = 0; i < 50; i++) {
            const time = now - (49 - i) * 60000;
            state.market.chartData.labels.push(formatTime(new Date(time)));
            state.market.chartData.prices.push((3450 + Math.sin(i / 5) * 50 + Math.random() * 10).toFixed(2));
        }
    }

    function setupEventListeners() {
        if (DOM.connectBtn) DOM.connectBtn.addEventListener('click', toggleWalletConnection);
        if (DOM.pairSelect) DOM.pairSelect.addEventListener('change', onPairChange);
        if (DOM.settingsBtn) DOM.settingsBtn.addEventListener('click', openSettingsModal);
        if (DOM.themeToggle) DOM.themeToggle.addEventListener('change', toggleTheme);
        if (DOM.currencySelect) DOM.currencySelect.addEventListener('change', updateCurrency);
        if (DOM.slippageInput) DOM.slippageInput.addEventListener('change', updateSlippage);
        if (DOM.soundToggle) DOM.soundToggle.addEventListener('change', toggleSounds);
        if (DOM.refreshIntervalInput) DOM.refreshIntervalInput.addEventListener('change', updateRefreshInterval);
    }

    function initializeChart() {
        if (!DOM.chartCanvas) return;
        const ctx = DOM.chartCanvas.getContext('2d');
        priceChart = new Chart(ctx, {
            type: 'line',
            data: {
                labels: state.market.chartData.labels,
                datasets: [{
                    label: state.market.selectedPair,
                    data: state.market.chartData.prices,
                    borderColor: getComputedStyle(document.documentElement).getPropertyValue('--accent-cyan').trim(),
                    backgroundColor: 'rgba(56, 189, 248, 0.1)',
                    borderWidth: 2,
                    pointRadius: 0,
                    fill: true,
                    tension: 0.3
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                animation: false,
                scales: {
                    x: {
                        ticks: { color: '#94a3b8' },
                        grid: { display: false }
                    },
                    y: {
                        ticks: { color: '#94a3b8' },
                        grid: { color: 'rgba(56, 189, 248, 0.05)' }
                    }
                },
                plugins: {
                    legend: { display: false },
                    tooltip: {
                        mode: 'index',
                        intersect: false
                    }
                },
                interaction: {
                    mode: 'nearest',
                    axis: 'x',
                    intersect: false
                }
            }
        });
    }

    function populateOrderBook() {
        const pair = state.market.selectedPair;
        const rate = PAIR_RATES[pair]?.price || 3450.75;
        const spread = rate * 0.001;
        state.orderBook.bids = [];
        state.orderBook.asks = [];
        for (let i = 0; i < state.orderBook.maxDepth; i++) {
            const bidPrice = rate - spread * (i + 1);
            const askPrice = rate + spread * (i + 1);
            const bidSize = (Math.random() * 2 + 0.5).toFixed(3);
            const askSize = (Math.random() * 2 + 0.5).toFixed(3);
            state.orderBook.bids.push({ price: bidPrice.toFixed(2), size: bidSize });
            state.orderBook.asks.push({ price: askPrice.toFixed(2), size: askSize });
        }
    }

    function renderOrderBook() {
        if (!DOM.orderBookBids || !DOM.orderBookAsks) return;
        DOM.orderBookBids.innerHTML = '';
        DOM.orderBookAsks.innerHTML = '';
        state.orderBook.bids.slice().reverse().forEach(bid => {
            const row = document.createElement('div');
            row.className = 'orderbook-row';
            row.innerHTML = `<span class="price">${bid.price}</span><span class="size">${bid.size}</span>`;
            DOM.orderBookBids.appendChild(row);
        });
        state.orderBook.asks.forEach(ask => {
            const row = document.createElement('div');
            row.className = 'orderbook-row';
            row.innerHTML = `<span class="price">${ask.price}</span><span class="size">${ask.size}</span>`;
            DOM.orderBookAsks.appendChild(row);
        });
    }

    function renderPortfolio() {
        if (!DOM.portfolioContainer) return;
        DOM.portfolioContainer.innerHTML = '';
        state.portfolio.forEach(asset => {
            const item = document.createElement('div');
            item.className = 'portfolio-item';
            item.innerHTML = `
                <div class="asset-info">
                    <span class="symbol">${asset.symbol}</span>
                    <span class="name">${asset.name}</span>
                </div>
                <div class="asset-value">
                    <span class="amount">${asset.balance.toFixed(4)}</span>
                    <span class="usd-value">$${asset.value.toLocaleString()}</span>
                </div>
                <div class="allocation-bar">
                    <div class="allocation-fill" style="width: ${asset.allocation}%"></div>
                </div>
            `;
            DOM.portfolioContainer.appendChild(item);
        });
    }

    function renderTransactions() {
        if (!DOM.transactionsContainer) return;
        DOM.transactionsContainer.innerHTML = '';
        state.transactions.slice().reverse().slice(0, 10).forEach(tx => {
            const item = document.createElement('div');
            item.className = `transaction-item ${tx.status}`;
            item.innerHTML = `
                <div class="tx-hash">${tx.hash?.substring(0, 10)}...${tx.hash?.substring(tx.hash.length - 8)}</div>
                <div class="tx-details">
                    <span class="tx-type ${tx.type}">${tx.type}</span>
                    <span class="tx-amount">${tx.amount} ${tx.token}</span>
                </div>
                <div class="tx-time">${formatTimeAgo(tx.timestamp)}</div>
            `;
            DOM.transactionsContainer.appendChild(item);
        });
    }

    function updateUI() {
        if (DOM.walletAddress) DOM.walletAddress.textContent = state.wallet.address || 'Not Connected';
        if (DOM.walletBalance) DOM.walletBalance.textContent = `$${state.wallet.balanceUsdt.toLocaleString()}`;
        if (DOM.gasPrice) DOM.gasPrice.textContent = `${state.gas.current} Gwei`;
        if (DOM.currentPrice) DOM.currentPrice.textContent = formatPrice(state.market.price);
        if (DOM.priceChange) {
            DOM.priceChange.textContent = `${state.market.change24h > 0 ? '+' : ''}${state.market.change24h}%`;
            DOM.priceChange.className = `price-change ${state.market.change24h >= 0 ? 'positive' : 'negative'}`;
        }
        if (DOM.volumeDisplay) DOM.volumeDisplay.textContent = `Vol: $${state.market.volume24h.toLocaleString()}`;
        if (DOM.highLowDisplay) DOM.highLowDisplay.textContent = `H: ${formatPrice(state.market.high24h)} L: ${formatPrice(state.market.low24h)}`;
        if (DOM.pairSelect) DOM.pairSelect.value = state.market.selectedPair;
        updateStakingDisplay();
    }

    function updateStakingDisplay() {
        if (!DOM.stakingContainer) return;
        DOM.stakingContainer.innerHTML = `
            <div class="staking-summary">
                <div class="staked-amount">
                    <span class="label">Staked OPUS</span>
                    <span class="value">${state.staking.stakedOpus.toFixed(2)}</span>
                </div>
                <div class="reward-info">
                    <span class="apy">APY: ${state.staking.rewardRateApy}%</span>
                    <span class="pending">Pending: ${state.staking.pendingRewards.toFixed(4)} OPUS</span>
                </div>
            </div>
        `;
    }

    function startSimulationEngines() {
        marketInterval = setInterval(simulateMarketData, state.settings.autoRefreshInterval);
        gasInterval = setInterval(simulateGasData, 15000);
        orderBookInterval = setInterval(() => {
            populateOrderBook();
            renderOrderBook();
        }, 5000);
    }

    function simulateMarketData() {
        const pair = state.market.selectedPair;
        const rate = PAIR_RATES[pair]?.price || 3450.75;
        const volatility = 0.02;
        const change = (Math.random() - 0.5) * volatility * rate;
        state.market.price += change;
        state.market.change24h = ((state.market.price - rate + change) / rate * 100).toFixed(2);
        state.market.high24h = Math.max(state.market.high24h, state.market.price);
        state.market.low24h = Math.min(state.market.low24h, state.market.price);
        state.market.volume24h += Math.random() * 1000000;
        updateChart();
        updateUI();
    }

    function simulateGasData() {
        state.gas.slow = Math.floor(Math.random() * 5 + 10);
        state.gas.standard = Math.floor(Math.random() * 5 + 15);
        state.gas.fast = Math.floor(Math.random() * 5 + 20);
        state.gas.current = state.gas.standard;
        if (DOM.gasPrice) DOM.gasPrice.textContent = `${state.gas.current} Gwei`;
    }

    function updateChart() {
        if (!priceChart) return;
        const now = new Date();
        state.market.chartData.labels.push(formatTime(now));
        state.market.chartData.prices.push(state.market.price.toFixed(2));
        if (state.market.chartData.labels.length > 100) {
            state.market.chartData.labels.shift();
            state.market.chartData.prices.shift();
        }
        priceChart.data.labels = state.market.chartData.labels;
        priceChart.data.datasets[0].data = state.market.chartData.prices;
        priceChart.update('none');
    }

    function toggleWalletConnection() {
        if (state.wallet.connected) {
            disconnectWallet();
        } else {
            connectWallet();
        }
    }

    function connectWallet() {
        state.wallet.connected = true;
        state.wallet.address = '0x' + Math.random().toString(16).substring(2, 18) + '...';
        state.wallet.balanceEth = (Math.random() * 20 + 5).toFixed(3);
        state.wallet.balanceUsdt = (Math.random() * 50000 + 10000).toFixed(2);
        updateUI();
        addNotification('Wallet Connected', `Connected to ${state.wallet.address}`, 'success');
        playSound('connect');
    }

    function disconnectWallet() {
        state.wallet.connected = false;
        state.wallet.address = null;
        updateUI();
        addNotification('Wallet Disconnected', 'Your wallet has been disconnected.', 'info');
        playSound('disconnect');
    }

    function onPairChange() {
        if (!DOM.pairSelect) return;
        state.market.selectedPair = DOM.pairSelect.value;
        const rate = PAIR_RATES[state.market.selectedPair]?.price || 3450.75;
        state.market.price = rate;
        state.market.change24h = (Math.random() * 10 - 5).toFixed(2);
        populateOrderBook();
        renderOrderBook();
        updateChart();
        updateUI();
        addNotification('Pair Changed', `Now viewing ${state.market.selectedPair}`, 'info');
    }

    function openSettingsModal() {
        addNotification('Settings', 'Opening settings panel...', 'info');
    }

    function toggleTheme() {
        if (!DOM.themeToggle) return;
        state.settings.theme = DOM.themeToggle.checked ? 'light' : 'dark';
        document.body.className = state.settings.theme;
        saveSettingsToStorage();
        addNotification('Theme Changed', `Switched to ${state.settings.theme} mode.`, 'info');
    }

    function updateCurrency() {
        if (!DOM.currencySelect) return;
        state.settings.currency = DOM.currencySelect.value;
        saveSettingsToStorage();
        updateUI();
        addNotification('Currency Updated', `Display currency set to ${state.settings.currency}.`, 'info');
    }

    function updateSlippage() {
        if (!DOM.slippageInput) return;
        state.settings.slippageTolerance = parseFloat(DOM.slippageInput.value) || 0.5;
        saveSettingsToStorage();
        addNotification('Slippage Tolerance', `Set to ${state.settings.slippageTolerance}%`, 'info');
    }

    function toggleSounds() {
        if (!DOM.soundToggle) return;
        state.settings.enableSounds = DOM.soundToggle.checked;
        saveSettingsToStorage();
        addNotification('Sound Effects', state.settings.enableSounds ? 'Enabled' : 'Disabled', 'info');
    }

    function updateRefreshInterval() {
        if (!DOM.refreshIntervalInput) return;
        state.settings.autoRefreshInterval = parseInt(DOM.refreshIntervalInput.value) || 3000;
        saveSettingsToStorage();
        if (marketInterval) clearInterval(marketInterval);
        marketInterval = setInterval(simulateMarketData, state.settings.autoRefreshInterval);
        addNotification('Refresh Rate', `Auto-refresh set to ${state.settings.autoRefreshInterval}ms`, 'info');
    }

    function addNotification(title, message, type = 'info') {
        const notification = {
            id: Date.now(),
            title,
            message,
            type,
            timestamp: new Date()
        };
        state.notifications.push(notification);
        if (state.notifications.length > 20) state.notifications.shift();
        renderNotifications();
        setTimeout(() => removeNotification(notification.id), 5000);
    }

    function removeNotification(id) {
        state.notifications = state.notifications.filter(n => n.id !== id);
        renderNotifications();
    }

    function renderNotifications() {
        if (!DOM.notificationsContainer) return;
        DOM.notificationsContainer.innerHTML = '';
        state.notifications.slice().reverse().forEach(note => {
            const item = document.createElement('div');
            item.className = `notification ${note.type}`;
            item.innerHTML = `
                <div class="notification-title">${note.title}</div>
                <div class="notification-message">${note.message}</div>
                <div class="notification-time">${formatTime(note.timestamp)}</div>
            `;
            DOM.notificationsContainer.appendChild(item);
        });
    }

    function playSound(type) {
        if (!state.settings.enableSounds) return;
        if (!audioCtx) {
            audioCtx = new (window.AudioContext || window.webkitAudioContext)();
        }
        const oscillator = audioCtx.createOscillator();
        const gainNode = audioCtx.createGain();
        oscillator.connect(gainNode);
        gainNode.connect(audioCtx.destination);
        oscillator.type = 'sine';
        switch (type) {
            case 'connect':
                oscillator.frequency.setValueAtTime(440, audioCtx.currentTime);
                break;
            case 'disconnect':
                oscillator.frequency.setValueAtTime(220, audioCtx.currentTime);
                break;
            default:
                oscillator.frequency.setValueAtTime(330, audioCtx.currentTime);
        }
        gainNode.gain.setValueAtTime(0.1, audioCtx.currentTime);
        gainNode.gain.exponentialRampToValueAtTime(0.001, audioCtx.currentTime + 0.5);
        oscillator.start(audioCtx.currentTime);
        oscillator.stop(audioCtx.currentTime + 0.5);
    }

    function setupWeb3Listeners() {
        window.addEventListener('message', (event) => {
            if (event.data?.type === 'WEB3_EVENT') {
                handleWeb3Event(event.data.payload);
            }
        });
    }

    function handleWeb3Event(payload) {
        switch (payload.event) {
            case 'TRANSACTION_SUBMITTED':
                addNotification('Transaction Submitted', payload.txHash, 'info');
                break;
            case 'TRANSACTION_CONFIRMED':
                addNotification('Transaction Confirmed', payload.txHash, 'success');
                simulateNewTransaction(payload);
                break;
            case 'PRICE_UPDATE':
                state.market.price = payload.price;
                updateChart();
                updateUI();
                break;
            default:
                console.log('Unhandled Web3 event:', payload);
        }
    }

    function simulateNewTransaction(payload) {
        const tx = {
            id: Date.now(),
            hash: payload.txHash || '0x' + Math.random().toString(16).substring(2, 66),
            type: payload.type || 'SWAP',
            amount: payload.amount || '1.25',
            token: payload.token || 'ETH',
            status: 'confirmed',
            timestamp: new Date()
        };
        state.transactions.push(tx);
        if (state.transactions.length > 50) state.transactions.shift();
        renderTransactions();
    }

    function formatPrice(price) {
        return new Intl.NumberFormat(state.settings.currency === 'USD' ? 'en-US' : 'en-US', {
            style: 'currency',
            currency: state.settings.currency,
            minimumFractionDigits: 2,
            maximumFractionDigits: 2
        }).format(price);
    }

    function formatTime(date) {
        return date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
    }

    function formatTimeAgo(date) {
        const seconds = Math.floor((new Date() - date) / 1000);
        if (seconds < 60) return `${seconds}s ago`;
        const minutes = Math.floor(seconds / 60);
        if (minutes < 60) return `${minutes}m ago`;
        const hours = Math.floor(minutes / 60);
        return `${hours}h ago`;
    }

    // Start the application
    document.addEventListener('DOMContentLoaded', init);
})();