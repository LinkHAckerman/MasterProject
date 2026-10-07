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
            portfolioTable: document.getElementById('portfolio-table-body'),
            tokenSearch: document.getElementById('token-search-input'),
            tokenList: document.getElementById('token-list'),
            modal: document.getElementById('modal'),
            modalContent: document.getElementById('modal-content'),
            closeModal: document.getElementById('close-modal')
        };
    }

    function setupEventListeners() {
        DOM.connectBtn.addEventListener('click', connectWallet);
        DOM.pairSelect.addEventListener('change', changeMarketPair);
        DOM.swapBtn.addEventListener('click', executeSwap);
        DOM.swapFromAmount.addEventListener('input', calculateSwap);
        DOM.swapToAmount.addEventListener('input', calculateSwap);
        DOM.themeToggle.addEventListener('change', toggleTheme);
        DOM.currencySelect.addEventListener('change', changeCurrency);
        DOM.languageSelect.addEventListener('change', changeLanguage);
        DOM.tokenSearch.addEventListener('input', searchTokens);
        DOM.closeModal.addEventListener('click', closeModal);
        window.addEventListener('click', outsideClick);
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
                updateMarketData(data);
                break;
            case 'orderbook_update':
                updateOrderBook(data);
                break;
            case 'transaction_update':
                updateTransactions(data);
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
        if (state.market.chartData.labels.length >= 60) {
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

    function updateTransactions(data) {
        state.transactions.unshift(data.transaction);
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

        // Update notifications
        updateNotificationsUI();
    }

    function updateOrderBookUI() {
        // Clear existing entries
        DOM.orderBookBids.innerHTML = '';
        DOM.orderBookAsks.innerHTML = '';

        // Add bids
        state.orderBook.bids.slice(0, 10).forEach(bid => {
            const bidElement = document.createElement('div');
            bidElement.className = 'orderbook-entry';
            bidElement.innerHTML = `
                <span class="orderbook-price" style="color: #10b981">$${bid.price.toFixed(2)}</span>
                <span class="orderbook-amount">${bid.amount.toFixed(4)}</span>
                <span class="orderbook-total">$${(bid.price * bid.amount).toFixed(2)}</span>
            `;
            DOM.orderBookBids.appendChild(bidElement);
        });

        // Add asks
        state.orderBook.asks.slice(0, 10).forEach(ask => {
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

        state.transactions.slice(0, 10).forEach(tx => {
            const txElement = document.createElement('div');
            txElement.className = 'transaction-item';
            txElement.innerHTML = `
                <div class="transaction-icon">
                    <i class="fas ${tx.type === 'buy' ? 'fa-arrow-down' : 'fa-arrow-up'} ${tx.type === 'buy' ? 'text-emerald-500' : 'text-rose-500'}"></i>
                </div>
                <div class="transaction-details">
                    <div class="transaction-type">${tx.type === 'buy' ? 'Buy' : 'Sell'} ${tx.amount.toFixed(4)} ${tx.pair.split('/')[0]}</div>
                    <div class="transaction-time">${new Date(tx.timestamp).toLocaleTimeString()}</div>
                </div>
                <div class="transaction-amount">${tx.type === 'buy' ? '+' : '-'}${tx.amount.toFixed(4)} ${tx.pair.split('/')[0]}</div>
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
                    <div class="asset-icon">${asset.symbol.substring(0, 1)}</div>
                    <div class="asset-details">
                        <div class="asset-symbol">${asset.symbol}</div>
                        <div class="asset-name">${asset.name}</div>
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

    function updateNotificationsUI() {
        DOM.notificationContainer.innerHTML = '';

        state.notifications.slice(0, 3).forEach(notification => {
            const notificationElement = document.createElement('div');
            notificationElement.className = `notification ${notification.type}`;
            notificationElement.innerHTML = `
                <div class="notification-icon">
                    <i class="fas ${notification.icon}"></i>
                </div>
                <div class="notification-content">
                    <div class="notification-title">${notification.title}</div>
                    <div class="notification-message">${notification.message}</div>
                </div>
                <div class="notification-time">${new Date(notification.timestamp).toLocaleTimeString()}</div>
            `;
            DOM.notificationContainer.appendChild(notificationElement);
        });
    }

    function connectWallet() {
        if (state.wallet.connected) {
            state.wallet.connected = false;
            state.wallet.address = null;
            updateUI();
            addNotification('Wallet disconnected', 'Your wallet has been disconnected successfully.', 'info', 'fa-wallet');
        } else {
            // Simulate wallet connection
            setTimeout(() => {
                state.wallet.connected = true;
                state.wallet.address = '0x742d35Cc6634C0532925a3b844Bc454e4438f44e';
                updateUI();
                addNotification('Wallet connected', 'Your wallet has been connected successfully.', 'success', 'fa-wallet');
            }, 1000);
        }
    }

    function changeMarketPair() {
        state.market.selectedPair = DOM.pairSelect.value;
        // In a real implementation, we would fetch new market data for the selected pair
        addNotification('Market pair changed', `Now viewing ${state.market.selectedPair} market data.`, 'info', 'fa-chart-line');
    }

    function executeSwap() {
        const fromAmount = parseFloat(DOM.swapFromAmount.value);
        const toAmount = parseFloat(DOM.swapToAmount.value);

        if (isNaN(fromAmount) || fromAmount <= 0) {
            addNotification('Invalid amount', 'Please enter a valid amount to swap.', 'error', 'fa-exclamation-triangle');
            return;
        }

        // Simulate swap execution
        setTimeout(() => {
            // Update wallet balances
            state.wallet.balanceEth -= fromAmount;
            state.wallet.balanceUsdt += toAmount;

            // Add transaction to history
            const transaction = {
                type: 'sell',
                pair: state.market.selectedPair,
                amount: fromAmount,
                price: state.market.price,
                timestamp: Date.now()
            };
            state.transactions.unshift(transaction);
            if (state.transactions.length > 20) {
                state.transactions.pop();
            }

            // Update UI
            updateUI();
            addNotification('Swap executed', `Successfully swapped ${fromAmount.toFixed(4)} ETH for ${toAmount.toFixed(2)} USDT.`, 'success', 'fa-exchange-alt');
        }, 1500);
    }

    function calculateSwap() {
        const fromAmount = parseFloat(DOM.swapFromAmount.value);
        if (!isNaN(fromAmount) && fromAmount > 0) {
            const toAmount = fromAmount * state.market.price;
            DOM.swapToAmount.value = toAmount.toFixed(2);
        }
    }

    function toggleTheme() {
        state.settings.theme = DOM.themeToggle.checked ? 'dark' : 'light';
        document.documentElement.setAttribute('data-theme', state.settings.theme);
        addNotification('Theme changed', `Switched to ${state.settings.theme} mode.`, 'info', 'fa-moon');
    }

    function changeCurrency() {
        state.settings.currency = DOM.currencySelect.value;
        addNotification('Currency changed', `Currency set to ${state.settings.currency}.`, 'info', 'fa-dollar-sign');
    }

    function changeLanguage() {
        state.settings.language = DOM.languageSelect.value;
        addNotification('Language changed', `Language set to ${state.settings.language}.`, 'info', 'fa-language');
    }

    function searchTokens() {
        const searchTerm = DOM.tokenSearch.value.toLowerCase();
        const filteredTokens = state.wallet.tokens.filter(token =>
            token.name.toLowerCase().includes(searchTerm) ||
            token.symbol.toLowerCase().includes(searchTerm)
        );

        DOM.tokenList.innerHTML = '';

        filteredTokens.forEach(token => {
            const tokenElement = document.createElement('div');
            tokenElement.className = 'token-item';
            tokenElement.innerHTML = `
                <div class="token-icon">${token.symbol.substring(0, 1)}</div>
                <div class="token-details">
                    <div class="token-symbol">${token.symbol}</div>
                    <div class="token-name">${token.name}</div>
                </div>
                <div class="token-balance">${token.balance.toFixed(4)}</div>
            `;
            DOM.tokenList.appendChild(tokenElement);
        });
    }

    function addNotification(title, message, type, icon) {
        const notification = {
            title,
            message,
            type,
            icon,
            timestamp: Date.now()
        };
        state.notifications.unshift(notification);
        if (state.notifications.length > 5) {
            state.notifications.pop();
        }
        updateNotificationsUI();
    }

    function showModal(content) {
        DOM.modalContent.innerHTML = content;
        DOM.modal.style.display = 'block';
    }

    function closeModal() {
        DOM.modal.style.display = 'none';
    }

    function outsideClick(e) {
        if (e.target === DOM.modal) {
            closeModal();
        }
    }

    // Initialize the application when the DOM is fully loaded
    document.addEventListener('DOMContentLoaded', init);

    // Expose functions to global scope for debugging
    window.MagnumOpus = {
        state,
        updateUI,
        addNotification,
        showModal,
        closeModal
    };
})();