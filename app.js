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
            chainId: '0x1',
            networkName: 'Ethereum Mainnet',
            tokens: []
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
            asks: []
        },
        transactions: [],
        portfolio: [
            { symbol: 'ETH', name: 'Ethereum', balance: 14.852, price: 3450.75, value: 51249.54, allocation: 54.2 },
            { symbol: 'BTC', name: 'Bitcoin', balance: 0.65, price: 64200.00, value: 41730.00, allocation: 44.1 },
            { symbol: 'SOL', name: 'Solana', balance: 12.5, price: 145.20, value: 1815.00, allocation: 1.7 }
        ],
        notifications: [],
        settings: {
            theme: 'dark',
            currency: 'USD',
            language: 'en'
        }
    };

    // DOM Elements Cache
    let DOM = {};

    // WebSocket Connection for Real-time Data
    let socket;

    // Chart Instance
    let priceChart;

    // Initialize the application
    function init() {
        initDOM();
        setupEventListeners();
        initializeChart();
        connectWebSocket();
        updateUI();
        setupWeb3Listeners();
    }

    function initDOM() {
        DOM = {
            connectBtn: document.getElementById('connect-wallet-btn'),
            walletAddress: document.getElementById('wallet-address-display'),
            gasPrice: document.getElementById('gas-price-display'),
            pairSelect: document.getElementById('pair-select'),
            currentPrice: document.getElementById('current-price-display'),
            priceChange: document.getElementById('price-change-display'),
            orderBookAsks: document.getElementById('orderbook-asks'),
            orderBookBids: document.getElementById('orderbook-bids'),
            txList: document.getElementById('transaction-history-list'),
            swapFromAmount: document.getElementById('swap-from-amount'),
            swapToAmount: document.getElementById('swap-to-amount'),
            swapBtn: document.getElementById('execute-swap-btn'),
            chartCanvas: document.getElementById('price-chart-canvas'),
            notificationContainer: document.getElementById('notification-container'),
            themeToggle: document.getElementById('theme-toggle'),
            currencySelect: document.getElementById('currency-select'),
            languageSelect: document.getElementById('language-select'),
            portfolioList: document.getElementById('portfolio-list'),
            tokenList: document.getElementById('token-list'),
            networkSelect: document.getElementById('network-select')
        };
    }

    function setupEventListeners() {
        DOM.connectBtn.addEventListener('click', connectWallet);
        DOM.swapBtn.addEventListener('click', executeSwap);
        DOM.swapFromAmount.addEventListener('input', calculateSwap);
        DOM.swapToAmount.addEventListener('input', calculateSwap);
        DOM.pairSelect.addEventListener('change', changePair);
        DOM.themeToggle.addEventListener('click', toggleTheme);
        DOM.currencySelect.addEventListener('change', changeCurrency);
        DOM.languageSelect.addEventListener('change', changeLanguage);
        DOM.networkSelect.addEventListener('change', changeNetwork);
    }

    function setupWeb3Listeners() {
        if (window.ethereum) {
            window.ethereum.on('accountsChanged', handleAccountsChanged);
            window.ethereum.on('chainChanged', handleChainChanged);
            window.ethereum.on('message', handleMessage);
        }
    }

    function connectWallet() {
        if (window.ethereum) {
            window.ethereum.request({ method: 'eth_requestAccounts' })
                .then(accounts => {
                    state.wallet.connected = true;
                    state.wallet.address = accounts[0];
                    updateUI();
                    fetchWalletData();
                    addNotification('Wallet connected successfully', 'success');
                })
                .catch(error => {
                    console.error('Error connecting wallet:', error);
                    addNotification('Failed to connect wallet', 'error');
                });
        } else {
            addNotification('Please install MetaMask!', 'error');
        }
    }

    function fetchWalletData() {
        // Simulate fetching wallet data
        setTimeout(() => {
            state.wallet.balanceEth = 14.852;
            state.wallet.balanceUsdt = 42500.00;
            state.wallet.tokens = [
                { symbol: 'ETH', balance: 14.852, price: 3450.75 },
                { symbol: 'USDT', balance: 42500.00, price: 1.00 }
            ];
            updateUI();
        }, 1000);
    }

    function executeSwap() {
        const fromAmount = parseFloat(DOM.swapFromAmount.value);
        const toAmount = parseFloat(DOM.swapToAmount.value);

        if (isNaN(fromAmount) || fromAmount <= 0) {
            addNotification('Please enter a valid amount', 'error');
            return;
        }

        // Simulate swap execution
        setTimeout(() => {
            const txHash = '0x' + Math.random().toString(16).substr(2, 64);
            const tx = {
                hash: txHash,
                from: state.wallet.address,
                to: '0x' + Math.random().toString(16).substr(2, 40),
                amount: fromAmount,
                timestamp: new Date().toISOString(),
                status: 'pending'
            };

            state.transactions.unshift(tx);
            updateUI();
            addNotification('Swap executed successfully', 'success');

            // Simulate transaction confirmation
            setTimeout(() => {
                tx.status = 'confirmed';
                updateUI();
            }, 5000);
        }, 2000);
    }

    function calculateSwap() {
        const fromAmount = parseFloat(DOM.swapFromAmount.value);
        if (!isNaN(fromAmount) && fromAmount > 0) {
            const toAmount = fromAmount * 0.997; // Simulate 0.3% fee
            DOM.swapToAmount.value = toAmount.toFixed(6);
        }
    }

    function changePair() {
        state.market.selectedPair = DOM.pairSelect.value;
        updateChartData();
        updateOrderBook();
    }

    function toggleTheme() {
        state.settings.theme = state.settings.theme === 'dark' ? 'light' : 'dark';
        document.documentElement.setAttribute('data-theme', state.settings.theme);
        updateUI();
    }

    function changeCurrency() {
        state.settings.currency = DOM.currencySelect.value;
        updateUI();
    }

    function changeLanguage() {
        state.settings.language = DOM.languageSelect.value;
        updateUI();
    }

    function changeNetwork() {
        state.wallet.chainId = DOM.networkSelect.value;
        state.wallet.networkName = DOM.networkSelect.options[DOM.networkSelect.selectedIndex].text;
        updateUI();
        addNotification(`Network changed to ${state.wallet.networkName}`, 'info');
    }

    function updateUI() {
        updateWalletInfo();
        updateGasPrice();
        updateMarketInfo();
        updateOrderBook();
        updateTransactionHistory();
        updatePortfolio();
        updateTokenList();
        updateSettings();
    }

    function updateWalletInfo() {
        if (state.wallet.connected) {
            DOM.walletAddress.textContent = `${state.wallet.address.slice(0, 6)}...${state.wallet.address.slice(-4)}`;
            DOM.connectBtn.textContent = 'Disconnect Wallet';
        } else {
            DOM.walletAddress.textContent = 'Not connected';
            DOM.connectBtn.textContent = 'Connect Wallet';
        }
    }

    function updateGasPrice() {
        DOM.gasPrice.textContent = `${state.gas.current} Gwei`;
    }

    function updateMarketInfo() {
        DOM.currentPrice.textContent = `$${state.market.price.toFixed(2)}`;
        DOM.priceChange.textContent = `${state.market.change24h.toFixed(2)}%`;
        DOM.priceChange.className = state.market.change24h >= 0 ? 'price-up' : 'price-down';
    }

    function updateOrderBook() {
        // Simulate order book data
        state.orderBook.bids = [
            { price: state.market.price, amount: 0.5 },
            { price: state.market.price * 0.999, amount: 0.3 },
            { price: state.market.price * 0.998, amount: 0.2 }
        ];
        state.orderBook.asks = [
            { price: state.market.price * 1.001, amount: 0.4 },
            { price: state.market.price * 1.002, amount: 0.3 },
            { price: state.market.price * 1.003, amount: 0.2 }
        ];

        DOM.orderBookBids.innerHTML = state.orderBook.bids.map(bid =>
            `<div class="orderbook-item">
                <span class="price">$${bid.price.toFixed(2)}</span>
                <span class="amount">${bid.amount.toFixed(3)}</span>
            </div>`
        ).join('');

        DOM.orderBookAsks.innerHTML = state.orderBook.asks.map(ask =>
            `<div class="orderbook-item">
                <span class="price">$${ask.price.toFixed(2)}</span>
                <span class="amount">${ask.amount.toFixed(3)}</span>
            </div>`
        ).join('');
    }

    function updateTransactionHistory() {
        DOM.txList.innerHTML = state.transactions.map(tx =>
            `<div class="tx-item">
                <div class="tx-hash">${tx.hash.slice(0, 6)}...${tx.hash.slice(-4)}</div>
                <div class="tx-amount">${tx.amount.toFixed(6)} ETH</div>
                <div class="tx-status ${tx.status}">${tx.status}</div>
            </div>`
        ).join('');
    }

    function updatePortfolio() {
        DOM.portfolioList.innerHTML = state.portfolio.map(asset =>
            `<div class="portfolio-item">
                <div class="asset-symbol">${asset.symbol}</div>
                <div class="asset-name">${asset.name}</div>
                <div class="asset-balance">${asset.balance.toFixed(6)}</div>
                <div class="asset-price">$${asset.price.toFixed(2)}</div>
                <div class="asset-value">$${asset.value.toFixed(2)}</div>
                <div class="asset-allocation">${asset.allocation.toFixed(1)}%</div>
            </div>`
        ).join('');
    }

    function updateTokenList() {
        DOM.tokenList.innerHTML = state.wallet.tokens.map(token =>
            `<div class="token-item">
                <div class="token-symbol">${token.symbol}</div>
                <div class="token-balance">${token.balance.toFixed(6)}</div>
                <div class="token-price">$${token.price.toFixed(2)}</div>
            </div>`
        ).join('');
    }

    function updateSettings() {
        DOM.themeToggle.textContent = state.settings.theme === 'dark' ? 'Light Mode' : 'Dark Mode';
        DOM.currencySelect.value = state.settings.currency;
        DOM.languageSelect.value = state.settings.language;
        DOM.networkSelect.value = state.wallet.chainId;
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
                    borderColor: '#38bdf8',
                    backgroundColor: 'rgba(56, 189, 248, 0.1)',
                    tension: 0.1
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                scales: {
                    y: {
                        beginAtZero: false
                    }
                }
            }
        });
    }

    function updateChartData() {
        // Simulate fetching chart data
        setTimeout(() => {
            const now = new Date();
            const labels = [];
            const prices = [];

            for (let i = 0; i < 24; i++) {
                const time = new Date(now - (24 - i) * 60 * 60 * 1000);
                labels.push(time.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }));
                prices.push(state.market.price * (1 + (Math.random() - 0.5) * 0.02));
            }

            state.market.chartData.labels = labels;
            state.market.chartData.prices = prices;
            priceChart.data.labels = labels;
            priceChart.data.datasets[0].data = prices;
            priceChart.update();
        }, 1000);
    }

    function connectWebSocket() {
        // Simulate WebSocket connection
        socket = {
            onmessage: function(event) {
                const data = JSON.parse(event.data);
                handleWebSocketMessage(data);
            }
        };

        // Simulate incoming data
        setInterval(() => {
            const message = {
                type: 'market_update',
                data: {
                    price: state.market.price * (1 + (Math.random() - 0.5) * 0.01),
                    change24h: state.market.change24h + (Math.random() - 0.5) * 0.1,
                    volume24h: state.market.volume24h + Math.random() * 1000000,
                    high24h: Math.max(state.market.high24h, state.market.price * 1.01),
                    low24h: Math.min(state.market.low24h, state.market.price * 0.99)
                }
            };
            handleWebSocketMessage(message);
        }, 5000);
    }

    function handleWebSocketMessage(message) {
        switch (message.type) {
            case 'market_update':
                state.market.price = message.data.price;
                state.market.change24h = message.data.change24h;
                state.market.volume24h = message.data.volume24h;
                state.market.high24h = message.data.high24h;
                state.market.low24h = message.data.low24h;
                updateUI();
                break;
            case 'orderbook_update':
                state.orderBook.bids = message.data.bids;
                state.orderBook.asks = message.data.asks;
                updateUI();
                break;
            case 'transaction_update':
                const txIndex = state.transactions.findIndex(tx => tx.hash === message.data.hash);
                if (txIndex !== -1) {
                    state.transactions[txIndex].status = message.data.status;
                    updateUI();
                }
                break;
            default:
                console.log('Unknown message type:', message.type);
        }
    }

    function addNotification(message, type = 'info') {
        const notification = {
            id: Date.now(),
            message,
            type
        };

        state.notifications.unshift(notification);
        if (state.notifications.length > 5) {
            state.notifications.pop();
        }

        updateNotificationUI();

        setTimeout(() => {
            state.notifications = state.notifications.filter(n => n.id !== notification.id);
            updateNotificationUI();
        }, 5000);
    }

    function updateNotificationUI() {
        DOM.notificationContainer.innerHTML = state.notifications.map(notification =>
            `<div class="notification ${notification.type}">
                <span>${notification.message}</span>
                <button class="close-btn" data-id="${notification.id}">&times;</button>
            </div>`
        ).join('');

        document.querySelectorAll('.close-btn').forEach(btn => {
            btn.addEventListener('click', (e) => {
                const id = parseInt(e.target.getAttribute('data-id'));
                state.notifications = state.notifications.filter(n => n.id !== id);
                updateNotificationUI();
            });
        });
    }

    function handleAccountsChanged(accounts) {
        if (accounts.length === 0) {
            state.wallet.connected = false;
            state.wallet.address = null;
            updateUI();
            addNotification('Wallet disconnected', 'info');
        } else if (accounts[0] !== state.wallet.address) {
            state.wallet.address = accounts[0];
            updateUI();
            fetchWalletData();
            addNotification('Wallet account changed', 'info');
        }
    }

    function handleChainChanged(chainId) {
        state.wallet.chainId = chainId;
        state.wallet.networkName = getNetworkName(chainId);
        updateUI();
        addNotification(`Network changed to ${state.wallet.networkName}`, 'info');
    }

    function handleMessage(message) {
        console.log('Received message:', message);
    }

    function getNetworkName(chainId) {
        const networkNames = {
            '0x1': 'Ethereum Mainnet',
            '0x3': 'Ropsten Testnet',
            '0x4': 'Rinkeby Testnet',
            '0x5': 'Goerli Testnet',
            '0x2a': 'Kovan Testnet',
            '0x89': 'Polygon Mainnet',
            '0x13881': 'Mumbai Testnet'
        };
        return networkNames[chainId] || `Unknown Network (${chainId})`;
    }

    // Initialize the application when DOM is loaded
    document.addEventListener('DOMContentLoaded', init);

})();