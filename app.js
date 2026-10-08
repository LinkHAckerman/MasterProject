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
            portfolioTable: document.getElementById('portfolio-table-body'),
            themeToggle: document.getElementById('theme-toggle'),
            settingsModal: document.getElementById('settings-modal'),
            settingsForm: document.getElementById('settings-form'),
            modalClose: document.querySelectorAll('.modal-close')
        };
    }

    function setupEventListeners() {
        DOM.connectBtn.addEventListener('click', connectWallet);
        DOM.pairSelect.addEventListener('change', updateMarketPair);
        DOM.swapBtn.addEventListener('click', executeSwap);
        DOM.swapFromAmount.addEventListener('input', calculateSwap);
        DOM.swapToAmount.addEventListener('input', calculateSwap);
        DOM.themeToggle.addEventListener('click', toggleTheme);
        DOM.settingsForm.addEventListener('submit', saveSettings);
        
        DOM.modalClose.forEach(btn => {
            btn.addEventListener('click', closeModal);
        });
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
                    tension: 0.3,
                    pointRadius: 0,
                    borderWidth: 2
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                scales: {
                    x: {
                        display: false
                    },
                    y: {
                        display: false
                    }
                },
                plugins: {
                    legend: {
                        display: false
                    },
                    tooltip: {
                        enabled: true,
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

    function connectWebSocket() {
        socket = new WebSocket('wss://api.magnumopus.io/ws');
        
        socket.onmessage = function(event) {
            const data = JSON.parse(event.data);
            handleWebSocketMessage(data);
        };

        socket.onclose = function() {
            setTimeout(connectWebSocket, 5000);
        };
    }

    function handleWebSocketMessage(data) {
        switch(data.type) {
            case 'price_update':
                updateMarketData(data.payload);
                break;
            case 'orderbook_update':
                updateOrderBook(data.payload);
                break;
            case 'transaction_update':
                addTransaction(data.payload);
                break;
            case 'wallet_update':
                updateWallet(data.payload);
                break;
        }
    }

    function updateMarketData(data) {
        state.market.price = data.price;
        state.market.change24h = data.change24h;
        state.market.volume24h = data.volume24h;
        state.market.high24h = data.high24h;
        state.market.low24h = data.low24h;
        
        // Update chart data
        if (state.market.chartData.labels.length > 20) {
            state.market.chartData.labels.shift();
            state.market.chartData.prices.shift();
        }
        
        state.market.chartData.labels.push(new Date().toLocaleTimeString());
        state.market.chartData.prices.push(data.price);
        
        priceChart.update();
        updateUI();
    }

    function updateOrderBook(data) {
        state.orderBook.bids = data.bids;
        state.orderBook.asks = data.asks;
        updateUI();
    }

    function addTransaction(tx) {
        state.transactions.unshift(tx);
        if (state.transactions.length > 10) {
            state.transactions.pop();
        }
        updateUI();
    }

    function updateWallet(walletData) {
        state.wallet = {...state.wallet, ...walletData};
        updateUI();
    }

    function updateUI() {
        // Update wallet information
        if (state.wallet.connected) {
            DOM.connectBtn.textContent = 'Disconnect Wallet';
            DOM.walletAddress.textContent = `${state.wallet.address.substring(0, 6)}...${state.wallet.address.substring(38)}`;
        } else {
            DOM.connectBtn.textContent = 'Connect Wallet';
            DOM.walletAddress.textContent = 'Not Connected';
        }

        // Update gas price
        DOM.gasPrice.textContent = `${state.gas.current} Gwei`;

        // Update market data
        DOM.currentPrice.textContent = `$${state.market.price.toFixed(2)}`;
        DOM.priceChange.textContent = `${state.market.change24h > 0 ? '+' : ''}${state.market.change24h.toFixed(2)}%`;
        DOM.priceChange.style.color = state.market.change24h > 0 ? '#10b981' : '#f43f5e';

        // Update order book
        updateOrderBookUI();

        // Update transaction history
        updateTransactionHistoryUI();

        // Update portfolio
        updatePortfolioUI();

        // Update notifications
        updateNotificationsUI();
    }

    function updateOrderBookUI() {
        DOM.orderBookBids.innerHTML = '';
        DOM.orderBookAsks.innerHTML = '';

        // Sort bids in descending order
        const sortedBids = [...state.orderBook.bids].sort((a, b) => b.price - a.price);

        // Sort asks in ascending order
        const sortedAsks = [...state.orderBook.asks].sort((a, b) => a.price - b.price);

        // Display top 10 bids
        sortedBids.slice(0, 10).forEach(bid => {
            const bidElement = document.createElement('div');
            bidElement.className = 'orderbook-item';
            bidElement.innerHTML = `
                <span class="orderbook-price" style="color: #10b981">${bid.price.toFixed(2)}</span>
                <span class="orderbook-amount">${bid.amount.toFixed(4)}</span>
                <span class="orderbook-total">${(bid.price * bid.amount).toFixed(2)}</span>
            `;
            DOM.orderBookBids.appendChild(bidElement);
        });

        // Display top 10 asks
        sortedAsks.slice(0, 10).forEach(ask => {
            const askElement = document.createElement('div');
            askElement.className = 'orderbook-item';
            askElement.innerHTML = `
                <span class="orderbook-price" style="color: #f43f5e">${ask.price.toFixed(2)}</span>
                <span class="orderbook-amount">${ask.amount.toFixed(4)}</span>
                <span class="orderbook-total">${(ask.price * ask.amount).toFixed(2)}</span>
            `;
            DOM.orderBookAsks.appendChild(askElement);
        });
    }

    function updateTransactionHistoryUI() {
        DOM.txList.innerHTML = '';

        state.transactions.forEach(tx => {
            const txElement = document.createElement('div');
            txElement.className = 'transaction-item';
            txElement.innerHTML = `
                <div class="transaction-info">
                    <span class="transaction-type" style="color: ${tx.type === 'buy' ? '#10b981' : '#f43f5e'}">${tx.type.toUpperCase()}</span>
                    <span class="transaction-amount">${tx.amount.toFixed(4)} ${tx.symbol}</span>
                </div>
                <div class="transaction-details">
                    <span class="transaction-price">@ ${tx.price.toFixed(2)} USDT</span>
                    <span class="transaction-time">${new Date(tx.timestamp).toLocaleTimeString()}</span>
                </div>
            `;
            DOM.txList.appendChild(txElement);
        });
    }

    function updatePortfolioUI() {
        DOM.portfolioTable.innerHTML = '';

        state.portfolio.forEach(asset => {
            const row = document.createElement('tr');
            row.innerHTML = `
                <td>
                    <div class="asset-info">
                        <span class="asset-symbol">${asset.symbol}</span>
                        <span class="asset-name">${asset.name}</span>
                    </div>
                </td>
                <td>${asset.balance.toFixed(4)}</td>
                <td>$${asset.price.toFixed(2)}</td>
                <td>$${asset.value.toFixed(2)}</td>
                <td>
                    <div class="allocation-bar">
                        <div class="allocation-fill" style="width: ${asset.allocation}%; background-color: ${getAssetColor(asset.symbol)};"></div>
                    </div>
                </td>
                <td>${asset.allocation.toFixed(1)}%</td>
            `;
            DOM.portfolioTable.appendChild(row);
        });
    }

    function getAssetColor(symbol) {
        const colors = {
            'ETH': '#38bdf8',
            'BTC': '#f59e0b',
            'SOL': '#a855f7'
        };
        return colors[symbol] || '#94a3b8';
    }

    function updateNotificationsUI() {
        DOM.notificationContainer.innerHTML = '';

        state.notifications.forEach(notification => {
            const notificationElement = document.createElement('div');
            notificationElement.className = `notification ${notification.type}`;
            notificationElement.innerHTML = `
                <div class="notification-content">
                    <span class="notification-message">${notification.message}</span>
                    <span class="notification-time">${new Date(notification.timestamp).toLocaleTimeString()}</span>
                </div>
                <button class="notification-close">&times;</button>
            `;
            DOM.notificationContainer.appendChild(notificationElement);

            // Auto-dismiss after 5 seconds
            setTimeout(() => {
                notificationElement.remove();
            }, 5000);
        });

        // Clear notifications after displaying
        state.notifications = [];
    }

    function connectWallet() {
        if (state.wallet.connected) {
            state.wallet.connected = false;
            state.wallet.address = null;
            addNotification('Wallet disconnected', 'info');
        } else {
            // Simulate wallet connection
            setTimeout(() => {
                state.wallet.connected = true;
                state.wallet.address = '0x742d35Cc6634C0532925a3b844Bc454e4438f44e';
                addNotification('Wallet connected successfully', 'success');
            }, 1000);
        }
        updateUI();
    }

    function updateMarketPair() {
        state.market.selectedPair = DOM.pairSelect.value;
        // In a real implementation, we would fetch new data for the selected pair
        addNotification(`Market pair changed to ${state.market.selectedPair}`, 'info');
    }

    function calculateSwap() {
        const fromAmount = parseFloat(DOM.swapFromAmount.value) || 0;
        const toAmount = fromAmount * (state.market.price * 0.997); // 0.3% slippage
        DOM.swapToAmount.value = toAmount.toFixed(4);
    }

    function executeSwap() {
        const fromAmount = parseFloat(DOM.swapFromAmount.value);
        const toAmount = parseFloat(DOM.swapToAmount.value);

        if (fromAmount <= 0 || toAmount <= 0) {
            addNotification('Invalid swap amount', 'error');
            return;
        }

        if (state.wallet.balanceEth < fromAmount) {
            addNotification('Insufficient ETH balance', 'error');
            return;
        }

        // Simulate swap execution
        setTimeout(() => {
            state.wallet.balanceEth -= fromAmount;
            state.wallet.balanceUsdt += toAmount;
            
            // Update portfolio
            const ethAsset = state.portfolio.find(asset => asset.symbol === 'ETH');
            if (ethAsset) {
                ethAsset.balance -= fromAmount;
                ethAsset.value = ethAsset.balance * ethAsset.price;
            }

            const usdtAsset = state.portfolio.find(asset => asset.symbol === 'USDT');
            if (usdtAsset) {
                usdtAsset.balance += toAmount;
                usdtAsset.value = usdtAsset.balance * usdtAsset.price;
            }

            // Recalculate allocations
            const totalValue = state.portfolio.reduce((sum, asset) => sum + asset.value, 0);
            state.portfolio.forEach(asset => {
                asset.allocation = (asset.value / totalValue) * 100;
            });

            // Add transaction
            addTransaction({
                type: 'sell',
                symbol: 'ETH',
                amount: fromAmount,
                price: state.market.price,
                timestamp: Date.now()
            });

            addNotification('Swap executed successfully', 'success');
            updateUI();
        }, 1500);
    }

    function toggleTheme() {
        const newTheme = state.settings.theme === 'dark' ? 'light' : 'dark';
        state.settings.theme = newTheme;
        document.documentElement.setAttribute('data-theme', newTheme);
        addNotification(`Theme changed to ${newTheme} mode`, 'info');
    }

    function saveSettings(e) {
        e.preventDefault();
        const formData = new FormData(DOM.settingsForm);
        state.settings.currency = formData.get('currency');
        state.settings.language = formData.get('language');
        addNotification('Settings saved successfully', 'success');
        closeModal();
    }

    function addNotification(message, type) {
        state.notifications.push({
            message,
            type,
            timestamp: Date.now()
        });
        updateNotificationsUI();
    }

    function closeModal() {
        DOM.settingsModal.style.display = 'none';
    }

    // Initialize the application when the DOM is fully loaded
    document.addEventListener('DOMContentLoaded', init);

    // Expose functions to global scope for debugging
    window.MagnumOpus = {
        state,
        updateUI,
        addNotification
    };

})();