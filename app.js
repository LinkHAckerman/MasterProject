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

        oscillator.type = 'sine';
        oscillator.frequency.value = frequency;

        gainNode.gain.setValueAtTime(0, audioCtx.currentTime);
        gainNode.gain.linearRampToValueAtTime(0.5, audioCtx.currentTime + 0.01);
        gainNode.gain.linearRampToValueAtTime(0, audioCtx.currentTime + duration / 1000);

        oscillator.start();
        oscillator.stop(audioCtx.currentTime + duration / 1000);
    }

    // ---------------------------------------------------------------------
    // Utility Functions
    // ---------------------------------------------------------------------

    /**
     * Format a number with the specified decimal places
     * @param {number} value - The number to format
     * @param {number} decimals - Number of decimal places
     * @returns {string} Formatted number string
     */
    function formatNumber(value, decimals) {
        return value.toLocaleString(undefined, {
            minimumFractionDigits: decimals,
            maximumFractionDigits: decimals
        });
    }

    /**
     * Format a currency value with the user's preferred currency
     * @param {number} value - The amount to format
     * @returns {string} Formatted currency string
     */
    function formatCurrency(value) {
        return new Intl.NumberFormat(undefined, {
            style: 'currency',
            currency: state.settings.currency,
            minimumFractionDigits: 2,
            maximumFractionDigits: 2
        }).format(value);
    }

    /**
     * Format a percentage value
     * @param {number} value - The percentage value
     * @returns {string} Formatted percentage string
     */
    function formatPercentage(value) {
        return `${value.toFixed(1)}%`;
    }

    /**
     * Format a timestamp as a relative time string
     * @param {number} timestamp - The timestamp in milliseconds
     * @returns {string} Relative time string
     */
    function formatRelativeTime(timestamp) {
        const now = Date.now();
        const diff = now - timestamp;

        if (diff < 60000) {
            return 'Just now';
        } else if (diff < 3600000) {
            const minutes = Math.floor(diff / 60000);
            return `${minutes} minute${minutes !== 1 ? 's' : ''} ago`;
        } else if (diff < 86400000) {
            const hours = Math.floor(diff / 3600000);
            return `${hours} hour${hours !== 1 ? 's' : ''} ago`;
        } else {
            const days = Math.floor(diff / 86400000);
            return `${days} day${days !== 1 ? 's' : ''} ago`;
        }
    }

    /**
     * Generate a random transaction hash
     * @returns {string} Random transaction hash
     */
    function generateRandomHash() {
        return '0x' + Array.from({ length: 40 }, () => Math.floor(Math.random() * 16).toString(16)).join('');
    }

    /**
     * Generate a random block number
     * @returns {number} Random block number
     */
    function generateRandomBlockNumber() {
        return Math.floor(Math.random() * 10000000) + 19000000;
    }

    // ---------------------------------------------------------------------
    // Wallet Functions
    // ---------------------------------------------------------------------

    /**
     * Connect to a wallet
     */
    async function connectWallet() {
        // Simulate wallet connection
        state.wallet.connected = true;
        state.wallet.address = '0x' + Array.from({ length: 40 }, () => Math.floor(Math.random() * 16).toString(16)).join('');

        // Update UI
        updateWalletUI();
        updatePortfolioUI();
        updateTransactionsUI();

        // Play connection sound
        playTone(880, 200);
    }

    /**
     * Disconnect from the wallet
     */
    function disconnectWallet() {
        state.wallet.connected = false;
        state.wallet.address = null;

        // Update UI
        updateWalletUI();
        updatePortfolioUI();
        updateTransactionsUI();

        // Play disconnection sound
        playTone(440, 200);
    }

    /**
     * Update the wallet UI
     */
    function updateWalletUI() {
        if (state.wallet.connected) {
            DOM.walletAddress.textContent = `${state.wallet.address.slice(0, 6)}...${state.wallet.address.slice(-4)}`;
            DOM.walletBalance.textContent = formatCurrency(state.wallet.balanceEth * state.wallet.tokens.find(t => t.symbol === 'ETH').price);
            DOM.connectWalletBtn.textContent = 'Disconnect';
            DOM.connectWalletBtn.onclick = disconnectWallet;
            DOM.walletInfo.classList.remove('hidden');
        } else {
            DOM.walletAddress.textContent = 'Not connected';
            DOM.walletBalance.textContent = formatCurrency(0);
            DOM.connectWalletBtn.textContent = 'Connect Wallet';
            DOM.connectWalletBtn.onclick = connectWallet;
            DOM.walletInfo.classList.add('hidden');
        }
    }

    // ---------------------------------------------------------------------
    // Market Functions
    // ---------------------------------------------------------------------

    /**
     * Update market data
     */
    function updateMarketData() {
        const pair = PAIR_RATES[state.market.selectedPair];
        const change = (Math.random() - 0.5) * 0.02;
        const newPrice = pair.price * (1 + change);

        state.market.price = newPrice;
        state.market.change24h = change * 100;
        state.market.volume24h += Math.floor(Math.random() * 1000000);
        state.market.high24h = Math.max(state.market.high24h, newPrice);
        state.market.low24h = Math.min(state.market.low24h, newPrice);

        // Update chart data
        const now = new Date();
        state.market.chartData.labels.push(now.toLocaleTimeString());
        state.market.chartData.prices.push(newPrice);
        state.market.chartData.candles.push({
            open: pair.price,
            high: Math.max(pair.price, newPrice),
            low: Math.min(pair.price, newPrice),
            close: newPrice
        });

        // Keep only the last 60 data points
        if (state.market.chartData.labels.length > 60) {
            state.market.chartData.labels.shift();
            state.market.chartData.prices.shift();
            state.market.chartData.candles.shift();
        }

        // Update UI
        updateMarketUI();
        updateChart();
    }

    /**
     * Update the market UI
     */
    function updateMarketUI() {
        DOM.marketPrice.textContent = formatCurrency(state.market.price);
        DOM.marketChange.textContent = `${state.market.change24h >= 0 ? '+' : ''}${formatPercentage(state.market.change24h)}`;
        DOM.marketChange.classList.toggle('text-green-500', state.market.change24h >= 0);
        DOM.marketChange.classList.toggle('text-red-500', state.market.change24h < 0);
        DOM.marketVolume.textContent = formatNumber(state.market.volume24h, 0);
        DOM.marketHigh.textContent = formatCurrency(state.market.high24h);
        DOM.marketLow.textContent = formatCurrency(state.market.low24h);
    }

    /**
     * Update the chart
     */
    function updateChart() {
        const ctx = DOM.chartCanvas.getContext('2d');
        const width = DOM.chartCanvas.width;
        const height = DOM.chartCanvas.height;

        // Clear canvas
        ctx.clearRect(0, 0, width, height);

        // Draw chart
        if (state.market.chartData.prices.length > 1) {
            const minPrice = Math.min(...state.market.chartData.prices);
            const maxPrice = Math.max(...state.market.chartData.prices);
            const priceRange = maxPrice - minPrice;

            // Draw grid lines
            ctx.strokeStyle = '#374151';
            ctx.lineWidth = 1;
            ctx.setLineDash([5, 5]);

            for (let i = 1; i < 5; i++) {
                const y = height - (i * height / 5);
                ctx.beginPath();
                ctx.moveTo(0, y);
                ctx.lineTo(width, y);
                ctx.stroke();
            }

            ctx.setLineDash([]);

            // Draw price line
            ctx.strokeStyle = '#3b82f6';
            ctx.lineWidth = 2;
            ctx.beginPath();

            for (let i = 0; i < state.market.chartData.prices.length; i++) {
                const x = (i / (state.market.chartData.prices.length - 1)) * width;
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
    // Order Book Functions
    // ---------------------------------------------------------------------

    /**
     * Update the order book
     */
    function updateOrderBook() {
        const pair = PAIR_RATES[state.market.selectedPair];
        const midPrice = pair.price;
        const spread = midPrice * 0.02;

        // Generate random bids and asks
        const bids = [];
        const asks = [];

        for (let i = 0; i < state.orderBook.maxDepth; i++) {
            const bidPrice = midPrice - (i * spread / state.orderBook.maxDepth);
            const askPrice = midPrice + (i * spread / state.orderBook.maxDepth);
            const bidSize = Math.random() * 10;
            const askSize = Math.random() * 10;

            bids.push({ price: bidPrice, size: bidSize });
            asks.push({ price: askPrice, size: askSize });
        }

        // Sort bids and asks
        bids.sort((a, b) => b.price - a.price);
        asks.sort((a, b) => a.price - b.price);

        state.orderBook.bids = bids;
        state.orderBook.asks = asks;

        // Update UI
        updateOrderBookUI();
    }

    /**
     * Update the order book UI
     */
    function updateOrderBookUI() {
        // Clear existing entries
        DOM.orderBookBids.innerHTML = '';
        DOM.orderBookAsks.innerHTML = '';

        // Add bids
        state.orderBook.bids.forEach(bid => {
            const row = document.createElement('tr');
            row.innerHTML = `
                <td class="text-right pr-2">${formatNumber(bid.price, PAIR_RATES[state.market.selectedPair].decimals)}</td>
                <td class="text-right pr-2">${formatNumber(bid.size, 2)}</td>
                <td class="w-full">
                    <div class="h-4 bg-green-500 opacity-20" style="width: ${bid.size * 10}%"></div>
                </td>
            `;
            DOM.orderBookBids.appendChild(row);
        });

        // Add asks
        state.orderBook.asks.forEach(ask => {
            const row = document.createElement('tr');
            row.innerHTML = `
                <td class="text-right pr-2">${formatNumber(ask.price, PAIR_RATES[state.market.selectedPair].decimals)}</td>
                <td class="text-right pr-2">${formatNumber(ask.size, 2)}</td>
                <td class="w-full">
                    <div class="h-4 bg-red-500 opacity-20" style="width: ${ask.size * 10}%"></div>
                </td>
            `;
            DOM.orderBookAsks.appendChild(row);
        });
    }

    // ---------------------------------------------------------------------
    // Transaction Functions
    // ---------------------------------------------------------------------

    /**
     * Add a new transaction to the state
     * @param {string} type - Transaction type
     * @param {string} description - Transaction description
     * @param {string} amount - Transaction amount
     */
    function addTransaction(type, description, amount) {
        const transaction = {
            hash: generateRandomHash(),
            type,
            description,
            amount,
            status: 'Pending',
            timestamp: Date.now(),
            blockNumber: generateRandomBlockNumber()
        };

        state.transactions.unshift(transaction);

        // Update UI
        updateTransactionsUI();

        // Simulate transaction confirmation
        setTimeout(() => {
            transaction.status = 'Confirmed';
            updateTransactionsUI();
        }, 5000);
    }

    /**
     * Update the transactions UI
     */
    function updateTransactionsUI() {
        DOM.transactionsList.innerHTML = '';

        state.transactions.forEach(tx => {
            const row = document.createElement('tr');
            row.innerHTML = `
                <td class="py-2 px-4">
                    <div class="flex items-center">
                        <span class="w-2 h-2 rounded-full mr-2 ${tx.status === 'Confirmed' ? 'bg-green-500' : 'bg-yellow-500'} animate-pulse"></span>
                        <span class="truncate max-w-xs">${tx.hash}</span>
                    </div>
                </td>
                <td class="py-2 px-4">${tx.type}</td>
                <td class="py-2 px-4">${tx.description}</td>
                <td class="py-2 px-4">${tx.amount}</td>
                <td class="py-2 px-4">${tx.status}</td>
                <td class="py-2 px-4">${formatRelativeTime(tx.timestamp)}</td>
                <td class="py-2 px-4">${tx.blockNumber}</td>
            `;
            DOM.transactionsList.appendChild(row);
        });
    }

    // ---------------------------------------------------------------------
    // Portfolio Functions
    // ---------------------------------------------------------------------

    /**
     * Update the portfolio data
     */
    function updatePortfolio() {
        const totalValue = state.wallet.tokens.reduce((sum, token) => {
            const tokenValue = token.balance * token.price;
            return sum + tokenValue;
        }, 0);

        state.portfolio = state.wallet.tokens.map(token => {
            const tokenValue = token.balance * token.price;
            return {
                symbol: token.symbol,
                name: token.name,
                balance: token.balance,
                price: token.price,
                value: tokenValue,
                allocation: (tokenValue / totalValue) * 100
            };
        });

        // Update UI
        updatePortfolioUI();
    }

    /**
     * Update the portfolio UI
     */
    function updatePortfolioUI() {
        DOM.portfolioList.innerHTML = '';

        state.portfolio.forEach(asset => {
            const row = document.createElement('tr');
            row.innerHTML = `
                <td class="py-2 px-4">${asset.symbol}</td>
                <td class="py-2 px-4">${asset.name}</td>
                <td class="py-2 px-4">${formatNumber(asset.balance, 4)}</td>
                <td class="py-2 px-4">${formatCurrency(asset.price)}</td>
                <td class="py-2 px-4">${formatCurrency(asset.value)}</td>
                <td class="py-2 px-4">${formatPercentage(asset.allocation)}</td>
            `;
            DOM.portfolioList.appendChild(row);
        });
    }

    // ---------------------------------------------------------------------
    // Staking Functions
    // ---------------------------------------------------------------------

    /**
     * Update staking data
     */
    function updateStaking() {
        const now = Date.now();
        const timeSinceLastClaim = now - state.staking.lastClaimed;
        const hoursSinceLastClaim = timeSinceLastClaim / 3600000;

        // Calculate pending rewards
        const dailyRewardRate = state.staking.rewardRateApy / 365;
        const rewardPerHour = (state.staking.stakedOpus * dailyRewardRate) / 24;
        state.staking.pendingRewards = rewardPerHour * hoursSinceLastClaim;

        // Update UI
        updateStakingUI();
    }

    /**
     * Update the staking UI
     */
    function updateStakingUI() {
        DOM.stakedOpus.textContent = formatNumber(state.staking.stakedOpus, 2);
        DOM.rewardRate.textContent = formatPercentage(state.staking.rewardRateApy);
        DOM.pendingRewards.textContent = formatNumber(state.staking.pendingRewards, 2);
        DOM.lastClaimed.textContent = formatRelativeTime(state.staking.lastClaimed);
    }

    /**
     * Claim staking rewards
     */
    function claimRewards() {
        if (state.staking.pendingRewards > 0) {
            const rewardToken = state.wallet.tokens.find(t => t.symbol === 'OPUS');
            rewardToken.balance += state.staking.pendingRewards;

            state.staking.pendingRewards = 0;
            state.staking.lastClaimed = Date.now();

            // Add transaction
            addTransaction('Reward', 'Claimed staking rewards', `${formatNumber(state.staking.pendingRewards, 2)} OPUS`);

            // Update UI
            updateStakingUI();
            updatePortfolio();

            // Play sound
            playTone(660, 200);
        }
    }

    // ---------------------------------------------------------------------
    // Swap Functions
    // ---------------------------------------------------------------------

    /**
     * Perform a token swap
     */
    function performSwap() {
        const fromToken = DOM.swapFromToken.value;
        const toToken = DOM.swapToToken.value;
        const amount = parseFloat(DOM.swapAmount.value);

        if (!fromToken || !toToken || isNaN(amount) || amount <= 0) {
            alert('Please enter valid swap details');
            return;
        }

        const fromTokenData = state.wallet.tokens.find(t => t.symbol === fromToken);
        const toTokenData = state.wallet.tokens.find(t => t.symbol === toToken);

        if (!fromTokenData || !toTokenData) {
            alert('Invalid token selection');
            return;
        }

        if (fromTokenData.balance < amount) {
            alert('Insufficient balance');
            return;
        }

        // Calculate swap
        const pairKey = `${fromToken}/${toToken}`;
        const pair = PAIR_RATES[pairKey];

        if (!pair) {
            alert('Unsupported token pair');
            return;
        }

        const receivedAmount = amount * pair.price;

        // Update balances
        fromTokenData.balance -= amount;
        toTokenData.balance += receivedAmount;

        // Add transaction
        addTransaction('Swap', `Swapped ${formatNumber(amount, 4)} ${fromToken} for ${formatNumber(receivedAmount, 4)} ${toToken}`, `${formatNumber(amount, 4)} ${fromToken}`);

        // Update UI
        updatePortfolio();
        updateMarketUI();
        updateOrderBook();

        // Play sound
        playTone(784, 200);
    }

    // ---------------------------------------------------------------------
    // Initialization
    // ---------------------------------------------------------------------

    /**
     * Initialize the DOM elements cache
     */
    function initDOM() {
        // Wallet elements
        DOM.walletAddress = document.getElementById('wallet-address');
        DOM.walletBalance = document.getElementById('wallet-balance');
        DOM.connectWalletBtn = document.getElementById('connect-wallet-btn');
        DOM.walletInfo = document.getElementById('wallet-info');

        // Market elements
        DOM.marketPrice = document.getElementById('market-price');
        DOM.marketChange = document.getElementById('market-change');
        DOM.marketVolume = document.getElementById('market-volume');
        DOM.marketHigh = document.getElementById('market-high');
        DOM.marketLow = document.getElementById('market-low');
        DOM.chartCanvas = document.getElementById('chart-canvas');

        // Order book elements
        DOM.orderBookBids = document.getElementById('order-book-bids');
        DOM.orderBookAsks = document.getElementById('order-book-asks');

        // Transactions elements
        DOM.transactionsList = document.getElementById('transactions-list');

        // Portfolio elements
        DOM.portfolioList = document.getElementById('portfolio-list');

        // Staking elements
        DOM.stakedOpus = document.getElementById('staked-opus');
        DOM.rewardRate = document.getElementById('reward-rate');
        DOM.pendingRewards = document.getElementById('pending-rewards');
        DOM.lastClaimed = document.getElementById('last-claimed');
        DOM.claimRewardsBtn = document.getElementById('claim-rewards-btn');
        DOM.claimRewardsBtn.addEventListener('click', claimRewards);

        // Swap elements
        DOM.swapFromToken = document.getElementById('swap-from-token');
        DOM.swapToToken = document.getElementById('swap-to-token');
        DOM.swapAmount = document.getElementById('swap-amount');
        DOM.swapBtn = document.getElementById('swap-btn');
        DOM.swapBtn.addEventListener('click', performSwap);

        // Initialize token selectors
        const tokens = Object.values(PAIR_RATES).map(pair => pair.base).filter((value, index, self) => self.indexOf(value) === index);
        tokens.forEach(token => {
            const option1 = document.createElement('option');
            option1.value = token;
            option1.textContent = token;
            DOM.swapFromToken.appendChild(option1);

            const option2 = document.createElement('option');
            option2.value = token;
            option2.textContent = token;
            DOM.swapToToken.appendChild(option2);
        });
    }

    /**
     * Initialize the application
     */
    function init() {
        initDOM();
        updateWalletUI();
        updateMarketUI();
        updateOrderBookUI();
        updateTransactionsUI();
        updatePortfolioUI();
        updateStakingUI();
        updateChart();

        // Start engine tickers
        marketInterval = setInterval(updateMarketData, state.settings.autoRefreshInterval);
        gasInterval = setInterval(updateGasPrices, state.settings.autoRefreshInterval * 2);
        orderBookInterval = setInterval(updateOrderBook, state.settings.autoRefreshInterval * 3);
        stakingInterval = setInterval(updateStaking, state.settings.autoRefreshInterval * 4);
    }

    // Initialize the application when the DOM is loaded
    document.addEventListener('DOMContentLoaded', init);

    // Expose functions to the global scope for debugging
    window.magnumOpus = {
        state,
        updateMarketData,
        updateOrderBook,
        updatePortfolio,
        updateStaking,
        addTransaction,
        playTone
    };

})();
