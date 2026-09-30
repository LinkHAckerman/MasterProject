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
            networkName: 'Ethereum Mainnet'
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
            low24h: 3310.50
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
        chartData: {
            labels: [],
            prices: []
        }
    };

    // DOM Elements Cache
    let DOM = {};

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
            themeToggle: document.getElementById('theme-toggle')
        };
    }

    // Theme Management System
    class ThemeManager {
        static init() {
            const savedTheme = localStorage.getItem('theme') || 'dark';
            ThemeManager.applyTheme(savedTheme);
            
            DOM.themeToggle.addEventListener('click', () => {
                const newTheme = document.documentElement.classList.contains('dark') ? 'light' : 'dark';
                ThemeManager.applyTheme(newTheme);
                localStorage.setItem('theme', newTheme);
            });
        }

        static applyTheme(theme) {
            if (theme === 'dark') {
                document.documentElement.classList.add('dark');
                DOM.themeToggle.innerHTML = '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="5"/><line x1="12" y1="1" x2="12" y2="3"/><line x1="12" y1="21" x2="12" y2="23"/><line x1="4.22" y1="4.22" x2="5.64" y2="5.64"/><line x1="18.36" y1="18.36" x2="19.78" y2="19.78"/><line x1="1" y1="12" x2="3" y2="12"/><line x1="21" y1="12" x2="23" y2="12"/><line x1="4.22" y1="19.78" x2="5.64" y2="18.36"/><line x1="18.36" y1="5.64" x2="19.78" y2="4.22"/></svg>';
            } else {
                document.documentElement.classList.remove('dark');
                DOM.themeToggle.innerHTML = '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"/></svg>';
            }
        }
    }

    // Notification System
    class NotificationSystem {
        static show(message, type = 'info', duration = 5000) {
            const notification = document.createElement('div');
            notification.className = `notification notification-${type}`;
            notification.textContent = message;

            DOM.notificationContainer.appendChild(notification);

            setTimeout(() => {
                notification.classList.add('fade-out');
                setTimeout(() => {
                    DOM.notificationContainer.removeChild(notification);
                }, 300);
            }, duration);
        }
    }

    // Wallet Connection Handler
    function connectWallet() {
        if (state.wallet.connected) {
            state.wallet.connected = false;
            state.wallet.address = null;
            DOM.connectBtn.textContent = 'Connect Wallet';
            DOM.walletAddress.textContent = 'Not connected';
            NotificationSystem.show('Wallet disconnected', 'warning');
        } else {
            // Simulate wallet connection
            setTimeout(() => {
                state.wallet.connected = true;
                state.wallet.address = '0x742d35Cc6634C0532925a3b844Bc454e4438f44e';
                DOM.connectBtn.textContent = 'Disconnect';
                DOM.walletAddress.textContent = `${state.wallet.address.slice(0, 6)}...${state.wallet.address.slice(-4)}`;
                NotificationSystem.show('Wallet connected successfully', 'success');
                updateUI();
            }, 1000);
        }
    }

    // Gas Price Updater
    function updateGasPrice() {
        const gasPrices = [state.gas.slow, state.gas.standard, state.gas.fast];
        const randomIndex = Math.floor(Math.random() * gasPrices.length);
        state.gas.current = gasPrices[randomIndex];
        DOM.gasPrice.textContent = `${state.gas.current} Gwei`;
    }

    // Market Data Simulator
    function simulateMarketData() {
        // Simulate price changes
        const change = (Math.random() - 0.5) * 10;
        state.market.price = Math.max(3000, state.market.price + change);
        state.market.change24h = (change / state.market.price) * 100;
        state.market.volume24h += Math.floor(Math.random() * 1000000);
        state.market.high24h = Math.max(state.market.high24h, state.market.price);
        state.market.low24h = Math.min(state.market.low24h, state.market.price);

        // Update chart data
        const now = new Date();
        state.chartData.labels.push(now.toLocaleTimeString());
        state.chartData.prices.push(state.market.price);

        // Keep only the last 20 data points
        if (state.chartData.labels.length > 20) {
            state.chartData.labels.shift();
            state.chartData.prices.shift();
        }

        updateUI();
    }

    // Order Book Simulator
    function simulateOrderBook() {
        // Clear existing orders
        state.orderBook.bids = [];
        state.orderBook.asks = [];

        // Generate random bids
        for (let i = 0; i < 5; i++) {
            const price = state.market.price - (i * 5) - (Math.random() * 2);
            const amount = 0.1 + (Math.random() * 0.9);
            state.orderBook.bids.push({ price: price.toFixed(2), amount: amount.toFixed(4) });
        }

        // Generate random asks
        for (let i = 0; i < 5; i++) {
            const price = state.market.price + (i * 5) + (Math.random() * 2);
            const amount = 0.1 + (Math.random() * 0.9);
            state.orderBook.asks.push({ price: price.toFixed(2), amount: amount.toFixed(4) });
        }

        updateUI();
    }

    // Transaction Simulator
    function simulateTransaction() {
        if (!state.wallet.connected) return;

        const isBuy = Math.random() > 0.5;
        const amount = (Math.random() * 0.5 + 0.1).toFixed(4);
        const price = state.market.price;
        const total = (amount * price).toFixed(2);
        const timestamp = new Date().toLocaleTimeString();

        const transaction = {
            id: `0x${Math.floor(Math.random() * 1000000000000).toString(16)}`,
            type: isBuy ? 'Buy' : 'Sell',
            amount: amount,
            price: price.toFixed(2),
            total: total,
            timestamp: timestamp,
            status: 'Completed'
        };

        state.transactions.unshift(transaction);
        if (state.transactions.length > 10) {
            state.transactions.pop();
        }

        // Update portfolio
        if (isBuy) {
            state.portfolio[0].balance = parseFloat(state.portfolio[0].balance) + parseFloat(amount);
            state.portfolio[0].value = state.portfolio[0].balance * state.portfolio[0].price;
        } else {
            state.portfolio[0].balance = parseFloat(state.portfolio[0].balance) - parseFloat(amount);
            state.portfolio[0].value = state.portfolio[0].balance * state.portfolio[0].price;
        }

        updateUI();
        NotificationSystem.show(`${transaction.type} ${transaction.amount} ETH at ${transaction.price} USDT`, 'success');
    }

    // Swap Functionality
    function executeSwap() {
        if (!state.wallet.connected) {
            NotificationSystem.show('Please connect your wallet first', 'error');
            return;
        }

        const fromAmount = parseFloat(DOM.swapFromAmount.value);
        if (isNaN(fromAmount) || fromAmount <= 0) {
            NotificationSystem.show('Please enter a valid amount', 'error');
            return;
        }

        const toAmount = (fromAmount * state.market.price).toFixed(2);
        DOM.swapToAmount.value = toAmount;

        // Simulate swap
        setTimeout(() => {
            simulateTransaction();
            NotificationSystem.show(`Swap successful: ${fromAmount} ETH for ${toAmount} USDT`, 'success');
            DOM.swapFromAmount.value = '';
            DOM.swapToAmount.value = '';
        }, 1500);
    }

    // Chart Renderer
    function renderChart() {
        if (!DOM.chartCanvas) return;

        const ctx = DOM.chartCanvas.getContext('2d');
        const width = DOM.chartCanvas.width;
        const height = DOM.chartCanvas.height;

        // Clear canvas
        ctx.clearRect(0, 0, width, height);

        if (state.chartData.prices.length < 2) return;

        // Find min and max values
        const minPrice = Math.min(...state.chartData.prices);
        const maxPrice = Math.max(...state.chartData.prices);
        const priceRange = maxPrice - minPrice;

        // Draw grid lines
        ctx.strokeStyle = 'rgba(255, 255, 255, 0.1)';
        ctx.lineWidth = 1;
        for (let i = 0; i < 5; i++) {
            const y = height - (i * height / 4);
            ctx.beginPath();
            ctx.moveTo(0, y);
            ctx.lineTo(width, y);
            ctx.stroke();
        }

        // Draw price line
        ctx.strokeStyle = '#38bdf8';
        ctx.lineWidth = 2;
        ctx.beginPath();
        const xStep = width / (state.chartData.prices.length - 1);
        for (let i = 0; i < state.chartData.prices.length; i++) {
            const x = i * xStep;
            const y = height - ((state.chartData.prices[i] - minPrice) / priceRange) * height;
            if (i === 0) {
                ctx.moveTo(x, y);
            } else {
                ctx.lineTo(x, y);
            }
        }
        ctx.stroke();
    }

    // UI Update Function
    function updateUI() {
        // Update wallet info
        if (state.wallet.connected) {
            DOM.walletAddress.textContent = `${state.wallet.address.slice(0, 6)}...${state.wallet.address.slice(-4)}`;
        } else {
            DOM.walletAddress.textContent = 'Not connected';
        }

        // Update gas price
        DOM.gasPrice.textContent = `${state.gas.current} Gwei`;

        // Update market data
        DOM.currentPrice.textContent = `$${state.market.price.toFixed(2)}`;
        DOM.priceChange.textContent = `${state.market.change24h.toFixed(2)}%`;
        DOM.priceChange.className = state.market.change24h >= 0 ? 'price-change positive' : 'price-change negative';

        // Update order book
        DOM.orderBookBids.innerHTML = state.orderBook.bids.map(order => {
            return `<div class="orderbook-row">
                <span class="orderbook-price positive">${order.price}</span>
                <span class="orderbook-amount">${order.amount}</span>
            </div>`;
        }).join('');

        DOM.orderBookAsks.innerHTML = state.orderBook.asks.map(order => {
            return `<div class="orderbook-row">
                <span class="orderbook-price negative">${order.price}</span>
                <span class="orderbook-amount">${order.amount}</span>
            </div>`;
        }).join('');

        // Update transaction history
        DOM.txList.innerHTML = state.transactions.map(tx => {
            return `<div class="transaction-item">
                <div class="transaction-info">
                    <span class="transaction-type ${tx.type.toLowerCase()}">${tx.type}</span>
                    <span class="transaction-amount">${tx.amount} ETH</span>
                    <span class="transaction-price">@ ${tx.price} USDT</span>
                </div>
                <div class="transaction-details">
                    <span class="transaction-total">${tx.total} USDT</span>
                    <span class="transaction-time">${tx.timestamp}</span>
                    <span class="transaction-status ${tx.status.toLowerCase()}">${tx.status}</span>
                </div>
            </div>`;
        }).join('');

        // Update portfolio
        DOM.portfolioTable.innerHTML = state.portfolio.map(asset => {
            return `<tr>
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
                        <div class="allocation-fill" style="width: ${asset.allocation}%"></div>
                    </div>
                    <span class="allocation-percent">${asset.allocation.toFixed(1)}%</span>
                </td>
            </tr>`;
        }).join('');

        // Render chart
        renderChart();
    }

    // Initialize the application
    function init() {
        initDOM();
        ThemeManager.init();
        updateUI();

        // Set up event listeners
        DOM.connectBtn.addEventListener('click', connectWallet);
        DOM.swapBtn.addEventListener('click', executeSwap);
        DOM.swapFromAmount.addEventListener('input', () => {
            const fromAmount = parseFloat(DOM.swapFromAmount.value);
            if (!isNaN(fromAmount) && fromAmount > 0) {
                DOM.swapToAmount.value = (fromAmount * state.market.price).toFixed(2);
            } else {
                DOM.swapToAmount.value = '';
            }
        });

        // Start data simulation
        setInterval(updateGasPrice, 15000);
        setInterval(simulateMarketData, 5000);
        setInterval(simulateOrderBook, 10000);
        setInterval(simulateTransaction, 30000);
    }

    // Start the application when DOM is loaded
    document.addEventListener('DOMContentLoaded', init);

})();