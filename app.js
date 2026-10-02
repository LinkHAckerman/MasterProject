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
            networkSelector: document.getElementById('network-selector'),
            tokenSelector: document.getElementById('token-selector'),
            swapFromToken: document.getElementById('swap-from-token'),
            swapToToken: document.getElementById('swap-to-token'),
            swapDirectionBtn: document.getElementById('swap-direction-btn'),
            gasSelector: document.getElementById('gas-selector')
        };
    }

    function setupEventListeners() {
        DOM.connectBtn.addEventListener('click', connectWallet);
        DOM.pairSelect.addEventListener('change', changeMarketPair);
        DOM.swapFromAmount.addEventListener('input', calculateSwap);
        DOM.swapToAmount.addEventListener('input', calculateSwap);
        DOM.swapBtn.addEventListener('click', executeSwap);
        DOM.themeToggle.addEventListener('click', toggleTheme);
        DOM.networkSelector.addEventListener('change', changeNetwork);
        DOM.tokenSelector.addEventListener('change', selectToken);
        DOM.swapDirectionBtn.addEventListener('click', reverseSwapTokens);
        DOM.gasSelector.addEventListener('change', updateGasPrice);
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
                    borderWidth: 2,
                    pointRadius: 0,
                    fill: true
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
                animation: {
                    duration: 0
                }
            }
        });
    }

    function connectWebSocket() {
        socket = new WebSocket('wss://api.magnumopus.io/ws');

        socket.onopen = function() {
            console.log('WebSocket connection established');
            subscribeToMarketData();
        };

        socket.onmessage = function(event) {
            const data = JSON.parse(event.data);
            handleWebSocketMessage(data);
        };

        socket.onclose = function() {
            console.log('WebSocket connection closed');
            setTimeout(connectWebSocket, 5000);
        };
    }

    function subscribeToMarketData() {
        const subscription = {
            type: 'subscribe',
            channels: [
                {
                    name: 'market',
                    pair: state.market.selectedPair
                },
                {
                    name: 'orderbook',
                    pair: state.market.selectedPair
                }
            ]
        };
        socket.send(JSON.stringify(subscription));
    }

    function handleWebSocketMessage(data) {
        switch (data.type) {
            case 'market_update':
                updateMarketData(data);
                break;
            case 'orderbook_update':
                updateOrderBook(data);
                break;
            case 'transaction':
                addTransaction(data);
                break;
            case 'wallet_update':
                updateWallet(data);
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
        if (state.market.chartData.labels.length > 60) {
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

    function addTransaction(data) {
        state.transactions.unshift(data);
        if (state.transactions.length > 20) {
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
        updateWalletDisplay();
        updateMarketDisplay();
        updateOrderBookDisplay();
        updateTransactionList();
        updatePortfolioDisplay();
        updateChart();
    }

    function updateWalletDisplay() {
        if (state.wallet.connected) {
            DOM.walletAddress.textContent = `${state.wallet.address.slice(0, 6)}...${state.wallet.address.slice(-4)}`;
            DOM.connectBtn.textContent = 'Disconnect';
        } else {
            DOM.walletAddress.textContent = 'Not connected';
            DOM.connectBtn.textContent = 'Connect Wallet';
        }

        DOM.gasPrice.textContent = `${state.gas.current} Gwei`;
    }

    function updateMarketDisplay() {
        DOM.currentPrice.textContent = `$${state.market.price.toFixed(2)}`;
        DOM.priceChange.textContent = `${state.market.change24h.toFixed(2)}%`;
        DOM.priceChange.style.color = state.market.change24h >= 0 ? '#10b981' : '#f43f5e';
    }

    function updateOrderBookDisplay() {
        DOM.orderBookBids.innerHTML = '';
        DOM.orderBookAsks.innerHTML = '';

        // Display top 10 bids
        state.orderBook.bids.slice(0, 10).forEach((bid, index) => {
            const bidElement = document.createElement('div');
            bidElement.className = 'orderbook-entry';
            bidElement.innerHTML = `
                <span class="orderbook-price" style="color: #10b981">$${bid.price.toFixed(2)}</span>
                <span class="orderbook-amount">${bid.amount.toFixed(4)}</span>
                <div class="orderbook-bar" style="width: ${bid.amount * 10}px; background-color: rgba(16, 185, 129, 0.2)"></div>
            `;
            DOM.orderBookBids.appendChild(bidElement);
        });

        // Display top 10 asks
        state.orderBook.asks.slice(0, 10).forEach((ask, index) => {
            const askElement = document.createElement('div');
            askElement.className = 'orderbook-entry';
            askElement.innerHTML = `
                <span class="orderbook-price" style="color: #f43f5e">$${ask.price.toFixed(2)}</span>
                <span class="orderbook-amount">${ask.amount.toFixed(4)}</span>
                <div class="orderbook-bar" style="width: ${ask.amount * 10}px; background-color: rgba(244, 63, 94, 0.2)"></div>
            `;
            DOM.orderBookAsks.appendChild(askElement);
        });
    }

    function updateTransactionList() {
        DOM.txList.innerHTML = '';
        state.transactions.slice(0, 10).forEach(tx => {
            const txElement = document.createElement('div');
            txElement.className = 'transaction-item';
            txElement.innerHTML = `
                <div class="transaction-icon">
                    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
                        <path d="M12 2C6.48 2 2 6.48 2 12C2 17.52 6.48 22 12 22C17.52 22 22 17.52 22 12C22 6.48 17.52 2 12 2ZM12 20C7.59 20 4 16.41 4 12C4 7.59 7.59 4 12 4C16.41 4 20 7.59 20 12C20 16.41 16.41 20 12 20Z" fill="${tx.type === 'buy' ? '#10b981' : '#f43f5e'}"/>
                        <path d="M12 17L8 13H11V7H13V13H16L12 17Z" fill="#fff"/>
                    </svg>
                </div>
                <div class="transaction-details">
                    <div class="transaction-type">${tx.type === 'buy' ? 'Buy' : 'Sell'} ${tx.amount.toFixed(4)} ${tx.pair.split('/')[0]}</div>
                    <div class="transaction-time">${new Date(tx.timestamp).toLocaleTimeString()}</div>
                </div>
                <div class="transaction-amount">${tx.type === 'buy' ? '+' : '-'}${tx.total.toFixed(2)} ${tx.pair.split('/')[1]}</div>
            `;
            DOM.txList.appendChild(txElement);
        });
    }

    function updatePortfolioDisplay() {
        DOM.portfolioTable.innerHTML = '';
        state.portfolio.forEach(asset => {
            const row = document.createElement('tr');
            row.innerHTML = `
                <td>
                    <div class="asset-info">
                        <div class="asset-icon">${asset.symbol.charAt(0)}</div>
                        <div class="asset-details">
                            <div class="asset-symbol">${asset.symbol}</div>
                            <div class="asset-name">${asset.name}</div>
                        </div>
                    </div>
                </td>
                <td>$${asset.price.toFixed(2)}</td>
                <td>${asset.balance.toFixed(4)}</td>
                <td>$${asset.value.toFixed(2)}</td>
                <td>
                    <div class="allocation-bar">
                        <div class="allocation-fill" style="width: ${asset.allocation}%; background: linear-gradient(to right, #38bdf8, #a855f7)"></div>
                    </div>
                </td>
            `;
            DOM.portfolioTable.appendChild(row);
        });
    }

    function updateChart() {
        priceChart.data.labels = state.market.chartData.labels;
        priceChart.data.datasets[0].data = state.market.chartData.prices;
        priceChart.update();
    }

    function connectWallet() {
        if (state.wallet.connected) {
            state.wallet.connected = false;
            state.wallet.address = null;
            updateUI();
            return;
        }

        // Simulate wallet connection
        setTimeout(() => {
            state.wallet.connected = true;
            state.wallet.address = '0x742d35Cc6634C0532925a3b844Bc454e4438f44e';
            updateUI();
            addNotification('Wallet connected successfully', 'success');
        }, 1000);
    }

    function changeMarketPair() {
        state.market.selectedPair = DOM.pairSelect.value;
        subscribeToMarketData();
        updateUI();
    }

    function calculateSwap() {
        if (DOM.swapFromAmount.value === '') {
            DOM.swapToAmount.value = '';
            return;
        }

        const amount = parseFloat(DOM.swapFromAmount.value);
        const rate = state.market.price;
        DOM.swapToAmount.value = (amount * rate).toFixed(2);
    }

    function executeSwap() {
        if (!state.wallet.connected) {
            addNotification('Please connect your wallet first', 'error');
            return;
        }

        const fromAmount = parseFloat(DOM.swapFromAmount.value);
        const toAmount = parseFloat(DOM.swapToAmount.value);

        if (isNaN(fromAmount) || fromAmount <= 0) {
            addNotification('Please enter a valid amount', 'error');
            return;
        }

        // Simulate swap execution
        setTimeout(() => {
            const tx = {
                type: 'buy',
                pair: state.market.selectedPair,
                amount: fromAmount,
                price: state.market.price,
                total: toAmount,
                timestamp: Date.now()
            };
            addTransaction(tx);
            addNotification('Swap executed successfully', 'success');

            // Update wallet balances
            state.wallet.balanceEth -= fromAmount;
            state.wallet.balanceUsdt += toAmount;
            updateUI();
        }, 1500);
    }

    function toggleTheme() {
        const newTheme = state.settings.theme === 'dark' ? 'light' : 'dark';
        state.settings.theme = newTheme;
        document.documentElement.setAttribute('data-theme', newTheme);
        DOM.themeToggle.textContent = newTheme === 'dark' ? '☀️' : '🌙';
    }

    function changeNetwork() {
        const networkId = DOM.networkSelector.value;
        switch (networkId) {
            case '0x1':
                state.wallet.networkName = 'Ethereum Mainnet';
                break;
            case '0x3':
                state.wallet.networkName = 'Ropsten Testnet';
                break;
            case '0x89':
                state.wallet.networkName = 'Polygon Mainnet';
                break;
            case '0xa86a':
                state.wallet.networkName = 'Avalanche Mainnet';
                break;
        }
        state.wallet.chainId = networkId;
        addNotification(`Network changed to ${state.wallet.networkName}`, 'info');
    }

    function selectToken() {
        const tokenAddress = DOM.tokenSelector.value;
        // In a real implementation, we would fetch token details here
        addNotification(`Token selected: ${tokenAddress}`, 'info');
    }

    function reverseSwapTokens() {
        const fromToken = DOM.swapFromToken.textContent;
        const toToken = DOM.swapToToken.textContent;
        DOM.swapFromToken.textContent = toToken;
        DOM.swapToToken.textContent = fromToken;
        calculateSwap();
    }

    function updateGasPrice() {
        const gasOption = DOM.gasSelector.value;
        switch (gasOption) {
            case 'slow':
                state.gas.current = state.gas.slow;
                break;
            case 'standard':
                state.gas.current = state.gas.standard;
                break;
            case 'fast':
                state.gas.current = state.gas.fast;
                break;
        }
        updateUI();
    }

    function addNotification(message, type) {
        const notification = {
            id: Date.now(),
            message,
            type
        };
        state.notifications.unshift(notification);
        if (state.notifications.length > 5) {
            state.notifications.pop();
        }
        renderNotifications();
    }

    function renderNotifications() {
        DOM.notificationContainer.innerHTML = '';
        state.notifications.forEach(notification => {
            const notificationElement = document.createElement('div');
            notificationElement.className = `notification notification-${notification.type}`;
            notificationElement.textContent = notification.message;
            DOM.notificationContainer.appendChild(notificationElement);
        });
    }

    // Initialize the application when the DOM is loaded
    document.addEventListener('DOMContentLoaded', init);

})();