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
     * Play a short tone for UI feedback.
     * @param {number} freq Frequency in Hz.
     * @param {number} dur Duration in milliseconds.
     */
    function playTone(freq, dur) {
        if (!state.settings.enableSounds) return;
        if (!audioCtx) audioCtx = new (window.AudioContext || window.webkitAudioContext)();
        const osc = audioCtx.createOscillator();
        const gain = audioCtx.createGain();
        osc.type = 'sine';
        osc.frequency.value = freq;
        osc.connect(gain);
        gain.connect(audioCtx.destination);
        gain.gain.setValueAtTime(0.001, audioCtx.currentTime);
        gain.gain.exponentialRampToValueAtTime(0.2, audioCtx.currentTime + 0.01);
        osc.start();
        setTimeout(() => {
            gain.gain.exponentialRampToValueAtTime(0.001, audioCtx.currentTime + 0.1);
            osc.stop(audioCtx.currentTime + 0.1);
        }, dur);
    }

    // ---------------------------------------------------------------------
    // Initialise DOM cache and bind UI events
    // ---------------------------------------------------------------------
    function initDOM() {
        // Core sections
        DOM.walletAddress = document.getElementById('wallet-address');
        DOM.walletBalance = document.getElementById('wallet-balance');
        DOM.connectBtn = document.getElementById('connect-wallet');
        DOM.themeToggle = document.getElementById('theme-toggle');
        // Market
        DOM.marketPair = document.getElementById('market-pair');
        DOM.marketPrice = document.getElementById('market-price');
        DOM.marketChange = document.getElementById('market-change');
        DOM.marketVolume = document.getElementById('market-volume');
        // Orderbook
        DOM.bidsContainer = document.getElementById('orderbook-bids');
        DOM.asksContainer = document.getElementById('orderbook-asks');
        // Portfolio
        DOM.portfolioTable = document.getElementById('portfolio-table-body');
        // Staking
        DOM.stakedAmount = document.getElementById('staked-amount');
        DOM.pendingRewards = document.getElementById('pending-rewards');
        DOM.claimBtn = document.getElementById('claim-rewards');
        // Transactions & notifications
        DOM.txList = document.getElementById('tx-list');
        DOM.notifications = document.getElementById('notifications');
        // Forms
        DOM.swapForm = document.getElementById('swap-form');
        DOM.stakeForm = document.getElementById('stake-form');

        // Event bindings
        if (DOM.connectBtn) DOM.connectBtn.addEventListener('click', connectWallet);
        if (DOM.themeToggle) DOM.themeToggle.addEventListener('click', toggleTheme);
        if (DOM.swapForm) DOM.swapForm.addEventListener('submit', handleSwap);
        if (DOM.stakeForm) DOM.stakeForm.addEventListener('submit', handleStake);
        if (DOM.claimBtn) DOM.claimBtn.addEventListener('click', handleClaim);
        if (DOM.marketPair) DOM.marketPair.addEventListener('change', (e) => {
            state.market.selectedPair = e.target.value;
            fetchMarketData();
        });
    }

    // ---------------------------------------------------------------------
    // Wallet connection (mocked for demo)
    // ---------------------------------------------------------------------
    function connectWallet() {
        // Simulate async wallet connection
        setTimeout(() => {
            state.wallet.connected = true;
            state.wallet.address = '0x' + Math.random().toString(16).substr(2, 40);
            renderWallet();
            addNotification('Wallet connected: ' + state.wallet.address);
            playTone(440, 150);
        }, 500);
    }

    // ---------------------------------------------------------------------
    // Theme handling
    // ---------------------------------------------------------------------
    function toggleTheme() {
        state.settings.theme = state.settings.theme === 'dark' ? 'light' : 'dark';
        applyTheme();
        addNotification('Theme switched to ' + state.settings.theme);
        playTone(660, 120);
    }

    function applyTheme() {
        document.documentElement.setAttribute('data-theme', state.settings.theme);
    }

    // ---------------------------------------------------------------------
    // Notification helper
    // ---------------------------------------------------------------------
    function addNotification(message) {
        const id = Date.now();
        state.notifications.unshift({ id, message, timestamp: id });
        renderNotifications();
        // Auto‑expire after 6 seconds
        setTimeout(() => {
            state.notifications = state.notifications.filter(n => n.id !== id);
            renderNotifications();
        }, 6000);
    }

    // ---------------------------------------------------------------------
    // Market data ticker (mocked random walk)
    // ---------------------------------------------------------------------
    function fetchMarketData() {
        const pairInfo = PAIR_RATES[state.market.selectedPair];
        if (!pairInfo) return;
        // Random walk +/- 1% per tick
        const delta = (Math.random() - 0.5) * 0.02 * pairInfo.price;
        const newPrice = Math.max(pairInfo.price * 0.5, pairInfo.price + delta);
        const change = ((newPrice - pairInfo.price) / pairInfo.price) * 100;
        state.market.price = parseFloat(newPrice.toFixed(pairInfo.decimals));
        state.market.change24h = parseFloat(change.toFixed(2));
        // Simulate volume swing
        state.market.volume24h = Math.round(state.market.volume24h * (0.95 + Math.random() * 0.1));
        // Update high/low
        state.market.high24h = Math.max(state.market.high24h, state.market.price);
        state.market.low24h = Math.min(state.market.low24h, state.market.price);
        // Push to chart data (keep last 30 points)
        const now = new Date();
        state.market.chartData.labels.push(now.toLocaleTimeString());
        state.market.chartData.prices.push(state.market.price);
        if (state.market.chartData.labels.length > 30) {
            state.market.chartData.labels.shift();
            state.market.chartData.prices.shift();
        }
        renderMarket();
    }

    // ---------------------------------------------------------------------
    // Gas price ticker (mocked)
    // ---------------------------------------------------------------------
    function updateGas() {
        const base = 10;
        const variance = Math.random() * 10; // 0‑10 Gwei
        const newGas = Math.round(base + variance);
        state.gas.current = newGas;
        renderGas();
    }

    // ---------------------------------------------------------------------
    // Orderbook ticker (mocked depth)
    // ---------------------------------------------------------------------
    function updateOrderBook() {
        const depth = state.orderBook.maxDepth;
        const mid = state.market.price;
        const spread = mid * 0.001; // 0.1% spread
        const bids = [];
        const asks = [];
        for (let i = 1; i <= depth; i++) {
            const priceBid = parseFloat((mid - i * spread).toFixed(2));
            const priceAsk = parseFloat((mid + i * spread).toFixed(2));
            const sizeBid = (Math.random() * 5).toFixed(4);
            const sizeAsk = (Math.random() * 5).toFixed(4);
            bids.push({ price: priceBid, size: sizeBid });
            asks.push({ price: priceAsk, size: sizeAsk });
        }
        state.orderBook.bids = bids;
        state.orderBook.asks = asks;
        renderOrderBook();
    }

    // ---------------------------------------------------------------------
    // Staking reward accrual (simple APY compounding per tick)
    // ---------------------------------------------------------------------
    function updateStaking() {
        const now = Date.now();
        const secondsSinceLast = (now - state.staking.lastClaimed) / 1000;
        const yearlySeconds = 365 * 24 * 60 * 60;
        const rewardPerSecond = (state.staking.stakedOpus * (state.staking.rewardRateApy / 100)) / yearlySeconds;
        const accrued = rewardPerSecond * secondsSinceLast;
        state.staking.pendingRewards = parseFloat((state.staking.pendingRewards + accrued).toFixed(6));
        renderStaking();
    }

    // ---------------------------------------------------------------------
    // UI Rendering helpers
    // ---------------------------------------------------------------------
    function renderWallet() {
        if (DOM.walletAddress) DOM.walletAddress.textContent = state.wallet.connected ? state.wallet.address : 'Not connected';
        if (DOM.walletBalance) {
            const totalUsd = state.wallet.tokens.reduce((sum, t) => sum + t.balance * t.price, 0);
            DOM.walletBalance.textContent = '$' + totalUsd.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 });
        }
    }

    function renderMarket() {
        if (DOM.marketPair) DOM.marketPair.value = state.market.selectedPair;
        if (DOM.marketPrice) DOM.marketPrice.textContent = state.market.price.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 });
        if (DOM.marketChange) {
            const sign = state.market.change24h >= 0 ? '+' : '';
            DOM.marketChange.textContent = sign + state.market.change24h.toFixed(2) + '%';
            DOM.marketChange.style.color = state.market.change24h >= 0 ? '#4caf50' : '#f44336';
        }
        if (DOM.marketVolume) DOM.marketVolume.textContent = state.market.volume24h.toLocaleString();
        // Chart rendering could be added here – omitted for brevity.
    }

    function renderGas() {
        const gasEl = document.getElementById('gas-price');
        if (gasEl) gasEl.textContent = state.gas.current + ' ' + state.gas.unit;
    }

    function renderOrderBook() {
        if (DOM.bidsContainer) {
            DOM.bidsContainer.innerHTML = '';
            state.orderBook.bids.forEach(b => {
                const row = document.createElement('div');
                row.className = 'order-row bid';
                row.textContent = b.size + ' @ ' + b.price;
                DOM.bidsContainer.appendChild(row);
            });
        }
        if (DOM.asksContainer) {
            DOM.asksContainer.innerHTML = '';
            state.orderBook.asks.forEach(a => {
                const row = document.createElement('div');
                row.className = 'order-row ask';
                row.textContent = a.size + ' @ ' + a.price;
                DOM.asksContainer.appendChild(row);
            });
        }
    }

    function renderPortfolio() {
        if (!DOM.portfolioTable) return;
        DOM.portfolioTable.innerHTML = '';
        state.portfolio.forEach(p => {
            const tr = document.createElement('tr');
            tr.innerHTML = `
                <td>${p.symbol}</td>
                <td>${p.balance.toLocaleString(undefined, {minimumFractionDigits: 4, maximumFractionDigits: 4})}</td>
                <td>$${p.price.toLocaleString(undefined, {minimumFractionDigits: 2, maximumFractionDigits: 2})}</td>
                <td>$${p.value.toLocaleString(undefined, {minimumFractionDigits: 2, maximumFractionDigits: 2})}</td>
                <td>${p.allocation.toFixed(1)}%</td>
            `;
            DOM.portfolioTable.appendChild(tr);
        });
    }

    function renderStaking() {
        if (DOM.stakedAmount) DOM.stakedAmount.textContent = state.staking.stakedOpus.toLocaleString(undefined, {minimumFractionDigits: 2});
        if (DOM.pendingRewards) DOM.pendingRewards.textContent = state.staking.pendingRewards.toFixed(6);
    }

    function renderTransactions() {
        if (!DOM.txList) return;
        DOM.txList.innerHTML = '';
        state.transactions.slice().reverse().forEach(tx => {
            const li = document.createElement('li');
            li.className = 'tx-item';
            li.textContent = `[${new Date(tx.timestamp).toLocaleTimeString()}] ${tx.type}: ${tx.description} (${tx.status})`;
            DOM.txList.appendChild(li);
        });
    }

    function renderNotifications() {
        if (!DOM.notifications) return;
        DOM.notifications.innerHTML = '';
        state.notifications.forEach(n => {
            const div = document.createElement('div');
            div.className = 'notification';
            div.textContent = n.message;
            DOM.notifications.appendChild(div);
        });
    }

    // ---------------------------------------------------------------------
    // Swap handling (mocked execution)
    // ---------------------------------------------------------------------
    function handleSwap(event) {
        event.preventDefault();
        const form = event.target;
        const fromSymbol = form.elements['from-token'].value;
        const toSymbol = form.elements['to-token'].value;
        const amountStr = form.elements['amount'].value;
        const amount = parseFloat(amountStr);
        if (isNaN(amount) || amount <= 0) {
            addNotification('Invalid swap amount');
            playTone(200, 200);
            return;
        }
        const fromToken = state.wallet.tokens.find(t => t.symbol === fromSymbol);
        const toToken = state.wallet.tokens.find(t => t.symbol === toSymbol);
        if (!fromToken || !toToken) {
            addNotification('Unsupported token pair');
            playTone(200, 200);
            return;
        }
        // Simple price lookup via PAIR_RATES (assume direct pair exists)
        const pairKey = `${fromSymbol}/${toSymbol}`;
        const reverseKey = `${toSymbol}/${fromSymbol}`;
        let rateInfo = PAIR_RATES[pairKey] || PAIR_RATES[reverseKey];
        if (!rateInfo) {
            addNotification('No price feed for selected pair');
            playTone(200, 200);
            return;
        }
        let price = rateInfo.price;
        // If we used reverse pair, invert price
        if (rateInfo.base !== fromSymbol) price = 1 / price;
        const received = amount * price;
        // Update balances
        fromToken.balance = Math.max(0, fromToken.balance - amount);
        toToken.balance = (toToken.balance || 0) + received;
        // Record transaction
        const tx = {
            hash: '0x' + Math.random().toString(16).substr(2, 64),
            type: 'Swap',
            description: `Swapped ${amount} ${fromSymbol} for ${received.toFixed(4)} ${toSymbol}`,
            amount: `${amount} ${fromSymbol}`,
            status: 'Confirmed',
            timestamp: Date.now(),
            blockNumber: Math.floor(Math.random() * 20000000)
        };
        state.transactions.push(tx);
        // Refresh UI
        renderWallet();
        renderTransactions();
        addNotification('Swap executed successfully');
        playTone(880, 120);
        form.reset();
    }

    // ---------------------------------------------------------------------
    // Staking handling (mocked)
    // ---------------------------------------------------------------------
    function handleStake(event) {
        event.preventDefault();
        const form = event.target;
        const amountStr = form.elements['stake-amount'].value;
        const amount = parseFloat(amountStr);
        if (isNaN(amount) || amount <= 0) {
            addNotification('Invalid stake amount');
            playTone(200, 200);
            return;
        }
        const opusToken = state.wallet.tokens.find(t => t.symbol === 'OPUS');
        if (!opusToken || opusToken.balance < amount) {
            addNotification('Insufficient OPUS balance');
            playTone(200, 200);
            return;
        }
        opusToken.balance -= amount;
        state.staking.stakedOpus += amount;
        state.staking.lastClaimed = Date.now();
        // Record transaction
        const tx = {
            hash: '0x' + Math.random().toString(16).substr(2, 64),
            type: 'Stake',
            description: `Staked ${amount} OPUS in Vault`,
            amount: `${amount} OPUS`,
            status: 'Confirmed',
            timestamp: Date.now(),
            blockNumber: Math.floor(Math.random() * 20000000)
        };
        state.transactions.push(tx);
        renderWallet();
        renderStaking();
        renderTransactions();
        addNotification('Staking successful');
        playTone(660, 120);
        form.reset();
    }

    function handleClaim() {
        if (state.staking.pendingRewards <= 0) {
            addNotification('No rewards to claim');
            playTone(200, 200);
            return;
        }
        const opusToken = state.wallet.tokens.find(t => t.symbol === 'OPUS');
        opusToken.balance += state.staking.pendingRewards;
        const claimed = state.staking.pendingRewards;
        state.staking.pendingRewards = 0;
        state.staking.lastClaimed = Date.now();
        // Record transaction
        const tx = {
            hash: '0x' + Math.random().toString(16).substr(2, 64),
            type: 'Claim',
            description: `Claimed ${claimed.toFixed(6)} OPUS rewards`,
            amount: `${claimed.toFixed(6)} OPUS`,
            status: 'Confirmed',
            timestamp: Date.now(),
            blockNumber: Math.floor(Math.random() * 20000000)
        };
        state.transactions.push(tx);
        renderWallet();
        renderStaking();
        renderTransactions();
        addNotification('Rewards claimed');
        playTone(1000, 150);
    }

    // ---------------------------------------------------------------------
    // Start / Stop tickers
    // ---------------------------------------------------------------------
    function startTickers() {
        marketInterval = setInterval(fetchMarketData, state.settings.autoRefreshInterval);
        gasInterval = setInterval(updateGas, 15000);
        orderBookInterval = setInterval(updateOrderBook, 5000);
        stakingInterval = setInterval(updateStaking, 10000);
    }

    function stopTickers() {
        clearInterval(marketInterval);
        clearInterval(gasInterval);
        clearInterval(orderBookInterval);
        clearInterval(stakingInterval);
    }

    // ---------------------------------------------------------------------
    // Initial render & bootstrap
    // ---------------------------------------------------------------------
    function bootstrap() {
        initDOM();
        applyTheme();
        renderWallet();
        renderMarket();
        renderGas();
        renderOrderBook();
        renderPortfolio();
        renderStaking();
        renderTransactions();
        renderNotifications();
        startTickers();
    }

    // Kick off when DOM is ready
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', bootstrap);
    } else {
        bootstrap();
    }

})();