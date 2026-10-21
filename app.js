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
            // Ignore audio context errors
        }
    }

    function playSound(effect) {
        switch (effect) {
            case 'click':
                playAudioTone(800, 'sine', 0.05, 0.02);
                break;
            case 'success':
                playAudioTone(523.25, 'triangle', 0.1, 0.05); // C5
                setTimeout(() => playAudioTone(659.25, 'triangle', 0.15, 0.05), 100); // E5
                setTimeout(() => playAudioTone(783.99, 'triangle', 0.25, 0.05), 200); // G5
                break;
            case 'error':
                playAudioTone(220, 'sawtooth', 0.2, 0.08);
                break;
            case 'trade':
                playAudioTone(1050, 'sine', 0.08, 0.03);
                break;
        }
    }

    /**
     * Initialization
     */
    function init() {
        loadPersistedSettings();
        initDOM();
        initChartData();
        setupEventListeners();
        renderChartCanvas();
        populateOrderBook();
        renderOrderBook();
        renderPortfolio();
        renderTransactions();
        updateUI();
        startSimulationEngines();
        setupWeb3Listeners();

        addNotification('System Initialized', 'Magnum Opus Web3 & DeFi Nexus Engine is live.', 'info');
    }

    function loadPersistedSettings() {
        try {
            const saved = localStorage.getItem('magnum_opus_settings');
            if (saved) {
                Object.assign(state.settings, JSON.parse(saved));
            }
        } catch (e) {
            console.warn('Could not read settings from localStorage', e);
        }
    }

    function saveSettingsToStorage() {
        try {
            localStorage.setItem('magnum_opus_settings', JSON.stringify(state.settings));
        } catch (e) {
            console.warn('Could not persist settings', e);
        }
    }

    function initDOM() {
        DOM = {
            connectBtn: document.getElementById('connect-wallet-btn'),
            walletAddress: document.getElementById('wallet-address-display'),
            walletBalance: document.getElementById('wallet-balance-display'),
            gasPrice: document.getElementById('gas-price-display'),
            pairSelect: document.getElementById('pair-select'),
            currentPrice: document.getElementById('current-price-display'),
            priceChange: document.getElementById('price-change-display'),
            orderBookAsks: document.getElementById('orderbook-asks'),
            orderBookBids: document.getElementById('orderbook-bids'),
            portfolioTable: document.getElementById('portfolio-table-body'),
            txTable: document.getElementById('tx-table-body'),
            swapPayInput: document.getElementById('swap-pay-amount'),
            swapReceiveInput: document.getElementById('swap-receive-amount'),
            swapPaySelect: document.getElementById('swap-pay-token'),
            swapReceiveSelect: document.getElementById('swap-receive-token'),
            swapExecuteBtn: document.getElementById('swap-execute-btn'),
            swapSlippageInput: document.getElementById('swap-slippage-input'),
            stakedAmountDisplay: document.getElementById('staked-amount-display'),
            pendingRewardsDisplay: document.getElementById('pending-rewards-display'),
            stakeInput: document.getElementById('stake-input-amount'),
            stakeBtn: document.getElementById('stake-btn'),
            unstakeBtn: document.getElementById('unstake-btn'),
            claimRewardsBtn: document.getElementById('claim-rewards-btn'),
            notificationsContainer: document.getElementById('notifications-container'),
            chartCanvas: document.getElementById('market-chart-canvas')
        };
    }

    /**
     * Canvas Interactive Chart Generator
     */
    function initChartData() {
        const basePrice = state.market.price;
        state.market.chartData.labels = [];
        state.market.chartData.prices = [];
        state.market.chartData.candles = [];

        let current = basePrice * 0.95;
        const now = Date.now();
        const interval = 300000; // 5 min candles

        for (let i = 40; i >= 0; i--) {
            const time = new Date(now - i * interval);
            const timeStr = time.getHours().toString().padStart(2, '0') + ':' + time.getMinutes().toString().padStart(2, '0');
            const delta = (Math.random() - 0.48) * (basePrice * 0.012);
            const open = current;
            const close = open + delta;
            const high = Math.max(open, close) + Math.random() * (basePrice * 0.005);
            const low = Math.min(open, close) - Math.random() * (basePrice * 0.005);
            current = close;

            state.market.chartData.labels.push(timeStr);
            state.market.chartData.prices.push(close);
            state.market.chartData.candles.push({ time: timeStr, open, high, low, close });
        }
        state.market.price = current;
    }

    function renderChartCanvas() {
        const canvas = DOM.chartCanvas;
        if (!canvas) return;
        const ctx = canvas.getContext('2d');
        if (!ctx) return;

        // Auto handle high DPI crisp rendering
        const rect = canvas.getBoundingClientRect();
        const dpr = window.devicePixelRatio || 1;
        const width = rect.width || 600;
        const height = rect.height || 300;

        canvas.width = width * dpr;
        canvas.height = height * dpr;
        ctx.scale(dpr, dpr);

        // Clear background
        ctx.fillStyle = '#080c1e';
        ctx.fillRect(0, 0, width, height);

        const candles = state.market.chartData.candles;
        if (!candles || candles.length === 0) return;

        let minPrice = Math.min(...candles.map(c => c.low));
        let maxPrice = Math.max(...candles.map(c => c.high));
        const padding = (maxPrice - minPrice) * 0.05 || 1;
        minPrice -= padding;
        maxPrice += padding;

        const paddingLeft = 10;
        const paddingRight = 60;
        const paddingTop = 20;
        const paddingBottom = 30;

        const chartW = width - paddingLeft - paddingRight;
        const chartH = height - paddingTop - paddingBottom;

        // Grid lines
        ctx.strokeStyle = 'rgba(255, 255, 255, 0.05)';
        ctx.lineWidth = 1;
        const gridSteps = 5;
        for (let i = 0; i <= gridSteps; i++) {
            const y = paddingTop + (chartH / gridSteps) * i;
            ctx.beginPath();
            ctx.moveTo(paddingLeft, y);
            ctx.lineTo(width - paddingRight, y);
            ctx.stroke();

            const pVal = maxPrice - ((maxPrice - minPrice) / gridSteps) * i;
            ctx.fillStyle = '#64748b';
            ctx.font = '10px sans-serif';
            ctx.textAlign = 'left';
            ctx.fillText('$' + pVal.toFixed(2), width - paddingRight + 8, y + 3);
        }

        // Render Candlesticks
        const candleWidth = Math.max(2, (chartW / candles.length) - 3);
        candles.forEach((c, i) => {
            const x = paddingLeft + (chartW / candles.length) * i + candleWidth / 2;
            const yOpen = paddingTop + chartH * (1 - (c.open - minPrice) / (maxPrice - minPrice));
            const yClose = paddingTop + chartH * (1 - (c.close - minPrice) / (maxPrice - minPrice));
            const yHigh = paddingTop + chartH * (1 - (c.high - minPrice) / (maxPrice - minPrice));
            const yLow = paddingTop + chartH * (1 - (c.low - minPrice) / (maxPrice - minPrice));

            const isBull = c.close >= c.open;
            const color = isBull ? '#10b981' : '#ef4444';

            // Wick
            ctx.strokeStyle = color;
            ctx.lineWidth = 1.2;
            ctx.beginPath();
            ctx.moveTo(x, yHigh);
            ctx.lineTo(x, yLow);
            ctx.stroke();

            // Body
            ctx.fillStyle = color;
            const top = Math.min(yOpen, yClose);
            const bodyH = Math.max(2, Math.abs(yClose - yOpen));
            ctx.fillRect(x - candleWidth / 2, top, candleWidth, bodyH);
        });
    }

    /**
     * Order Book Simulation Engine
     */
    function populateOrderBook() {
        const current = state.market.price;
        state.orderBook.asks = [];
        state.orderBook.bids = [];

        for (let i = 1; i <= state.orderBook.maxDepth; i++) {
            const askPrice = current * (1 + (i * 0.0012));
            const bidPrice = current * (1 - (i * 0.0012));
            const askAmount = (Math.random() * 3.5 + 0.1).toFixed(4);
            const bidAmount = (Math.random() * 3.5 + 0.1).toFixed(4);

            state.orderBook.asks.push({ price: askPrice, amount: parseFloat(askAmount) });
            state.orderBook.bids.push({ price: bidPrice, amount: parseFloat(bidAmount) });
        }
    }

    function renderOrderBook() {
        if (!DOM.orderBookAsks || !DOM.orderBookBids) return;

        let asksHTML = '';
        let bidsHTML = '';

        state.orderBook.asks.slice().reverse().forEach(item => {
            const total = (item.price * item.amount).toFixed(2);
            asksHTML += `<div class="orderbook-row ask">
                <span class="price">${item.price.toFixed(2)}</span>
                <span class="amount">${item.amount.toFixed(4)}</span>
                <span class="total">${total}</span>
            </div>`;
        });

        state.orderBook.bids.forEach(item => {
            const total = (item.price * item.amount).toFixed(2);
            bidsHTML += `<div class="orderbook-row bid">
                <span class="price">${item.price.toFixed(2)}</span>
                <span class="amount">${item.amount.toFixed(4)}</span>
                <span class="total">${total}</span>
            </div>`;
        });

        DOM.orderBookAsks.innerHTML = asksHTML;
        DOM.orderBookBids.innerHTML = bidsHTML;
    }

    /**
     * Portfolio & Transaction Rendering
     */
    function renderPortfolio() {
        if (!DOM.portfolioTable) return;
        let html = '';
        let totalVal = 0;

        state.portfolio.forEach(item => {
            const val = item.balance * item.price;
            totalVal += val;
        });

        state.portfolio.forEach(item => {
            const val = item.balance * item.price;
            const alloc = totalVal > 0 ? ((val / totalVal) * 100).toFixed(1) : 0;
            html += `<tr>
                <td><strong>${item.symbol}</strong> <span class="text-muted">(${item.name})</span></td>
                <td>${item.balance.toLocaleString(undefined, { minimumFractionDigits: 2 })}</td>
                <td>$${item.price.toLocaleString(undefined, { minimumFractionDigits: 2 })}</td>
                <td>$${val.toLocaleString(undefined, { minimumFractionDigits: 2 })}</td>
                <td><div class="badge-pill">${alloc}%</div></td>
            </tr>`;
        });

        DOM.portfolioTable.innerHTML = html;
    }

    function renderTransactions() {
        if (!DOM.txTable) return;
        let html = '';

        state.transactions.forEach(tx => {
            const timeAgo = formatTimeAgo(tx.timestamp);
            html += `<tr>
                <td class="font-mono">${tx.hash}</td>
                <td><span class="badge-tx ${tx.type.toLowerCase()}">${tx.type}</span></td>
                <td>${tx.description}</td>
                <td><span class="status-tag ${tx.status.toLowerCase()}">${tx.status}</span></td>
                <td class="text-muted">${timeAgo}</td>
            </tr>`;
        });

        DOM.txTable.innerHTML = html;
    }

    /**
     * UI Updates
     */
    function updateUI() {
        if (DOM.connectBtn) {
            DOM.connectBtn.textContent = state.wallet.connected
                ? formatAddress(state.wallet.address)
                : 'Connect Wallet';
            DOM.connectBtn.classList.toggle('connected', state.wallet.connected);
        }

        if (DOM.walletAddress) {
            DOM.walletAddress.textContent = state.wallet.connected
                ? state.wallet.address
                : 'Not Connected';
        }

        if (DOM.walletBalance) {
            DOM.walletBalance.textContent = state.wallet.balanceEth.toFixed(4) + ' ETH';
        }

        if (DOM.gasPrice) {
            DOM.gasPrice.textContent = `${state.gas.current} Gwei`;
        }

        if (DOM.currentPrice) {
            DOM.currentPrice.textContent = `$${state.market.price.toFixed(2)}`;
        }

        if (DOM.priceChange) {
            const isPos = state.market.change24h >= 0;
            DOM.priceChange.textContent = `${isPos ? '+' : ''}${state.market.change24h.toFixed(2)}%`;
            DOM.priceChange.className = `price-change ${isPos ? 'positive' : 'negative'}`;
        }

        if (DOM.stakedAmountDisplay) {
            DOM.stakedAmountDisplay.textContent = `${state.staking.stakedOpus.toLocaleString()} OPUS`;
        }

        if (DOM.pendingRewardsDisplay) {
            DOM.pendingRewardsDisplay.textContent = `${state.staking.pendingRewards.toFixed(4)} OPUS`;
        }
    }

    /**
     * DEX Swapping Logic Engine
     */
    function calculateSwap() {
        if (!DOM.swapPayInput || !DOM.swapReceiveInput || !DOM.swapPaySelect || !DOM.swapReceiveSelect) return;
        const payToken = DOM.swapPaySelect.value;
        const receiveToken = DOM.swapReceiveSelect.value;
        const payAmount = parseFloat(DOM.swapPayInput.value) || 0;

        if (payAmount <= 0) {
            DOM.swapReceiveInput.value = '';
            return;
        }

        const payTokenObj = state.wallet.tokens.find(t => t.symbol === payToken) || { price: 1 };
        const receiveTokenObj = state.wallet.tokens.find(t => t.symbol === receiveToken) || { price: 1 };

        const usdValue = payAmount * payTokenObj.price;
        const receiveAmount = usdValue / receiveTokenObj.price;

        // Apply fee (0.3% simulated swap fee)
        const netReceive = receiveAmount * 0.997;
        DOM.swapReceiveInput.value = netReceive.toFixed(4);
    }

    function executeSwap() {
        playSound('click');
        if (!state.wallet.connected) {
            addNotification('Wallet Required', 'Please connect your Web3 wallet first.', 'warning');
            return;
        }

        const payToken = DOM.swapPaySelect.value;
        const receiveToken = DOM.swapReceiveSelect.value;
        const payAmount = parseFloat(DOM.swapPayInput.value) || 0;
        const receiveAmount = parseFloat(DOM.swapReceiveInput.value) || 0;

        if (payAmount <= 0 || payToken === receiveToken) {
            addNotification('Invalid Swap', 'Please enter a valid swap amount and distinct tokens.', 'error');
            playSound('error');
            return;
        }

        const payTokenObj = state.wallet.tokens.find(t => t.symbol === payToken);
        if (payTokenObj && payTokenObj.balance < payAmount) {
            addNotification('Insufficient Balance', `You do not have enough ${payToken} to complete this trade.`, 'error');
            playSound('error');
            return;
        }

        // Perform swap balance mutation
        if (payTokenObj) payTokenObj.balance -= payAmount;
        const receiveTokenObj = state.wallet.tokens.find(t => t.symbol === receiveToken);
        if (receiveTokenObj) receiveTokenObj.balance += receiveAmount;

        // Record transaction
        const txHash = generateMockHash();
        state.transactions.unshift({
            hash: formatAddress(txHash),
            type: 'Swap',
            description: `Swapped ${payAmount} ${payToken} for ${receiveAmount.toFixed(4)} ${receiveToken}`,
            amount: `${payAmount} ${payToken}`,
            status: 'Confirmed',
            timestamp: Date.now(),
            blockNumber: 19842100 + Math.floor(Math.random() * 50)
        });

        DOM.swapPayInput.value = '';
        DOM.swapReceiveInput.value = '';

        playSound('success');
        addNotification('Swap Executed', `Successfully swapped ${payAmount} ${payToken} for ${receiveAmount.toFixed(4)} ${receiveToken}!`, 'success');
        renderPortfolio();
        renderTransactions();
        updateUI();
    }

    /**
     * Yield Staking Interactions
     */
    function handleStake() {
        playSound('click');
        if (!state.wallet.connected) {
            addNotification('Wallet Required', 'Connect wallet to stake OPUS tokens.', 'warning');
            return;
        }

        const amount = parseFloat(DOM.stakeInput ? DOM.stakeInput.value : 0);
        const opusObj = state.wallet.tokens.find(t => t.symbol === 'OPUS');

        if (!amount || amount <= 0 || (opusObj && opusObj.balance < amount)) {
            addNotification('Invalid Staking Amount', 'Check your OPUS token balance and try again.', 'error');
            playSound('error');
            return;
        }

        if (opusObj) opusObj.balance -= amount;
        state.staking.stakedOpus += amount;

        state.transactions.unshift({
            hash: formatAddress(generateMockHash()),
            type: 'Stake',
            description: `Staked ${amount.toLocaleString()} OPUS in Vault`,
            amount: `${amount} OPUS`,
            status: 'Confirmed',
            timestamp: Date.now(),
            blockNumber: 19842105
        });

        if (DOM.stakeInput) DOM.stakeInput.value = '';
        playSound('success');
        addNotification('Tokens Staked', `Successfully staked ${amount.toLocaleString()} OPUS in high-yield vault.`, 'success');
        renderPortfolio();
        renderTransactions();
        updateUI();
    }

    function handleClaimRewards() {
        playSound('click');
        if (state.staking.pendingRewards <= 0) {
            addNotification('No Rewards', 'You have no accrued yield rewards to claim right now.', 'info');
            return;
        }

        const claimed = state.staking.pendingRewards;
        const opusObj = state.wallet.tokens.find(t => t.symbol === 'OPUS');
        if (opusObj) opusObj.balance += claimed;

        state.staking.pendingRewards = 0;
        state.staking.lastClaimed = Date.now();

        state.transactions.unshift({
            hash: formatAddress(generateMockHash()),
            type: 'Claim',
            description: `Claimed ${claimed.toFixed(4)} OPUS Staking Rewards`,
            amount: `${claimed.toFixed(4)} OPUS`,
            status: 'Confirmed',
            timestamp: Date.now(),
            blockNumber: 19842110
        });

        playSound('success');
        addNotification('Rewards Claimed', `Claimed ${claimed.toFixed(4)} OPUS rewards to your wallet!`, 'success');
        renderPortfolio();
        renderTransactions();
        updateUI();
    }

    /**
     * Web3 Provider Connection Simulation
     */
    function toggleWalletConnection() {
        playSound('click');
        if (state.wallet.connected) {
            state.wallet.connected = false;
            state.wallet.address = null;
            addNotification('Wallet Disconnected', 'Your wallet has been disconnected.', 'info');
        } else {
            if (window.ethereum) {
                window.ethereum.request({ method: 'eth_requestAccounts' })
                    .then(accounts => {
                        state.wallet.connected = true;
                        state.wallet.address = accounts[0];
                        playSound('success');
                        addNotification('Web3 Connected', `Connected account: ${formatAddress(accounts[0])}`, 'success');
                        updateUI();
                    })
                    .catch(() => {
                        simulateMockWalletConnect();
                    });
            } else {
                simulateMockWalletConnect();
            }
        }
        updateUI();
    }

    function simulateMockWalletConnect() {
        state.wallet.connected = true;
        state.wallet.address = generateMockHash().substring(0, 42);
        playSound('success');
        addNotification('Demo Wallet Connected', `Simulated Web3 Session active: ${formatAddress(state.wallet.address)}`, 'success');
        updateUI();
    }

    function setupWeb3Listeners() {
        if (window.ethereum) {
            window.ethereum.on('accountsChanged', (accounts) => {
                if (accounts.length === 0) {
                    state.wallet.connected = false;
                    state.wallet.address = null;
                } else {
                    state.wallet.connected = true;
                    state.wallet.address = accounts[0];
                }
                updateUI();
            });
            window.ethereum.on('chainChanged', () => {
                window.location.reload();
            });
        }
    }

    /**
     * Real-time Simulation Engines
     */
    function startSimulationEngines() {
        // Market Price Motion Simulator
        marketInterval = setInterval(() => {
            const delta = (Math.random() - 0.49) * (state.market.price * 0.002);
            state.market.price = Math.max(1, state.market.price + delta);
            state.market.change24h += (Math.random() - 0.5) * 0.05;

            // Update Chart Data
            const candles = state.market.chartData.candles;
            if (candles && candles.length > 0) {
                const last = candles[candles.length - 1];
                last.close = state.market.price;
                if (state.market.price > last.high) last.high = state.market.price;
                if (state.market.price < last.low) last.low = state.market.price;
            }

            renderChartCanvas();
            populateOrderBook();
            renderOrderBook();
            updateUI();
        }, state.settings.autoRefreshInterval);

        // Gas Ticker
        gasInterval = setInterval(() => {
            state.gas.current = Math.max(8, Math.floor(18 + (Math.random() - 0.5) * 6));
            if (DOM.gasPrice) DOM.gasPrice.textContent = `${state.gas.current} Gwei`;
        }, 5000);

        // Staking Reward Accrual Engine
        stakingInterval = setInterval(() => {
            if (state.staking.stakedOpus > 0) {
                const secPerYear = 31536000;
                const rewardPerSec = (state.staking.stakedOpus * (state.staking.rewardRateApy / 100)) / secPerYear;
                state.staking.pendingRewards += rewardPerSec;
                if (DOM.pendingRewardsDisplay) {
                    DOM.pendingRewardsDisplay.textContent = `${state.staking.pendingRewards.toFixed(4)} OPUS`;
                }
            }
        }, 1000);
    }

    /**
     * Notification Engine
     */
    function addNotification(title, message, type = 'info') {
        const notification = {
            id: Date.now(),
            title,
            message,
            type,
            timestamp: new Date()
        };
        state.notifications.push(notification);
        renderNotification(notification);
    }

    function renderNotification(notif) {
        if (!DOM.notificationsContainer) return;
        const el = document.createElement('div');
        el.className = `notification-toast toast-${notif.type}`;
        el.innerHTML = `
            <div class="toast-content">
                <strong>${notif.title}</strong>
                <p>${notif.message}</p>
            </div>
            <button class="toast-close">&times;</button>
        `;

        el.querySelector('.toast-close').addEventListener('click', () => {
            el.remove();
        });

        DOM.notificationsContainer.appendChild(el);
        setTimeout(() => {
            if (el.parentNode) el.remove();
        }, 6000);
    }

    /**
     * Event Listeners Registration
     */
    function setupEventListeners() {
        if (DOM.connectBtn) {
            DOM.connectBtn.addEventListener('click', toggleWalletConnection);
        }

        if (DOM.swapPayInput) {
            DOM.swapPayInput.addEventListener('input', calculateSwap);
        }

        if (DOM.swapPaySelect) {
            DOM.swapPaySelect.addEventListener('change', calculateSwap);
        }

        if (DOM.swapReceiveSelect) {
            DOM.swapReceiveSelect.addEventListener('change', calculateSwap);
        }

        if (DOM.swapExecuteBtn) {
            DOM.swapExecuteBtn.addEventListener('click', executeSwap);
        }

        if (DOM.stakeBtn) {
            DOM.stakeBtn.addEventListener('click', handleStake);
        }

        if (DOM.claimRewardsBtn) {
            DOM.claimRewardsBtn.addEventListener('click', handleClaimRewards);
        }

        if (DOM.pairSelect) {
            DOM.pairSelect.addEventListener('change', (e) => {
                const pair = e.target.value;
                if (PAIR_RATES[pair]) {
                    state.market.selectedPair = pair;
                    state.market.price = PAIR_RATES[pair].price;
                    initChartData();
                    renderChartCanvas();
                    populateOrderBook();
                    renderOrderBook();
                    updateUI();
                    playSound('click');
                }
            });
        }

        window.addEventListener('resize', () => {
            renderChartCanvas();
        });
    }

    /**
     * Helper Utilities
     */
    function formatAddress(addr) {
        if (!addr) return '';
        return `${addr.substring(0, 6)}...${addr.substring(addr.length - 4)}`;
    }

    function generateMockHash() {
        const chars = '0123456789abcdef';
        let hash = '0x';
        for (let i = 0; i < 64; i++) {
            hash += chars[Math.floor(Math.random() * chars.length)];
        }
        return hash;
    }

    function formatTimeAgo(timestamp) {
        const diff = Math.floor((Date.now() - timestamp) / 1000);
        if (diff < 60) return `${diff}s ago`;
        if (diff < 3600) return `${Math.floor(diff / 60)}m ago`;
        if (diff < 86400) return `${Math.floor(diff / 3600)}h ago`;
        return `${Math.floor(diff / 86400)}d ago`;
    }

    // Boot on DOM Ready
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
    } else {
        init();
    }
})();
