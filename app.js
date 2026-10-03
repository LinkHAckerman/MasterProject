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
            currencySelect: document.getElementById('currency-select'),
            languageSelect: document.getElementById('language-select')
        };
    }

    function setupEventListeners() {
        DOM.connectBtn.addEventListener('click', connectWallet);
        DOM.pairSelect.addEventListener('change', updateMarketPair);
        DOM.swapFromAmount.addEventListener('input', calculateSwap);
        DOM.swapToAmount.addEventListener('input', calculateSwap);
        DOM.swapBtn.addEventListener('click', executeSwap);
        DOM.themeToggle.addEventListener('click', toggleTheme);
        DOM.currencySelect.addEventListener('change', updateCurrency);
        DOM.languageSelect.addEventListener('change', updateLanguage);
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
                    fill: true
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
                            color: 'rgba(56, 189, 248, 0.1)'
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

    function connectWebSocket() {
        socket = new WebSocket('wss://api.magnumopus.com/ws');

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

    function updateWallet(data) {
        state.wallet.balanceEth = data.balanceEth;
        state.wallet.balanceUsdt = data.balanceUsdt;
        state.wallet.tokens = data.tokens;
        updateUI();
    }

    function updateUI() {
        // Update wallet information
        if (state.wallet.connected) {
            DOM.walletAddress.textContent = `${state.wallet.address.substring(0, 6)}...${state.wallet.address.substring(38)}`;
            DOM.connectBtn.textContent = 'Disconnect';
        } else {
            DOM.walletAddress.textContent = 'Not connected';
            DOM.connectBtn.textContent = 'Connect Wallet';
        }

        // Update gas price
        DOM.gasPrice.textContent = `${state.gas.current} Gwei`;

        // Update market data
        DOM.currentPrice.textContent = `$${state.market.price.toFixed(2)}`;
        DOM.priceChange.textContent = `${state.market.change24h.toFixed(2)}%`;
        DOM.priceChange.style.color = state.market.change24h >= 0 ? '#10b981' : '#f43f5e';

        // Update order book
        updateOrderBookUI();

        // Update transaction history
        updateTransactionHistoryUI();

        // Update portfolio
        updatePortfolioUI();

        // Update chart
        priceChart.update();
    }

    function updateOrderBookUI() {
        DOM.orderBookBids.innerHTML = '';
        DOM.orderBookAsks.innerHTML = '';

        // Sort bids in descending order
        const sortedBids = [...state.orderBook.bids].sort((a, b) => b.price - a.price);
        sortedBids.forEach(bid => {
            const bidElement = document.createElement('div');
            bidElement.className = 'orderbook-entry';
            bidElement.innerHTML = `
                <span class="orderbook-price" style="color: #10b981">$${bid.price.toFixed(2)}</span>
                <span class="orderbook-amount">${bid.amount.toFixed(4)}</span>
                <span class="orderbook-total">$${(bid.price * bid.amount).toFixed(2)}</span>
            `;
            DOM.orderBookBids.appendChild(bidElement);
        });

        // Sort asks in ascending order
        const sortedAsks = [...state.orderBook.asks].sort((a, b) => a.price - b.price);
        sortedAsks.forEach(ask => {
            const askElement = document.createElement('div');
            askElement.className = 'orderbook-entry';
            askElement.innerHTML = `
                <span class="orderbook-price" style="color: #f43f5e">$${ask.price.toFixed(2)}</span>
                <span class="orderbook-amount">${ask.amount.toFixed(4)}</span>
                <span class="orderbook-total">$${(ask.price * ask.amount).toFixed(2)}</span>
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
                <div class="transaction-icon">
                    <i class="fas ${tx.type === 'buy' ? 'fa-arrow-down' : 'fa-arrow-up'} ${tx.type === 'buy' ? 'text-emerald-500' : 'text-rose-500'}"></i>
                </div>
                <div class="transaction-details">
                    <div class="transaction-type">${tx.type === 'buy' ? 'Buy' : 'Sell'} ${tx.symbol}</div>
                    <div class="transaction-time">${new Date(tx.timestamp).toLocaleTimeString()}</div>
                </div>
                <div class="transaction-amount">
                    <div class="amount">${tx.amount.toFixed(4)} ${tx.symbol}</div>
                    <div class="value">$${(tx.amount * tx.price).toFixed(2)}</div>
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
                <td class="portfolio-asset">
                    <div class="asset-icon">${asset.symbol}</div>
                    <div class="asset-details">
                        <div class="asset-name">${asset.name}</div>
                        <div class="asset-symbol">${asset.symbol}</div>
                    </div>
                </td>
                <td class="portfolio-balance">${asset.balance.toFixed(4)}</td>
                <td class="portfolio-price">$${asset.price.toFixed(2)}</td>
                <td class="portfolio-value">$${asset.value.toFixed(2)}</td>
                <td class="portfolio-allocation">${asset.allocation.toFixed(1)}%</td>
            `;
            DOM.portfolioTable.appendChild(row);
        });
    }

    function calculateSwap() {
        const fromAmount = parseFloat(DOM.swapFromAmount.value) || 0;
        const toAmount = fromAmount * (state.market.price * (1 - (state.gas.current / 1000)));
        DOM.swapToAmount.value = toAmount.toFixed(4);
    }

    function executeSwap() {
        const fromAmount = parseFloat(DOM.swapFromAmount.value);
        const toAmount = parseFloat(DOM.swapToAmount.value);

        if (fromAmount <= 0 || toAmount <= 0) {
            showNotification('Please enter valid amounts', 'error');
            return;
        }

        if (fromAmount > state.wallet.balanceEth) {
            showNotification('Insufficient ETH balance', 'error');
            return;
        }

        // Simulate swap transaction
        const tx = {
            type: 'sell',
            symbol: 'ETH',
            amount: fromAmount,
            price: state.market.price,
            timestamp: Date.now()
        };

        addTransaction(tx);
        state.wallet.balanceEth -= fromAmount;
        state.wallet.balanceUsdt += toAmount;
        updateUI();
        showNotification('Swap executed successfully', 'success');
    }

    function connectWallet() {
        if (state.wallet.connected) {
            state.wallet.connected = false;
            state.wallet.address = null;
            updateUI();
            showNotification('Wallet disconnected', 'info');
        } else {
            // Simulate wallet connection
            state.wallet.connected = true;
            state.wallet.address = '0x1234567890123456789012345678901234567890';
            updateUI();
            showNotification('Wallet connected successfully', 'success');
        }
    }

    function updateMarketPair() {
        state.market.selectedPair = DOM.pairSelect.value;
        // In a real implementation, we would fetch new market data for the selected pair
        showNotification(`Market pair changed to ${state.market.selectedPair}`, 'info');
    }

    function toggleTheme() {
        state.settings.theme = state.settings.theme === 'dark' ? 'light' : 'dark';
        document.documentElement.setAttribute('data-theme', state.settings.theme);
        showNotification(`Theme changed to ${state.settings.theme} mode`, 'info');
    }

    function updateCurrency() {
        state.settings.currency = DOM.currencySelect.value;
        showNotification(`Currency changed to ${state.settings.currency}`, 'info');
    }

    function updateLanguage() {
        state.settings.language = DOM.languageSelect.value;
        showNotification(`Language changed to ${state.settings.language}`, 'info');
    }

    function showNotification(message, type) {
        const notification = document.createElement('div');
        notification.className = `notification ${type}`;
        notification.textContent = message;

        DOM.notificationContainer.appendChild(notification);

        setTimeout(() => {
            notification.classList.add('show');
        }, 10);

        setTimeout(() => {
            notification.classList.remove('show');
            setTimeout(() => {
                DOM.notificationContainer.removeChild(notification);
            }, 300);
        }, 3000);
    }

    function setupWeb3Listeners() {
        // In a real implementation, we would set up listeners for Web3 events
        // such as account changes, network changes, etc.
    }

    // Initialize the application when the DOM is fully loaded
    document.addEventListener('DOMContentLoaded', init);

})();