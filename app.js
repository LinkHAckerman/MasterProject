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
            timeframe: '24H',
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
    // Pair Exchange Rates Dictionary
    // ---------------------------------------------------------------------
    const PAIR_RATES = {
        'ETH/USDT': { base: 'ETH', quote: 'USDT', price: 3450.75, decimals: 2 },
        'BTC/USDT': { base: 'BTC', quote: 'USDT', price: 64200.00, decimals: 2 },
        'SOL/USDT': { base: 'SOL', quote: 'USDT', price: 145.20, decimals: 2 },
        'OPUS/USDT': { base: 'OPUS', quote: 'USDT', price: 0.45, decimals: 4 },
        'ETH/BTC': { base: 'ETH', quote: 'BTC', price: 0.0537, decimals: 6 }
    };

    // Tickers & Web Audio context
    let marketInterval = null;
    let gasInterval = null;
    let stakingInterval = null;
    let audioCtx = null;

    // ---------------------------------------------------------------------
    // Web Audio Sound Engine
    // ---------------------------------------------------------------------
    function initAudio() {
        if (!audioCtx && (window.AudioContext || window.webkitAudioContext)) {
            const AudioCtxClass = window.AudioContext || window.webkitAudioContext;
            audioCtx = new AudioCtxClass();
        }
    }

    function playSound(type) {
        if (!state.settings.enableSounds) return;
        try {
            initAudio();
            if (!audioCtx) return;
            if (audioCtx.state === 'suspended') {
                audioCtx.resume();
            }
            const osc = audioCtx.createOscillator();
            const gain = audioCtx.createGain();
            osc.connect(gain);
            gain.connect(audioCtx.destination);
            const now = audioCtx.currentTime;

            if (type === 'click') {
                osc.type = 'sine';
                osc.frequency.setValueAtTime(600, now);
                osc.frequency.exponentialRampToValueAtTime(800, now + 0.05);
                gain.gain.setValueAtTime(0.08, now);
                gain.gain.exponentialRampToValueAtTime(0.001, now + 0.05);
                osc.start(now);
                osc.stop(now + 0.05);
            } else if (type === 'success') {
                osc.type = 'triangle';
                osc.frequency.setValueAtTime(440, now);
                osc.frequency.setValueAtTime(554.37, now + 0.08);
                osc.frequency.setValueAtTime(659.25, now + 0.16);
                gain.gain.setValueAtTime(0.1, now);
                gain.gain.exponentialRampToValueAtTime(0.001, now + 0.3);
                osc.start(now);
                osc.stop(now + 0.3);
            } else if (type === 'swap') {
                osc.type = 'sine';
                osc.frequency.setValueAtTime(300, now);
                osc.frequency.exponentialRampToValueAtTime(900, now + 0.12);
                gain.gain.setValueAtTime(0.12, now);
                gain.gain.exponentialRampToValueAtTime(0.001, now + 0.15);
                osc.start(now);
                osc.stop(now + 0.15);
            } else if (type === 'error') {
                osc.type = 'sawtooth';
                osc.frequency.setValueAtTime(180, now);
                osc.frequency.setValueAtTime(140, now + 0.1);
                gain.gain.setValueAtTime(0.1, now);
                gain.gain.exponentialRampToValueAtTime(0.001, now + 0.25);
                osc.start(now);
                osc.stop(now + 0.25);
            }
        } catch (e) {
            console.warn('Audio playback error:', e);
        }
    }

    // ---------------------------------------------------------------------
    // Formatting Helpers
    // ---------------------------------------------------------------------
    function formatCurrency(val, decimals = 2, prefix = '$') {
        if (val === undefined || val === null || isNaN(val)) return `${prefix}0.00`;
        return `${prefix}${Number(val).toLocaleString('en-US', {
            minimumFractionDigits: decimals,
            maximumFractionDigits: decimals
        })}`;
    }

    function formatNumber(val, decimals = 4) {
        if (val === undefined || val === null || isNaN(val)) return '0.00';
        return Number(val).toLocaleString('en-US', {
            minimumFractionDigits: decimals,
            maximumFractionDigits: decimals
        });
    }

    function truncateAddress(addr) {
        if (!addr) return '';
        return `${addr.substring(0, 6)}...${addr.substring(addr.length - 4)}`;
    }

    function escapeHtml(str) {
        if (!str) return '';
        return String(str)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;')
            .replace(/'/g, '&#039;');
    }

    // ---------------------------------------------------------------------
    // Toast Notifications System
    // ---------------------------------------------------------------------
    function showNotification(title, message, type = 'info') {
        const id = 'notif_' + Date.now();
        const notification = { id, title, message, type, time: new Date() };
        state.notifications.unshift(notification);

        const toastContainer = document.getElementById('toastContainer') || createToastContainer();
        const toast = document.createElement('div');
        toast.className = `toast toast-${type} fade-in`;
        toast.id = id;
        toast.innerHTML = `
            <div class="toast-header">
                <span class="toast-title">${escapeHtml(title)}</span>
                <span class="toast-close" data-toast-id="${id}">&times;</span>
            </div>
            <div class="toast-body">${escapeHtml(message)}</div>
        `;

        toastContainer.appendChild(toast);

        const closeBtn = toast.querySelector('.toast-close');
        if (closeBtn) {
            closeBtn.addEventListener('click', () => {
                toast.remove();
            });
        }

        setTimeout(() => {
            if (document.getElementById(id)) {
                toast.classList.add('fade-out');
                setTimeout(() => toast.remove(), 300);
            }
        }, 5000);
    }

    function createToastContainer() {
        let container = document.getElementById('toastContainer');
        if (!container) {
            container = document.createElement('div');
            container.id = 'toastContainer';
            container.className = 'toast-container';
            document.body.appendChild(container);
        }
        return container;
    }

    // ---------------------------------------------------------------------
    // Orderbook Simulation
    // ---------------------------------------------------------------------
    function generateOrderBook() {
        const currentPrice = state.market.price;
        const decimals = PAIR_RATES[state.market.selectedPair]?.decimals || 2;
        const bids = [];
        const asks = [];

        let cumulativeBidVol = 0;
        let cumulativeAskVol = 0;

        for (let i = 0; i < state.orderBook.maxDepth; i++) {
            const bidPrice = currentPrice * (1 - (i + 1) * 0.0008 - Math.random() * 0.0004);
            const bidAmount = (Math.random() * 3.5 + 0.1).toFixed(4);
            cumulativeBidVol += parseFloat(bidAmount);
            bids.push({
                price: bidPrice.toFixed(decimals),
                amount: bidAmount,
                total: cumulativeBidVol.toFixed(decimals)
            });

            const askPrice = currentPrice * (1 + (i + 1) * 0.0008 + Math.random() * 0.0004);
            const askAmount = (Math.random() * 3.5 + 0.1).toFixed(4);
            cumulativeAskVol += parseFloat(askAmount);
            asks.push({
                price: askPrice.toFixed(decimals),
                amount: askAmount,
                total: cumulativeAskVol.toFixed(decimals)
            });
        }

        state.orderBook.bids = bids;
        state.orderBook.asks = asks;
        renderOrderBook();
    }

    function renderOrderBook() {
        const bidsContainer = document.getElementById('orderBookBids');
        const asksContainer = document.getElementById('orderBookAsks');
        if (!bidsContainer || !asksContainer) return;

        const maxTotal = Math.max(
            parseFloat(state.orderBook.bids[state.orderBook.bids.length - 1]?.total || 1),
            parseFloat(state.orderBook.asks[state.orderBook.asks.length - 1]?.total || 1)
        );

        bidsContainer.innerHTML = state.orderBook.bids.map(item => {
            const depthPct = Math.min(100, (parseFloat(item.total) / maxTotal) * 100);
            return `
                <div class="orderbook-row bid-row">
                    <span class="col-price price-green">${item.price}</span>
                    <span class="col-amount">${item.amount}</span>
                    <span class="col-total">${item.total}</span>
                    <div class="depth-bar bid-bar" style="width: ${depthPct}%"></div>
                </div>
            `;
        }).join('');

        asksContainer.innerHTML = state.orderBook.asks.map(item => {
            const depthPct = Math.min(100, (parseFloat(item.total) / maxTotal) * 100);
            return `
                <div class="orderbook-row ask-row">
                    <span class="col-price price-red">${item.price}</span>
                    <span class="col-amount">${item.amount}</span>
                    <span class="col-total">${item.total}</span>
                    <div class="depth-bar ask-bar" style="width: ${depthPct}%"></div>
                </div>
            `;
        }).join('');
    }

    // ---------------------------------------------------------------------
    // Interactive Canvas Chart Renderer
    // ---------------------------------------------------------------------
    function initChartData() {
        const count = 50;
        const basePrice = state.market.price;
        const prices = [];
        const labels = [];
        const candles = [];

        let current = basePrice * 0.95;
        const now = Date.now();

        for (let i = count; i >= 0; i--) {
            const time = new Date(now - i * 3600000);
            const timeStr = time.getHours().toString().padStart(2, '0') + ':00';
            const change = (Math.random() - 0.48) * (basePrice * 0.012);
            const open = current;
            const close = open + change;
            const high = Math.max(open, close) + Math.random() * (basePrice * 0.005);
            const low = Math.min(open, close) - Math.random() * (basePrice * 0.005);
            current = close;

            prices.push(close);
            labels.push(timeStr);
            candles.push({ open, high, low, close, time: timeStr });
        }

        state.market.chartData = { labels, prices, candles };
        state.market.price = current;
        renderChart();
    }

    function renderChart() {
        const canvas = document.getElementById('marketChart');
        if (!canvas) return;
        const ctx = canvas.getContext('2d');
        const rect = canvas.getBoundingClientRect();

        const dpr = window.devicePixelRatio || 1;
        canvas.width = (rect.width || 600) * dpr;
        canvas.height = (rect.height || 320) * dpr;
        ctx.scale(dpr, dpr);

        const width = rect.width || 600;
        const height = rect.height || 320;
        const padding = { top: 20, right: 60, bottom: 30, left: 20 };

        ctx.clearRect(0, 0, width, height);

        const prices = state.market.chartData.prices;
        if (!prices || prices.length === 0) return;

        const minPrice = Math.min(...prices) * 0.995;
        const maxPrice = Math.max(...prices) * 1.005;
        const priceRange = maxPrice - minPrice || 1;

        const chartWidth = width - padding.left - padding.right;
        const chartHeight = height - padding.top - padding.bottom;

        // Grid Lines & Price Axis Labels
        ctx.strokeStyle = 'rgba(255, 255, 255, 0.05)';
        ctx.lineWidth = 1;
        const gridSteps = 5;
        for (let i = 0; i <= gridSteps; i++) {
            const y = padding.top + (chartHeight / gridSteps) * i;
            ctx.beginPath();
            ctx.moveTo(padding.left, y);
            ctx.lineTo(width - padding.right, y);
            ctx.stroke();

            const pValue = maxPrice - (priceRange / gridSteps) * i;
            ctx.fillStyle = 'rgba(148, 163, 184, 0.6)';
            ctx.font = '10px Inter, sans-serif';
            ctx.textAlign = 'left';
            ctx.fillText(formatCurrency(pValue, 2, '$'), width - padding.right + 8, y + 3);
        }

        // Line Chart & Area Fill
        const stepX = chartWidth / (prices.length - 1);
        ctx.beginPath();
        prices.forEach((p, idx) => {
            const x = padding.left + idx * stepX;
            const y = padding.top + chartHeight - ((p - minPrice) / priceRange) * chartHeight;
            if (idx === 0) ctx.moveTo(x, y);
            else ctx.lineTo(x, y);
        });

        const isPositive = prices[prices.length - 1] >= prices[0];
        const strokeColor = isPositive ? '#10b981' : '#ef4444';
        const fillGradient = ctx.createLinearGradient(0, padding.top, 0, height - padding.bottom);
        fillGradient.addColorStop(0, isPositive ? 'rgba(16, 185, 129, 0.25)' : 'rgba(239, 68, 68, 0.25)');
        fillGradient.addColorStop(1, 'rgba(16, 185, 129, 0.0)');

        ctx.strokeStyle = strokeColor;
        ctx.lineWidth = 2.5;
        ctx.stroke();

        ctx.lineTo(padding.left + (prices.length - 1) * stepX, padding.top + chartHeight);
        ctx.lineTo(padding.left, padding.top + chartHeight);
        ctx.closePath();
        ctx.fillStyle = fillGradient;
        ctx.fill();

        // Current Price Dashed Indicator Line
        const lastPrice = prices[prices.length - 1];
        const lastY = padding.top + chartHeight - ((lastPrice - minPrice) / priceRange) * chartHeight;
        ctx.strokeStyle = strokeColor;
        ctx.setLineDash([4, 4]);
        ctx.beginPath();
        ctx.moveTo(padding.left, lastY);
        ctx.lineTo(width - padding.right, lastY);
        ctx.stroke();
        ctx.setLineDash([]);
    }

    // ---------------------------------------------------------------------
    // DEX Swap Router & Calculation Engine
    // ---------------------------------------------------------------------
    function updateSwapAmounts(source) {
        const payInput = document.getElementById('swapPayAmount');
        const receiveInput = document.getElementById('swapReceiveAmount');
        const payTokenSelect = document.getElementById('swapPayToken');
        const receiveTokenSelect = document.getElementById('swapReceiveToken');

        if (!payInput || !receiveInput || !payTokenSelect || !receiveTokenSelect) return;

        const paySymbol = payTokenSelect.value;
        const receiveSymbol = receiveTokenSelect.value;

        const payToken = state.wallet.tokens.find(t => t.symbol === paySymbol);
        const receiveToken = state.wallet.tokens.find(t => t.symbol === receiveSymbol);

        if (!payToken || !receiveToken) return;

        if (source === 'pay') {
            const amount = parseFloat(payInput.value) || 0;
            if (amount <= 0) {
                receiveInput.value = '';
                return;
            }
            const totalValueUsd = amount * payToken.price;
            const receiveAmount = totalValueUsd / receiveToken.price;
            receiveInput.value = receiveAmount.toFixed(receiveToken.decimals > 8 ? 6 : 4);
        } else if (source === 'receive') {
            const amount = parseFloat(receiveInput.value) || 0;
            if (amount <= 0) {
                payInput.value = '';
                return;
            }
            const totalValueUsd = amount * receiveToken.price;
            const payAmount = totalValueUsd / payToken.price;
            payInput.value = payAmount.toFixed(payToken.decimals > 8 ? 6 : 4);
        }

        updateSwapDetails();
    }

    function updateSwapDetails() {
        const payInput = document.getElementById('swapPayAmount');
        const payTokenSelect = document.getElementById('swapPayToken');
        const receiveTokenSelect = document.getElementById('swapReceiveToken');
        const rateDisplay = document.getElementById('swapExchangeRate');
        const priceImpactDisplay = document.getElementById('swapPriceImpact');
        const minReceivedDisplay = document.getElementById('swapMinReceived');
        const feeDisplay = document.getElementById('swapNetworkFee');

        if (!payInput || !payTokenSelect || !receiveTokenSelect) return;

        const paySymbol = payTokenSelect.value;
        const receiveSymbol = receiveTokenSelect.value;
        const payToken = state.wallet.tokens.find(t => t.symbol === paySymbol);
        const receiveToken = state.wallet.tokens.find(t => t.symbol === receiveSymbol);

        if (!payToken || !receiveToken) return;

        const rate = payToken.price / receiveToken.price;
        if (rateDisplay) {
            rateDisplay.innerText = `1 ${paySymbol} ≈ ${rate.toFixed(4)} ${receiveSymbol}`;
        }

        const amount = parseFloat(payInput.value) || 0;
        const impact = Math.min((amount * payToken.price) / 500000 * 100, 5.0).toFixed(2);
        if (priceImpactDisplay) {
            priceImpactDisplay.innerText = `${impact}%`;
            priceImpactDisplay.className = impact > 2.0 ? 'text-red' : 'text-green';
        }

        if (minReceivedDisplay) {
            const expectedReceive = (amount * payToken.price) / receiveToken.price;
            const minAmount = expectedReceive * (1 - state.settings.slippageTolerance / 100);
            minReceivedDisplay.innerText = `${minAmount.toFixed(4)} ${receiveSymbol}`;
        }

        if (feeDisplay) {
            feeDisplay.innerText = `$${(state.gas.current * 0.12).toFixed(2)} (${state.gas.current} Gwei)`;
        }
    }

    function executeSwap() {
        const payInput = document.getElementById('swapPayAmount');
        const payTokenSelect = document.getElementById('swapPayToken');
        const receiveTokenSelect = document.getElementById('swapReceiveToken');

        if (!payInput || !payTokenSelect || !receiveTokenSelect) return;

        if (!state.wallet.connected) {
            playSound('error');
            showNotification('Wallet Disconnected', 'Please connect your Web3 wallet first.', 'error');
            return;
        }

        const payAmount = parseFloat(payInput.value);
        if (!payAmount || payAmount <= 0) {
            playSound('error');
            showNotification('Invalid Amount', 'Please enter a valid swap amount.', 'error');
            return;
        }

        const paySymbol = payTokenSelect.value;
        const receiveSymbol = receiveTokenSelect.value;
        const payToken = state.wallet.tokens.find(t => t.symbol === paySymbol);
        const receiveToken = state.wallet.tokens.find(t => t.symbol === receiveSymbol);

        if (payToken.balance < payAmount) {
            playSound('error');
            showNotification('Insufficient Balance', `You do not have enough ${paySymbol}.`, 'error');
            return;
        }

        const receivedAmount = (payAmount * payToken.price) / receiveToken.price;

        payToken.balance -= payAmount;
        receiveToken.balance += receivedAmount;

        const txHash = '0x' + Array.from({ length: 8 }, () => Math.floor(Math.random() * 16).toString(16)).join('') + '...' + Array.from({ length: 4 }, () => Math.floor(Math.random() * 16).toString(16)).join('');
        const tx = {
            hash: txHash,
            type: 'Swap',
            description: `Swapped ${payAmount} ${paySymbol} for ${receivedAmount.toFixed(4)} ${receiveSymbol}`,
            amount: `${payAmount} ${paySymbol}`,
            status: 'Confirmed',
            timestamp: Date.now(),
            blockNumber: 19842100 + Math.floor(Math.random() * 500)
        };

        state.transactions.unshift(tx);
        playSound('swap');
        showNotification('Swap Executed', tx.description, 'success');

        payInput.value = '';
        updateSwapAmounts('pay');
        renderWalletState();
        renderTransactions();
    }

    // ---------------------------------------------------------------------
    // Yield Staking Engine
    // ---------------------------------------------------------------------
    function updateStakingRewards() {
        const yieldPerSec = (state.staking.stakedOpus * (state.staking.rewardRateApy / 100)) / (365 * 86400);
        state.staking.pendingRewards += yieldPerSec * 3;

        const pendingDisplay = document.getElementById('pendingStakingRewards');
        if (pendingDisplay) {
            pendingDisplay.innerText = `${state.staking.pendingRewards.toFixed(6)} OPUS`;
        }
    }

    function executeClaimRewards() {
        if (!state.wallet.connected) {
            playSound('error');
            showNotification('Wallet Disconnected', 'Please connect your Web3 wallet.', 'error');
            return;
        }

        if (state.staking.pendingRewards <= 0) {
            playSound('error');
            showNotification('No Rewards', 'You have no pending rewards to claim.', 'info');
            return;
        }

        const claimed = state.staking.pendingRewards;
        const opusToken = state.wallet.tokens.find(t => t.symbol === 'OPUS');
        if (opusToken) opusToken.balance += claimed;

        state.staking.pendingRewards = 0;
        state.staking.lastClaimed = Date.now();

        const txHash = '0x' + Math.random().toString(16).substring(2, 10) + '...claim';
        state.transactions.unshift({
            hash: txHash,
            type: 'Claim Yield',
            description: `Claimed ${claimed.toFixed(4)} OPUS rewards`,
            amount: `${claimed.toFixed(4)} OPUS`,
            status: 'Confirmed',
            timestamp: Date.now(),
            blockNumber: 19842200
        });

        playSound('success');
        showNotification('Yield Claimed', `Successfully claimed ${claimed.toFixed(4)} OPUS!`, 'success');
        renderWalletState();
        renderTransactions();
    }

    function executeStakeOpus() {
        const input = document.getElementById('stakeAmountInput');
        if (!input) return;
        const amount = parseFloat(input.value);

        if (!state.wallet.connected) {
            playSound('error');
            showNotification('Wallet Disconnected', 'Connect wallet first.', 'error');
            return;
        }

        const opusToken = state.wallet.tokens.find(t => t.symbol === 'OPUS');
        if (!amount || amount <= 0 || amount > opusToken.balance) {
            playSound('error');
            showNotification('Invalid Stake Amount', 'Check your OPUS balance.', 'error');
            return;
        }

        opusToken.balance -= amount;
        state.staking.stakedOpus += amount;
        input.value = '';

        state.transactions.unshift({
            hash: '0x' + Math.random().toString(16).substring(2, 10) + '...stake',
            type: 'Stake',
            description: `Staked ${amount} OPUS in Yield Vault`,
            amount: `${amount} OPUS`,
            status: 'Confirmed',
            timestamp: Date.now(),
            blockNumber: 19842210
        });

        playSound('success');
        showNotification('Staking Confirmed', `Staked ${amount} OPUS at ${state.staking.rewardRateApy}% APY`, 'success');
        renderWalletState();
        renderStakingInfo();
        renderTransactions();
    }

    // ---------------------------------------------------------------------
    // UI Render Controllers
    // ---------------------------------------------------------------------
    function renderWalletState() {
        const btnConnect = document.getElementById('btnConnectWallet');
        const addrDisplay = document.getElementById('walletAddressDisplay');
        const ethDisplay = document.getElementById('walletBalanceEth');
        const usdtDisplay = document.getElementById('walletBalanceUsdt');

        if (state.wallet.connected) {
            if (btnConnect) {
                btnConnect.innerText = truncateAddress(state.wallet.address);
                btnConnect.classList.add('connected');
            }
            if (addrDisplay) addrDisplay.innerText = state.wallet.address;
        } else {
            if (btnConnect) {
                btnConnect.innerText = 'Connect Wallet';
                btnConnect.classList.remove('connected');
            }
            if (addrDisplay) addrDisplay.innerText = 'Not Connected';
        }

        const ethToken = state.wallet.tokens.find(t => t.symbol === 'ETH');
        const usdtToken = state.wallet.tokens.find(t => t.symbol === 'USDT');

        if (ethDisplay && ethToken) ethDisplay.innerText = `${formatNumber(ethToken.balance, 4)} ETH`;
        if (usdtDisplay && usdtToken) usdtDisplay.innerText = formatCurrency(usdtToken.balance, 2);

        renderPortfolio();
    }

    function renderPortfolio() {
        const container = document.getElementById('portfolioTableBody');
        if (!container) return;

        let totalVal = 0;
        state.wallet.tokens.forEach(t => {
            totalVal += t.balance * t.price;
        });

        const totalDisplay = document.getElementById('portfolioTotalValue');
        if (totalDisplay) totalDisplay.innerText = formatCurrency(totalVal, 2);

        container.innerHTML = state.wallet.tokens.map(token => {
            const val = token.balance * token.price;
            const alloc = totalVal > 0 ? ((val / totalVal) * 100).toFixed(1) : '0.0';
            return `
                <tr>
                    <td class="flex-align">
                        <span class="token-icon">${token.symbol.substring(0, 3)}</span>
                        <div>
                            <div class="font-bold">${token.name}</div>
                            <div class="text-subtle text-sm">${token.symbol}</div>
                        </div>
                    </td>
                    <td>${formatNumber(token.balance, 4)}</td>
                    <td>${formatCurrency(token.price, token.price < 1 ? 4 : 2)}</td>
                    <td class="font-bold">${formatCurrency(val, 2)}</td>
                    <td>
                        <div class="alloc-bar-container">
                            <span>${alloc}%</span>
                            <div class="alloc-bar" style="width: ${alloc}%"></div>
                        </div>
                    </td>
                </tr>
            `;
        }).join('');
    }

    function renderTransactions() {
        const container = document.getElementById('txHistoryTableBody');
        if (!container) return;

        if (state.transactions.length === 0) {
            container.innerHTML = '<tr><td colspan="5" class="text-center text-subtle">No transactions found</td></tr>';
            return;
        }

        container.innerHTML = state.transactions.map(tx => {
            const timeAgo = Math.floor((Date.now() - tx.timestamp) / 60000);
            const timeStr = timeAgo < 1 ? 'Just now' : timeAgo < 60 ? `${timeAgo}m ago` : `${Math.floor(timeAgo / 60)}h ago`;
            return `
                <tr>
                    <td class="font-mono text-cyan">${tx.hash}</td>
                    <td><span class="badge badge-${tx.type.toLowerCase().replace(/\s+/g, '')}">${tx.type}</span></td>
                    <td>${tx.description}</td>
                    <td>${timeStr}</td>
                    <td><span class="text-green">✓ ${tx.status}</span></td>
                </tr>
            `;
        }).join('');
    }

    function renderStakingInfo() {
        const stakedDisplay = document.getElementById('stakedOpusAmount');
        const apyDisplay = document.getElementById('stakingApyRate');

        if (stakedDisplay) stakedDisplay.innerText = `${formatNumber(state.staking.stakedOpus, 2)} OPUS`;
        if (apyDisplay) apyDisplay.innerText = `${state.staking.rewardRateApy}%`;
    }

    function renderGasPrices() {
        const slowEl = document.getElementById('gasSlow');
        const stdEl = document.getElementById('gasStandard');
        const fastEl = document.getElementById('gasFast');

        if (slowEl) slowEl.innerText = `${state.gas.slow} Gwei`;
        if (stdEl) stdEl.innerText = `${state.gas.standard} Gwei`;
        if (fastEl) fastEl.innerText = `${state.gas.fast} Gwei`;
    }

    // ---------------------------------------------------------------------
    // Real-Time Simulators
    // ---------------------------------------------------------------------
    function updateMarketPrices() {
        const fluctuation = (Math.random() - 0.49) * 0.006;
        state.market.price = state.market.price * (1 + fluctuation);
        state.market.high24h = Math.max(state.market.high24h, state.market.price);
        state.market.low24h = Math.min(state.market.low24h, state.market.price);

        const baseSymbol = state.market.selectedPair.split('/')[0];
        const token = state.wallet.tokens.find(t => t.symbol === baseSymbol);
        if (token) token.price = state.market.price;

        const currentPriceEl = document.getElementById('currentPairPrice');
        if (currentPriceEl) {
            currentPriceEl.innerText = formatCurrency(state.market.price, PAIR_RATES[state.market.selectedPair]?.decimals || 2);
            currentPriceEl.className = fluctuation >= 0 ? 'price-green' : 'price-red';
        }

        state.market.chartData.prices.shift();
        state.market.chartData.prices.push(state.market.price);

        renderChart();
        generateOrderBook();
        updateSwapDetails();
    }

    function updateGasTracker() {
        const base = Math.floor(Math.random() * 8) + 14;
        state.gas.slow = base - 4;
        state.gas.standard = base;
        state.gas.fast = base + 6;
        state.gas.current = base;
        renderGasPrices();
    }

    function toggleWalletConnection() {
        playSound('click');
        if (state.wallet.connected) {
            state.wallet.connected = false;
            state.wallet.address = null;
            showNotification('Wallet Disconnected', 'Your wallet has been disconnected.', 'info');
        } else {
            state.wallet.connected = true;
            state.wallet.address = '0x742d35Cc6634C0532925a3b844Bc454e4438f44e';
            showNotification('Wallet Connected', `Connected to ${truncateAddress(state.wallet.address)}`, 'success');
        }
        renderWalletState();
    }

    // ---------------------------------------------------------------------
    // DOM Initialization & Event Handlers
    // ---------------------------------------------------------------------
    function initEvents() {
        const navItems = document.querySelectorAll('.nav-item');
        navItems.forEach(item => {
            item.addEventListener('click', () => {
                playSound('click');
                navItems.forEach(n => n.classList.remove('active'));
                item.classList.add('active');

                const targetTab = item.dataset.tab;
                document.querySelectorAll('.tab-content').forEach(tab => {
                    tab.classList.toggle('active', tab.id === targetTab);
                });
            });
        });

        const btnConnect = document.getElementById('btnConnectWallet');
        if (btnConnect) btnConnect.addEventListener('click', toggleWalletConnection);

        const pairSelect = document.getElementById('pairSelect');
        if (pairSelect) {
            pairSelect.addEventListener('change', (e) => {
                playSound('click');
                const pair = e.target.value;
                state.market.selectedPair = pair;
                if (PAIR_RATES[pair]) {
                    state.market.price = PAIR_RATES[pair].price;
                }
                initChartData();
                generateOrderBook();
            });
        }

        const payInput = document.getElementById('swapPayAmount');
        const receiveInput = document.getElementById('swapReceiveAmount');
        const payTokenSelect = document.getElementById('swapPayToken');
        const receiveTokenSelect = document.getElementById('swapReceiveToken');
        const btnSwap = document.getElementById('btnExecuteSwap');
        const btnSwitchSwap = document.getElementById('btnSwitchSwapTokens');

        if (payInput) payInput.addEventListener('input', () => updateSwapAmounts('pay'));
        if (receiveInput) receiveInput.addEventListener('input', () => updateSwapAmounts('receive'));
        if (payTokenSelect) payTokenSelect.addEventListener('change', () => updateSwapAmounts('pay'));
        if (receiveTokenSelect) receiveTokenSelect.addEventListener('change', () => updateSwapAmounts('pay'));

        if (btnSwitchSwap) {
            btnSwitchSwap.addEventListener('click', () => {
                playSound('click');
                const temp = payTokenSelect.value;
                payTokenSelect.value = receiveTokenSelect.value;
                receiveTokenSelect.value = temp;
                updateSwapAmounts('pay');
            });
        }

        if (btnSwap) btnSwap.addEventListener('click', executeSwap);

        const btnClaim = document.getElementById('btnClaimRewards');
        const btnStake = document.getElementById('btnStakeOpus');

        if (btnClaim) btnClaim.addEventListener('click', executeClaimRewards);
        if (btnStake) btnStake.addEventListener('click', executeStakeOpus);

        const tfButtons = document.querySelectorAll('.tf-btn');
        tfButtons.forEach(btn => {
            btn.addEventListener('click', () => {
                playSound('click');
                tfButtons.forEach(b => b.classList.remove('active'));
                btn.classList.add('active');
                state.market.timeframe = btn.innerText;
                initChartData();
            });
        });

        window.addEventListener('resize', () => {
            renderChart();
        });
    }

    function init() {
        console.log('⚡ MAGNUM OPUS // Web3 & DeFi Engine Initialized');
        initChartData();
        generateOrderBook();
        renderWalletState();
        renderTransactions();
        renderStakingInfo();
        renderGasPrices();
        initEvents();

        marketInterval = setInterval(updateMarketPrices, 3000);
        gasInterval = setInterval(updateGasTracker, 8000);
        stakingInterval = setInterval(updateStakingRewards, 3000);
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
    } else {
        init();
    }
})();
