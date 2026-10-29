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
    let DOM = {};

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
     * Play a short tone for UI feedback.
     * @param {number} frequency Hz
     * @param {number} duration ms
     */
    function playTone(frequency, duration) {
        if (!state.settings.enableSounds) return;
        if (!audioCtx) audioCtx = new (window.AudioContext || window.webkitAudioContext)();
        const oscillator = audioCtx.createOscillator();
        const gain = audioCtx.createGain();
        oscillator.type = 'sine';
        oscillator.frequency.setValueAtTime(frequency, audioCtx.currentTime);
        gain.gain.setValueAtTime(0.001, audioCtx.currentTime);
        oscillator.connect(gain).connect(audioCtx.destination);
        oscillator.start();
        gain.gain.exponentialRampToValueAtTime(0.2, audioCtx.currentTime + 0.01);
        gain.gain.exponentialRampToValueAtTime(0.001, audioCtx.currentTime + duration / 1000);
        oscillator.stop(audioCtx.currentTime + duration / 1000 + 0.02);
    }

    // ---------------------------------------------------------------------
    // UI Helpers
    // ---------------------------------------------------------------------
    function formatNumber(num, decimals = 2) {
        return Number(num).toLocaleString(undefined, { minimumFractionDigits: decimals, maximumFractionDigits: decimals });
    }

    function addNotification(message, type = 'info') {
        const timestamp = new Date().toISOString();
        state.notifications.unshift({ message, type, timestamp });
        if (DOM.notificationList) {
            const li = document.createElement('li');
            li.className = `notification ${type}`;
            li.textContent = `[${new Date(timestamp).toLocaleTimeString()}] ${message}`;
            DOM.notificationList.prepend(li);
        }
        playTone(440, 100);
    }

    // ---------------------------------------------------------------------
    // DOM Initialization
    // ---------------------------------------------------------------------
    function initDOM() {
        DOM = {
            connectBtn: document.getElementById('connect-wallet'),
            addressSpan: document.getElementById('wallet-address'),
            balanceList: document.getElementById('wallet-balances'),
            marketPrice: document.getElementById('market-price'),
            marketChange: document.getElementById('market-change'),
            marketVolume: document.getElementById('market-volume'),
            orderBookBids: document.getElementById('orderbook-bids'),
            orderBookAsks: document.getElementById('orderbook-asks'),
            swapForm: document.getElementById('swap-form'),
            stakeForm: document.getElementById('stake-form'),
            txList: document.getElementById('tx-list'),
            portfolioTable: document.getElementById('portfolio-table'),
            stakingInfo: document.getElementById('staking-info'),
            notificationList: document.getElementById('notification-list'),
            themeToggle: document.getElementById('theme-toggle')
        };

        // Attach event listeners
        if (DOM.connectBtn) DOM.connectBtn.addEventListener('click', connectWallet);
        if (DOM.swapForm) DOM.swapForm.addEventListener('submit', handleSwap);
        if (DOM.stakeForm) DOM.stakeForm.addEventListener('submit', handleStake);
        if (DOM.themeToggle) DOM.themeToggle.addEventListener('click', toggleTheme);
    }

    // ---------------------------------------------------------------------
    // Wallet Interaction (mocked for demo)
    // ---------------------------------------------------------------------
    function connectWallet() {
        // In a real app, this would invoke window.ethereum.request({ method: 'eth_requestAccounts' })
        state.wallet.connected = true;
        state.wallet.address = '0x' + Math.random().toString(16).substr(2, 40);
        updateWalletUI();
        addNotification('Wallet connected: ' + state.wallet.address, 'success');
        playTone(660, 150);
    }

    function updateWalletUI() {
        if (!DOM.addressSpan) return;
        DOM.addressSpan.textContent = state.wallet.connected ? state.wallet.address : 'Not Connected';
        // Update token balances list
        if (DOM.balanceList) {
            DOM.balanceList.innerHTML = '';
            state.wallet.tokens.forEach(tok => {
                const li = document.createElement('li');
                li.textContent = `${tok.symbol}: ${formatNumber(tok.balance, 4)} (${formatNumber(tok.price)} ${state.settings.currency})`;
                DOM.balanceList.appendChild(li);
            });
        }
    }

    // ---------------------------------------------------------------------
    // Market Data Simulation
    // ---------------------------------------------------------------------
    function updateMarketData() {
        const pair = PAIR_RATES[state.market.selectedPair];
        // Simulate price drift within ±1%
        const drift = (Math.random() - 0.5) * 0.02; // ±1%
        const newPrice = pair.price * (1 + drift);
        state.market.price = parseFloat(newPrice.toFixed(pair.decimals));
        // Simulate 24h change, volume, high/low
        state.market.change24h = parseFloat(((Math.random() - 0.5) * 10).toFixed(2));
        state.market.volume24h = Math.round(state.market.volume24h * (0.95 + Math.random() * 0.1));
        state.market.high24h = Math.max(state.market.high24h, state.market.price);
        state.market.low24h = Math.min(state.market.low24h, state.market.price);
        // Mock chart data (push last 30 points)
        const now = new Date();
        state.market.chartData.labels.push(now.toLocaleTimeString());
        state.market.chartData.prices.push(state.market.price);
        if (state.market.chartData.labels.length > 30) {
            state.market.chartData.labels.shift();
            state.market.chartData.prices.shift();
        }
        renderMarketUI();
    }

    function renderMarketUI() {
        if (DOM.marketPrice) DOM.marketPrice.textContent = formatNumber(state.market.price, PAIR_RATES[state.market.selectedPair].decimals);
        if (DOM.marketChange) {
            const change = state.market.change24h;
            DOM.marketChange.textContent = (change >= 0 ? '+' : '') + formatNumber(change, 2) + '%';
            DOM.marketChange.style.color = change >= 0 ? '#22c55e' : '#ef4444';
        }
        if (DOM.marketVolume) DOM.marketVolume.textContent = formatNumber(state.market.volume24h, 0);
        // Chart rendering is omitted for brevity – a canvas library would consume state.market.chartData
    }

    // ---------------------------------------------------------------------
    // Gas Price Simulation
    // ---------------------------------------------------------------------
    function updateGasPrices() {
        const base = 10; // base Gwei
        state.gas.slow = Math.round(base * (0.8 + Math.random() * 0.4));
        state.gas.standard = Math.round(base * (1 + Math.random() * 0.5));
        state.gas.fast = Math.round(base * (1.5 + Math.random() * 0.5));
        state.gas.current = state.gas.standard;
        // UI update – assume elements exist with IDs gas-slow, gas-standard, gas-fast
        ['slow', 'standard', 'fast'].forEach(level => {
            const el = document.getElementById(`gas-${level}`);
            if (el) el.textContent = state.gas[level] + ' ' + state.gas.unit;
        });
    }

    // ---------------------------------------------------------------------
    // Order Book Simulation
    // ---------------------------------------------------------------------
    function updateOrderBook() {
        const depth = state.orderBook.maxDepth;
        const mid = state.market.price;
        const spread = mid * 0.001; // 0.1% spread
        state.orderBook.bids = [];
        state.orderBook.asks = [];
        for (let i = 1; i <= depth; i++) {
            const priceBid = parseFloat((mid - spread * i).toFixed(2));
            const priceAsk = parseFloat((mid + spread * i).toFixed(2));
            const sizeBid = (Math.random() * 5).toFixed(4);
            const sizeAsk = (Math.random() * 5).toFixed(4);
            state.orderBook.bids.push({ price: priceBid, size: sizeBid });
            state.orderBook.asks.push({ price: priceAsk, size: sizeAsk });
        }
        renderOrderBook();
    }

    function renderOrderBook() {
        if (DOM.orderBookBids) {
            DOM.orderBookBids.innerHTML = '';
            state.orderBook.bids.forEach(entry => {
                const li = document.createElement('li');
                li.textContent = `${formatNumber(entry.size, 4)} @ ${formatNumber(entry.price, 2)}`;
                DOM.orderBookBids.appendChild(li);
            });
        }
        if (DOM.orderBookAsks) {
            DOM.orderBookAsks.innerHTML = '';
            state.orderBook.asks.forEach(entry => {
                const li = document.createElement('li');
                li.textContent = `${formatNumber(entry.size, 4)} @ ${formatNumber(entry.price, 2)}`;
                DOM.orderBookAsks.appendChild(li);
            });
        }
    }

    // ---------------------------------------------------------------------
    // Staking Rewards Simulation
    // ---------------------------------------------------------------------
    function updateStaking() {
        const now = Date.now();
        const elapsedSec = (now - state.staking.lastClaimed) / 1000;
        const rewardPerSec = (state.staking.stakedOpus * state.staking.rewardRateApy) / (365 * 24 * 3600 * 100);
        const accrued = rewardPerSec * elapsedSec;
        state.staking.pendingRewards = parseFloat((state.staking.pendingRewards + accrued).toFixed(4));
        renderStaking();
    }

    function renderStaking() {
        if (DOM.stakingInfo) {
            DOM.stakingInfo.innerHTML = `Staked: ${formatNumber(state.staking.stakedOpus, 2)} OPUS<br>` +
                `APY: ${formatNumber(state.staking.rewardRateApy, 2)}%<br>` +
                `Pending Rewards: ${formatNumber(state.staking.pendingRewards, 4)} OPUS`;
        }
    }

    // ---------------------------------------------------------------------
    // Transaction Log UI
    // ---------------------------------------------------------------------
    function renderTransactions() {
        if (!DOM.txList) return;
        DOM.txList.innerHTML = '';
        state.transactions.slice().reverse().forEach(tx => {
            const li = document.createElement('li');
            li.className = `tx ${tx.status.toLowerCase()}`;
            const date = new Date(tx.timestamp).toLocaleString();
            li.textContent = `[${date}] ${tx.type}: ${tx.description} (${tx.status})`;
            DOM.txList.appendChild(li);
        });
    }

    // ---------------------------------------------------------------------
    // Portfolio UI
    // ---------------------------------------------------------------------
    function renderPortfolio() {
        if (!DOM.portfolioTable) return;
        const tbody = DOM.portfolioTable.querySelector('tbody');
        if (!tbody) return;
        tbody.innerHTML = '';
        state.portfolio.forEach(item => {
            const tr = document.createElement('tr');
            tr.innerHTML = `<td>${item.symbol}</td>` +
                `<td>${formatNumber(item.balance, 4)}</td>` +
                `<td>${formatNumber(item.price, 2)}</td>` +
                `<td>${formatNumber(item.value, 2)}</td>` +
                `<td>${formatNumber(item.allocation, 1)}%</td>`;
            tbody.appendChild(tr);
        });
    }

    // ---------------------------------------------------------------------
    // Swap Handler (mock implementation)
    // ---------------------------------------------------------------------
    function handleSwap(event) {
        event.preventDefault();
        const form = event.target;
        const fromToken = form.elements['from-token'].value;
        const toToken = form.elements['to-token'].value;
        const amountStr = form.elements['amount'].value;
        const amount = parseFloat(amountStr);
        if (isNaN(amount) || amount <= 0) {
            addNotification('Invalid swap amount', 'error');
            return;
        }
        const fromInfo = state.wallet.tokens.find(t => t.symbol === fromToken);
        const toInfo = state.wallet.tokens.find(t => t.symbol === toToken);
        if (!fromInfo || !toInfo) {
            addNotification('Unsupported token pair', 'error');
            return;
        }
        if (fromInfo.balance < amount) {
            addNotification('Insufficient balance for swap', 'error');
            return;
        }
        // Simple constant product mock: amountOut = amount * priceRatio
        const priceRatio = fromInfo.price / toInfo.price;
        const amountOut = amount * priceRatio * (1 - state.settings.slippageTolerance / 100);
        // Update balances
        fromInfo.balance = parseFloat((fromInfo.balance - amount).toFixed(8));
        toInfo.balance = parseFloat((toInfo.balance + amountOut).toFixed(8));
        // Log transaction
        const tx = {
            hash: '0x' + Math.random().toString(16).substr(2, 64),
            type: 'Swap',
            description: `Swapped ${formatNumber(amount, 4)} ${fromToken} for ${formatNumber(amountOut, 4)} ${toToken}`,
            amount: `${formatNumber(amount, 4)} ${fromToken}`,
            status: 'Pending',
            timestamp: Date.now(),
            blockNumber: null
        };
        state.transactions.push(tx);
        renderTransactions();
        updateWalletUI();
        addNotification('Swap submitted', 'info');
        // Simulate confirmation after 2 seconds
        setTimeout(() => {
            tx.status = 'Confirmed';
            tx.blockNumber = Math.floor(Math.random() * 20000000) + 1000000;
            renderTransactions();
            addNotification('Swap confirmed', 'success');
            playTone(880, 120);
        }, 2000);
    }

    // ---------------------------------------------------------------------
    // Stake Handler (mock implementation)
    // ---------------------------------------------------------------------
    function handleStake(event) {
        event.preventDefault();
        const form = event.target;
        const amountStr = form.elements['amount'].value;
        const amount = parseFloat(amountStr);
        if (isNaN(amount) || amount <= 0) {
            addNotification('Invalid stake amount', 'error');
            return;
        }
        const opus = state.wallet.tokens.find(t => t.symbol === 'OPUS');
        if (!opus || opus.balance < amount) {
            addNotification('Insufficient OPUS balance', 'error');
            return;
        }
        // Update balances and staking state
        opus.balance = parseFloat((opus.balance - amount).toFixed(8));
        state.staking.stakedOpus = parseFloat((state.staking.stakedOpus + amount).toFixed(8));
        state.staking.lastClaimed = Date.now();
        state.staking.pendingRewards = 0;
        // Log transaction
        const tx = {
            hash: '0x' + Math.random().toString(16).substr(2, 64),
            type: 'Stake',
            description: `Staked ${formatNumber(amount, 4)} OPUS`,
            amount: `${formatNumber(amount, 4)} OPUS`,
            status: 'Pending',
            timestamp: Date.now(),
            blockNumber: null
        };
        state.transactions.push(tx);
        renderTransactions();
        updateWalletUI();
        renderStaking();
        addNotification('Stake submitted', 'info');
        setTimeout(() => {
            tx.status = 'Confirmed';
            tx.blockNumber = Math.floor(Math.random() * 20000000) + 1000000;
            renderTransactions();
            addNotification('Stake confirmed', 'success');
            playTone(660, 120);
        }, 2000);
    }

    // ---------------------------------------------------------------------
    // Theme Toggle
    // ---------------------------------------------------------------------
    function toggleTheme() {
        const root = document.documentElement;
        if (state.settings.theme === 'dark') {
            state.settings.theme = 'light';
            root.classList.remove('theme-dark');
            root.classList.add('theme-light');
        } else {
            state.settings.theme = 'dark';
            root.classList.remove('theme-light');
            root.classList.add('theme-dark');
        }
        addNotification('Theme switched to ' + state.settings.theme, 'info');
    }

    // ---------------------------------------------------------------------
    // Engine Control – start/stop intervals
    // ---------------------------------------------------------------------
    function startEngine() {
        // Market ticker
        updateMarketData();
        marketInterval = setInterval(updateMarketData, state.settings.autoRefreshInterval);
        // Gas ticker – slower
        updateGasPrices();
        gasInterval = setInterval(updateGasPrices, 15000);
        // Order book ticker
        updateOrderBook();
        orderBookInterval = setInterval(updateOrderBook, 5000);
        // Staking rewards ticker
        updateStaking();
        stakingInterval = setInterval(updateStaking, 10000);
        // Initial UI render
        renderMarketUI();
        renderOrderBook();
        renderStaking();
        renderTransactions();
        renderPortfolio();
        updateWalletUI();
    }

    function stopEngine() {
        clearInterval(marketInterval);
        clearInterval(gasInterval);
        clearInterval(orderBookInterval);
        clearInterval(stakingInterval);
    }

    // ---------------------------------------------------------------------
    // Graceful shutdown handling (e.g., when user navigates away)
    // ---------------------------------------------------------------------
    window.addEventListener('beforeunload', stopEngine);

    // ---------------------------------------------------------------------
    // Bootstrap
    // ---------------------------------------------------------------------
    document.addEventListener('DOMContentLoaded', () => {
        initDOM();
        startEngine();
        // If the wallet is already injected (e.g., MetaMask), auto‑connect could be attempted here.
    });

})();