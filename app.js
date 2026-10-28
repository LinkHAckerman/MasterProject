/**
 * MAGNUM OPUS // Web3 & DeFi Nexus Engine - Core Dashboard Application Logic
 * High-performance interactive dashboard engine with real-time data feeds,
 * simulated wallet interactions, orderbook engine, canvas chart renderer,
 * DEX swap routing, yield staking, and Web Audio sound engine.
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

    // Engine Tickers
    let marketInterval = null;
    let gasInterval = null;
    let orderBookInterval = null;
    let stakingInterval = null;

    // Audio context for procedural Web Audio sound synthesis
    let audioCtx = null;

    /**
     * Web Audio Sound Synthesizer
     */
    function playAudioTone(freq, type = 'sine', duration = 0.15, gainVal = 0.05) {
        if (!state.settings.enableSounds) return;
        try {
            if (!audioCtx) {
                audioCtx = new (window.AudioContext || window.webkitAudioContext)();
            }
            if (audioCtx.state === 'suspended') {
                audioCtx.resume();
            }
            const osc = audioCtx.createOscillator();
            const gain = audioCtx.createGain();
            osc.type = type;
            osc.frequency.setValueAtTime(freq, audioCtx.currentTime);
            gain.gain.setValueAtTime(gainVal, audioCtx.currentTime);
            gain.gain.exponentialRampToValueAtTime(0.0001, audioCtx.currentTime + duration);
            osc.connect(gain);
            gain.connect(audioCtx.destination);
            osc.start();
            osc.stop(audioCtx.currentTime + duration);
        } catch (e) {
            console.warn('Audio playback failed:', e);
        }
    }

    /**
     * Generate synthetic candlestick chart data
     */
    function generateChartData(length = 50) {
        const candles = [];
        const labels = [];
        const prices = [];
        let basePrice = state.market.price;
        for (let i = 0; i < length; i++) {
            const open = basePrice + (Math.random() - 0.5) * basePrice * 0.02;
            const close = open + (Math.random() - 0.5) * open * 0.015;
            const high = Math.max(open, close) + Math.random() * open * 0.01;
            const low = Math.min(open, close) - Math.random() * open * 0.01;
            candles.push({ open, high, low, close });
            prices.push(close);
            labels.push(`T-${length - i}`);
            basePrice = close;
        }
        return { labels, prices, candles };
    }

    /**
     * Render candlestick chart on canvas
     */
    function renderChart() {
        const canvas = DOM.chartCanvas;
        if (!canvas) return;
        const ctx = canvas.getContext('2d');
        const { candles, labels } = state.market.chartData;
        if (candles.length === 0) return;

        const width = canvas.width;
        const height = canvas.height;
        ctx.clearRect(0, 0, width, height);

        const padding = 40;
        const chartWidth = width - padding * 2;
        const chartHeight = height - padding * 2;
        const candleCount = Math.min(candles.length, 20);
        const visibleCandles = candles.slice(-candleCount);
        const candleWidth = chartWidth / candleCount * 0.7;
        const spacing = chartWidth / candleCount;

        const allHighs = visibleCandles.map(c => c.high);
        const allLows = visibleCandles.map(c => c.low);
        const maxPrice = Math.max(...allHighs);
        const minPrice = Math.min(...allLows);
        const priceRange = maxPrice - minPrice || 1;

        // Draw grid lines
        ctx.strokeStyle = 'rgba(255,255,255,0.05)';
        ctx.lineWidth = 1;
        for (let i = 0; i <= 5; i++) {
            const y = padding + (chartHeight / 5) * i;
            ctx.beginPath();
            ctx.moveTo(padding, y);
            ctx.lineTo(width - padding, y);
            ctx.stroke();
        }

        // Draw candles
        visibleCandles.forEach((candle, index) => {
            const x = padding + index * spacing + spacing / 2;
            const yHigh = padding + chartHeight - ((candle.high - minPrice) / priceRange) * chartHeight;
            const yLow = padding + chartHeight - ((candle.low - minPrice) / priceRange) * chartHeight;
            const yOpen = padding + chartHeight - ((candle.open - minPrice) / priceRange) * chartHeight;
            const yClose = padding + chartHeight - ((candle.close - minPrice) / priceRange) * chartHeight;

            // Wick
            ctx.strokeStyle = candle.close >= candle.open ? '#26a69a' : '#ef5350';
            ctx.lineWidth = 1;
            ctx.beginPath();
            ctx.moveTo(x, yHigh);
            ctx.lineTo(x, yLow);
            ctx.stroke();

            // Body
            const bodyHeight = Math.abs(yOpen - yClose);
            const bodyY = Math.min(yOpen, yClose);
            ctx.fillStyle = candle.close >= candle.open ? '#26a69a' : '#ef5350';
            ctx.fillRect(x - candleWidth / 2, bodyY, candleWidth, bodyHeight || 1);
        });

        // Draw price line
        ctx.strokeStyle = 'rgba(100, 180, 255, 0.6)';
        ctx.lineWidth = 1;
        ctx.setLineDash([5, 5]);
        const lastPriceY = padding + chartHeight - ((visibleCandles[visibleCandles.length - 1].close - minPrice) / priceRange) * chartHeight;
        ctx.beginPath();
        ctx.moveTo(padding, lastPriceY);
        ctx.lineTo(width - padding, lastPriceY);
        ctx.stroke();
        ctx.setLineDash([]);
    }

    /**
     * Generate synthetic order book data
     */
    function generateOrderBook() {
        const bids = [];
        const asks = [];
        const centerPrice = state.market.price;
        for (let i = 0; i < state.orderBook.maxDepth; i++) {
            const bidPrice = centerPrice - (i + 1) * centerPrice * 0.001;
            const askPrice = centerPrice + (i + 1) * centerPrice * 0.001;
            const bidAmount = Math.random() * 10 + 1;
            const askAmount = Math.random() * 10 + 1;
            bids.push({ price: bidPrice, amount: bidAmount });
            asks.push({ price: askPrice, amount: askAmount });
        }
        return { bids, asks };
    }

    /**
     * Render order book to DOM
     */
    function renderOrderBook() {
        const bidsContainer = DOM.orderBookBids;
        const asksContainer = DOM.orderBookAsks;
        if (!bidsContainer || !asksContainer) return;

        bidsContainer.innerHTML = '';
        asksContainer.innerHTML = '';

        state.orderBook.bids.slice().reverse().forEach(bid => {
            const row = document.createElement('div');
            row.className = 'orderbook-row bid';
            row.innerHTML = `
                <span class="price">${bid.price.toFixed(2)}</span>
                <span class="amount">${bid.amount.toFixed(4)}</span>
                <span class="total">${(bid.price * bid.amount).toFixed(2)}</span>
            `;
            bidsContainer.appendChild(row);
        });

        state.orderBook.asks.forEach(ask => {
            const row = document.createElement('div');
            row.className = 'orderbook-row ask';
            row.innerHTML = `
                <span class="price">${ask.price.toFixed(2)}</span>
                <span class="amount">${ask.amount.toFixed(4)}</span>
                <span class="total">${(ask.price * ask.amount).toFixed(2)}</span>
            `;
            asksContainer.appendChild(row);
        });
    }

    /**
     * Update gas price simulation
     */
    function updateGasPrice() {
        const variation = (Math.random() - 0.5) * 4;
        state.gas.current = Math.max(8, Math.min(30, state.gas.current + variation));
        state.gas.slow = Math.max(5, state.gas.current - 6);
        state.gas.standard = state.gas.current;
        state.gas.fast = state.gas.current + 6;
        if (DOM.gasCurrent) DOM.gasCurrent.textContent = state.gas.current.toFixed(1);
        if (DOM.gasSlow) DOM.gasSlow.textContent = state.gas.slow.toFixed(1);
        if (DOM.gasStandard) DOM.gasStandard.textContent = state.gas.standard.toFixed(1);
        if (DOM.gasFast) DOM.gasFast.textContent = state.gas.fast.toFixed(1);
    }

    /**
     * Update staking rewards
     */
    function updateStaking() {
        const elapsed = (Date.now() - state.staking.lastClaimed) / 86400000;
        const dailyReward = (state.staking.stakedOpus * state.staking.rewardRateApy / 100) / 365;
        state.staking.pendingRewards = parseFloat((dailyReward * elapsed).toFixed(4));
        if (DOM.pendingRewards) DOM.pendingRewards.textContent = state.staking.pendingRewards.toFixed(4);
        if (DOM.stakedOpus) DOM.stakedOpus.textContent = state.staking.stakedOpus.toFixed(2);
    }

    /**
     * Add notification
     */
    function addNotification(message, type = 'info') {
        const id = Date.now();
        state.notifications.push({ id, message, type });
        renderNotifications();
        setTimeout(() => removeNotification(id), 5000);
    }

    /**
     * Remove notification
     */
    function removeNotification(id) {
        state.notifications = state.notifications.filter(n => n.id !== id);
        renderNotifications();
    }

    /**
     * Render notifications panel
     */
    function renderNotifications() {
        const container = DOM.notifications;
        if (!container) return;
        container.innerHTML = '';
        state.notifications.slice(-5).reverse().forEach(note => {
            const el = document.createElement('div');
            el.className = `notification ${note.type}`;
            el.textContent = note.message;
            container.appendChild(el);
        });
    }

    /**
     * Format currency
     */
    function formatCurrency(value, decimals = 2) {
        return new Intl.NumberFormat('en-US', {
            style: 'currency',
            currency: state.settings.currency,
            minimumFractionDigits: decimals,
            maximumFractionDigits: decimals
        }).format(value);
    }

    /**
     * Execute simulated swap
     */
    function executeSwap(fromToken, toToken, amount) {
        const rate = PAIR_RATES[`${fromToken}/${toToken}`] || PAIR_RATES[`${toToken}/${fromToken}`];
        if (!rate) {
            addNotification(`No exchange rate found for ${fromToken}/${toToken}`, 'error');
            return;
        }
        const fromBalance = state.wallet.tokens.find(t => t.symbol === fromToken);
        if (!fromBalance || fromBalance.balance < amount) {
            addNotification(`Insufficient ${fromToken} balance`, 'error');
            return;
        }
        const convertedAmount = amount * rate.price;
        fromBalance.balance -= amount;
        const toBalance = state.wallet.tokens.find(t => t.symbol === toToken);
        if (toBalance) {
            toBalance.balance += convertedAmount;
        }
        addNotification(`Swapped ${amount} ${fromToken} for ${convertedAmount.toFixed(4)} ${toToken}`, 'success');
        playAudioTone(440, 'sine', 0.1, 0.03);
        renderWallet();
    }

    /**
     * Render wallet balances
     */
    function renderWallet() {
        if (DOM.walletAddress) DOM.walletAddress.textContent = state.wallet.address || 'Not Connected';
        if (DOM.balanceEth) DOM.balanceEth.textContent = state.wallet.balanceEth.toFixed(4);
        if (DOM.balanceUsdt) DOM.balanceUsdt.textContent = state.wallet.balanceUsdt.toFixed(2);
        if (DOM.balanceBtc) DOM.balanceBtc.textContent = state.wallet.balanceBtc.toFixed(6);
        if (DOM.balanceSol) DOM.balanceSol.textContent = state.wallet.balanceSol.toFixed(4);
        if (DOM.networkName) DOM.networkName.textContent = state.wallet.networkName;
        if (DOM.chainId) DOM.chainId.textContent = state.wallet.chainId;

        const tokenList = DOM.tokenList;
        if (tokenList) {
            tokenList.innerHTML = '';
            state.wallet.tokens.forEach(token => {
                const row = document.createElement('div');
                row.className = 'token-row';
                row.innerHTML = `
                    <span class="token-symbol">${token.symbol}</span>
                    <span class="token-name">${token.name}</span>
                    <span class="token-balance">${token.balance.toFixed(token.decimals > 6 ? 4 : 6)}</span>
                    <span class="token-value">${formatCurrency(token.balance * token.price)}</span>
                `;
                tokenList.appendChild(row);
            });
        }
    }

    /**
     * Render portfolio allocation
     */
    function renderPortfolio() {
        const container = DOM.portfolio;
        if (!container) return;
        container.innerHTML = '';
        state.portfolio.forEach(item => {
            const row = document.createElement('div');
            row.className = 'portfolio-row';
            row.innerHTML = `
                <span class="portfolio-symbol">${item.symbol}</span>
                <span class="portfolio-name">${item.name}</span>
                <span class="portfolio-balance">${item.balance.toFixed(4)}</span>
                <span class="portfolio-value">${formatCurrency(item.value)}</span>
                <span class="portfolio-allocation">${item.allocation.toFixed(1)}%</span>
            `;
            container.appendChild(row);
        });
    }

    /**
     * Render transaction history
     */
    function renderTransactions() {
        const container = DOM.transactions;
        if (!container) return;
        container.innerHTML = '';
        state.transactions.slice().reverse().forEach(tx => {
            const row = document.createElement('div');
            row.className = `transaction-row ${tx.status.toLowerCase()}`;
            row.innerHTML = `
                <span class="tx-hash">${tx.hash}</span>
                <span class="tx-type">${tx.type}</span>
                <span class="tx-description">${tx.description}</span>
                <span class="tx-amount">${tx.amount}</span>
                <span class="tx-status">${tx.status}</span>
                <span class="tx-time">${new Date(tx.timestamp).toLocaleTimeString()}</span>
            `;
            container.appendChild(row);
        });
    }

    /**
     * Connect wallet simulation
     */
    function connectWallet() {
        if (state.wallet.connected) {
            state.wallet.connected = false;
            state.wallet.address = null;
            addNotification('Wallet disconnected', 'info');
        } else {
            state.wallet.connected = true;
            state.wallet.address = '0x' + Math.random().toString(16).substr(2, 40);
            addNotification('Wallet connected successfully', 'success');
            playAudioTone(523, 'sine', 0.15, 0.04);
        }
        renderWallet();
    }

    /**
     * Initialize DOM element references
     */
    function initDOMElements() {
        DOM = {
            walletAddress: document.getElementById('wallet-address'),
            balanceEth: document.getElementById('balance-eth'),
            balanceUsdt: document.getElementById('balance-usdt'),
            balanceBtc: document.getElementById('balance-btc'),
            balanceSol: document.getElementById('balance-sol'),
            networkName: document.getElementById('network-name'),
            chainId: document.getElementById('chain-id'),
            tokenList: document.getElementById('token-list'),
            gasCurrent: document.getElementById('gas-current'),
            gasSlow: document.getElementById('gas-slow'),
            gasStandard: document.getElementById('gas-standard'),
            gasFast: document.getElementById('gas-fast'),
            chartCanvas: document.getElementById('price-chart'),
            orderBookBids: document.getElementById('orderbook-bids'),
            orderBookAsks: document.getElementById('orderbook-asks'),
            pendingRewards: document.getElementById('pending-rewards'),
            stakedOpus: document.getElementById('staked-opus'),
            notifications: document.getElementById('notifications'),
            portfolio: document.getElementById('portfolio'),
            transactions: document.getElementById('transactions'),
            connectBtn: document.getElementById('connect-wallet-btn'),
            swapForm: document.getElementById('swap-form'),
            stakeBtn: document.getElementById('stake-btn'),
            claimBtn: document.getElementById('claim-btn')
        };
    }

    /**
     * Attach event listeners
     */
    function attachEventListeners() {
        if (DOM.connectBtn) {
            DOM.connectBtn.addEventListener('click', connectWallet);
        }
        if (DOM.swapForm) {
            DOM.swapForm.addEventListener('submit', function(e) {
                e.preventDefault();
                const fromToken = document.getElementById('swap-from').value;
                const toToken = document.getElementById('swap-to').value;
                const amount = parseFloat(document.getElementById('swap-amount').value);
                if (isNaN(amount) || amount <= 0) {
                    addNotification('Please enter a valid amount', 'error');
                    return;
                }
                executeSwap(fromToken, toToken, amount);
            });
        }
        if (DOM.stakeBtn) {
            DOM.stakeBtn.addEventListener('click', function() {
                const amount = parseFloat(prompt('Enter OPUS amount to stake:'));
                if (isNaN(amount) || amount <= 0) return;
                const opusToken = state.wallet.tokens.find(t => t.symbol === 'OPUS');
                if (!opusToken || opusToken.balance < amount) {
                    addNotification('Insufficient OPUS balance', 'error');
                    return;
                }
                opusToken.balance -= amount;
                state.staking.stakedOpus += amount;
                addNotification(`Staked ${amount} OPUS`, 'success');
                playAudioTone(329, 'square', 0.2, 0.05);
                renderWallet();
                updateStaking();
            });
        }
        if (DOM.claimBtn) {
            DOM.claimBtn.addEventListener('click', function() {
                if (state.staking.pendingRewards <= 0) {
                    addNotification('No rewards to claim', 'info');
                    return;
                }
                const claimed = state.staking.pendingRewards;
                state.staking.pendingRewards = 0;
                state.staking.lastClaimed = Date.now();
                const opusToken = state.wallet.tokens.find(t => t.symbol === 'OPUS');
                if (opusToken) opusToken.balance += claimed;
                addNotification(`Claimed ${claimed.toFixed(4)} OPUS rewards`, 'success');
                playAudioTone(659, 'sine', 0.3, 0.06);
                renderWallet();
                updateStaking();
            });
        }
    }

    /**
     * Start all interval-based updates
     */
    function startIntervals() {
        marketInterval = setInterval(() => {
            const variation = (Math.random() - 0.5) * 10;
            state.market.price += variation;
            state.market.change24h = (Math.random() * 10 - 5).toFixed(2);
            state.market.volume24h = Math.floor(Math.random() * 2000000000);
            state.market.high24h = state.market.price + Math.random() * 50;
            state.market.low24h = state.market.price - Math.random() * 50;
            state.market.chartData = generateChartData(50);
            renderChart();
            if (DOM.marketPrice) DOM.marketPrice.textContent = state.market.price.toFixed(2);
            if (DOM.marketChange) DOM.marketChange.textContent = `${state.market.change24h}%`;
            if (DOM.marketVolume) DOM.marketVolume.textContent = formatCurrency(state.market.volume24h, 0);
            if (DOM.marketHigh) DOM.marketHigh.textContent = state.market.high24h.toFixed(2);
            if (DOM.marketLow) DOM.marketLow.textContent = state.market.low24h.toFixed(2);
        }, state.settings.autoRefreshInterval);

        gasInterval = setInterval(updateGasPrice, 5000);

        orderBookInterval = setInterval(() => {
            state.orderBook = generateOrderBook();
            renderOrderBook();
        }, 3000);

        stakingInterval = setInterval(updateStaking, 10000);
    }

    /**
     * Initialize application
     */
    function init() {
        initDOMElements();
        attachEventListeners();
        state.market.chartData = generateChartData(50);
        state.orderBook = generateOrderBook();
        renderChart();
        renderOrderBook();
        renderWallet();
        renderPortfolio();
        renderTransactions();
        updateGasPrice();
        updateStaking();
        startIntervals();
        addNotification('Magnum Opus dashboard initialized', 'info');
    }

    // Auto-initialize when DOM is ready
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
    } else {
        init();
    }
})();