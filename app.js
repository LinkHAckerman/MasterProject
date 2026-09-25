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
        ]
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
            chartCanvas: document.getElementById('price-chart-canvas')
        };
    }

    // Canvas Chart Rendering Engine
    class ChartEngine {
        constructor(canvas) {
            this.canvas = canvas;
            this.ctx = canvas ? canvas.getContext('2d') : null;
            this.dataPoints = [];
            this.generateHistoricalData();
        }

        generateHistoricalData() {
            let basePrice = 3400;
            const now = Date.now();
            for (let i = 50; i >= 0; i--) {
                const time = now - i * 60000 * 5;
                const variation = (Math.random() - 0.48) * 15;
                basePrice += variation;
                this.dataPoints.push({ time, price: basePrice });
            }
        }

        addPoint(price) {
            this.dataPoints.push({ time: Date.now(), price });
            if (this.dataPoints.length > 60) this.dataPoints.shift();
            this.render();
        }

        render() {
            if (!this.canvas || !this.ctx) return;
            const width = this.canvas.width = this.canvas.parentElement ? this.canvas.parentElement.clientWidth : 600;
            const height = this.canvas.height = 300;
            const ctx = this.ctx;

            ctx.clearRect(0, 0, width, height);

            if (this.dataPoints.length < 2) return;

            const prices = this.dataPoints.map(p => p.price);
            const minPrice = Math.min(...prices) * 0.998;
            const maxPrice = Math.max(...prices) * 1.002;
            const priceRange = maxPrice - minPrice || 1;

            // Draw Grid
            ctx.strokeStyle = 'rgba(56, 189, 248, 0.08)';
            ctx.lineWidth = 1;
            for (let y = 0; y < height; y += 50) {
                ctx.beginPath();
                ctx.moveTo(0, y);
                ctx.lineTo(width, y);
                ctx.stroke();
            }

            // Draw Gradient Area
            const gradient = ctx.createLinearGradient(0, 0, 0, height);
            gradient.addColorStop(0, 'rgba(56, 189, 248, 0.35)');
            gradient.addColorStop(1, 'rgba(56, 189, 248, 0.0)');

            ctx.beginPath();
            const stepX = width / (this.dataPoints.length - 1);

            this.dataPoints.forEach((pt, idx) => {
                const x = idx * stepX;
                const y = height - ((pt.price - minPrice) / priceRange) * height;
                if (idx === 0) ctx.moveTo(x, y);
                else ctx.lineTo(x, y);
            });

            ctx.strokeStyle = '#38bdf8';
            ctx.lineWidth = 2;
            ctx.stroke();

            // Close Path for Gradient Fill
            ctx.lineTo(width, height);
            ctx.lineTo(0, height);
            ctx.closePath();
            ctx.fillStyle = gradient;
            ctx.fill();
        }
    }

    let chartInstance = null;

    // Orderbook Simulation Engine
    function updateOrderBook() {
        const basePrice = state.market.price;
        const asks = [];
        const bids = [];

        for (let i = 1; i <= 6; i++) {
            const askPrice = (basePrice + i * 0.85 + Math.random() * 0.3).toFixed(2);
            const askAmount = (Math.random() * 2.5 + 0.1).toFixed(4);
            asks.unshift({ price: askPrice, amount: askAmount, total: (askPrice * askAmount).toFixed(2) });

            const bidPrice = (basePrice - i * 0.85 - Math.random() * 0.3).toFixed(2);
            const bidAmount = (Math.random() * 2.5 + 0.1).toFixed(4);
            bids.push({ price: bidPrice, amount: bidAmount, total: (bidPrice * bidAmount).toFixed(2) });
        }

        state.orderBook.asks = asks;
        state.orderBook.bids = bids;

        renderOrderBook();
    }

    function renderOrderBook() {
        if (DOM.orderBookAsks) {
            DOM.orderBookAsks.innerHTML = state.orderBook.asks.map(a => `
                <div class="ob-row ask" style="display:flex; justify-content:space-between; padding:2px 0; color:#f43f5e; font-family:var(--font-mono); font-size:0.85rem;">
                    <span>${a.price}</span>
                    <span>${a.amount}</span>
                    <span>${a.total}</span>
                </div>
            `).join('');
        }

        if (DOM.orderBookBids) {
            DOM.orderBookBids.innerHTML = state.orderBook.bids.map(b => `
                <div class="ob-row bid" style="display:flex; justify-content:space-between; padding:2px 0; color:#10b981; font-family:var(--font-mono); font-size:0.85rem;">
                    <span>${b.price}</span>
                    <span>${b.amount}</span>
                    <span>${b.total}</span>
                </div>
            `).join('');
        }
    }

    // Live Data Feed Simulation
    function startTickerLoop() {
        setInterval(() => {
            const delta = (Math.random() - 0.49) * 4.5;
            state.market.price = Math.max(100, +(state.market.price + delta).toFixed(2));
            state.gas.current = Math.floor(15 + Math.random() * 12);

            if (DOM.currentPrice) {
                DOM.currentPrice.textContent = `$${state.market.price.toLocaleString('en-US', { minimumFractionDigits: 2 })}`;
            }

            if (DOM.gasPrice) {
                DOM.gasPrice.textContent = `${state.gas.current} Gwei`;
            }

            if (chartInstance) {
                chartInstance.addPoint(state.market.price);
            }

            updateOrderBook();
        }, 3000);
    }

    // Wallet Integration Engine
    function setupWalletHandlers() {
        if (!DOM.connectBtn) return;

        DOM.connectBtn.addEventListener('click', async () => {
            if (state.wallet.connected) {
                // Disconnect logic
                state.wallet.connected = false;
                state.wallet.address = null;
                DOM.connectBtn.textContent = 'Connect Wallet';
                if (DOM.walletAddress) DOM.walletAddress.textContent = 'Not Connected';
                showNotification('Wallet disconnected', 'info');
            } else {
                // Connect logic (Simulated Web3 Provider)
                DOM.connectBtn.textContent = 'Connecting...';
                setTimeout(() => {
                    state.wallet.connected = true;
                    state.wallet.address = '0x71C...39A2';
                    DOM.connectBtn.textContent = '0x71C...39A2';
                    if (DOM.walletAddress) DOM.walletAddress.textContent = '0x71C7656EC7ab88b098defB751B7401B5f6d839A2';
                    showNotification('Wallet connected successfully!', 'success');
                }, 800);
            }
        });
    }

    // Swap Engine Logic
    function setupSwapEngine() {
        if (!DOM.swapFromAmount || !DOM.swapToAmount || !DOM.swapBtn) return;

        DOM.swapFromAmount.addEventListener('input', (e) => {
            const val = parseFloat(e.target.value) || 0;
            const estimatedTo = (val * (state.market.price / 1.001)).toFixed(2);
            DOM.swapToAmount.value = estimatedTo > 0 ? estimatedTo : '';
        });

        DOM.swapBtn.addEventListener('click', () => {
            const amount = parseFloat(DOM.swapFromAmount.value);
            if (!amount || amount <= 0) {
                showNotification('Please enter a valid swap amount', 'warning');
                return;
            }

            if (!state.wallet.connected) {
                showNotification('Connect wallet to execute swap', 'warning');
                return;
            }

            const txHash = '0x' + Array.from({length: 64}, () => Math.floor(Math.random()*16).toString(16)).join('');
            addTransactionRecord({
                hash: txHash,
                type: 'SWAP',
                description: `Swapped ${amount} ETH for ${(amount * state.market.price).toFixed(2)} USDT`,
                status: 'Confirmed',
                time: new Date().toLocaleTimeString()
            });

            showNotification(`Swap executed! Tx: ${txHash.substring(0, 10)}...`, 'success');
            DOM.swapFromAmount.value = '';
            DOM.swapToAmount.value = '';
        });
    }

    // Notification System
    function showNotification(message, type = 'info') {
        const toast = document.createElement('div');
        toast.className = `toast toast-${type}`;
        toast.style.position = 'fixed';
        toast.style.bottom = '20px';
        toast.style.right = '20px';
        toast.style.padding = '12px 24px';
        toast.style.borderRadius = '8px';
        toast.style.color = '#fff';
        toast.style.fontWeight = '600';
        toast.style.zIndex = '9999';
        toast.style.boxShadow = '0 10px 25px rgba(0,0,0,0.5)';
        toast.style.backdropFilter = 'blur(10px)';
        toast.style.transition = 'all 0.3s ease';

        if (type === 'success') toast.style.background = 'rgba(16, 185, 129, 0.9)';
        else if (type === 'warning') toast.style.background = 'rgba(245, 158, 11, 0.9)';
        else if (type === 'error') toast.style.background = 'rgba(244, 63, 94, 0.9)';
        else toast.style.background = 'rgba(56, 189, 248, 0.9)';

        toast.textContent = message;
        document.body.appendChild(toast);

        setTimeout(() => {
            toast.style.opacity = '0';
            toast.style.transform = 'translateY(10px)';
            setTimeout(() => toast.remove(), 300);
        }, 3500);
    }

    // Transaction Logging
    function addTransactionRecord(tx) {
        state.transactions.unshift(tx);
        if (state.transactions.length > 10) state.transactions.pop();
        renderTransactions();
    }

    function renderTransactions() {
        if (!DOM.txList) return;

        DOM.txList.innerHTML = state.transactions.map(tx => `
            <div class="tx-item" style="display:flex; justify-content:space-between; align-items:center; padding:10px; border-bottom:1px solid rgba(56, 189, 248, 0.1); font-size:0.85rem;">
                <div>
                    <span style="font-weight:700; color:var(--accent-cyan);">${tx.type}</span>
                    <span style="color:var(--text-muted); margin-left:8px;">${tx.description}</span>
                </div>
                <div style="text-align:right;">
                    <span style="color:var(--accent-emerald); font-weight:600;">${tx.status}</span>
                    <div style="color:var(--text-muted); font-size:0.75rem;">${tx.time}</div>
                </div>
            </div>
        `).join('');
    }

    // Window Resize Handler
    function setupResizeListener() {
        window.addEventListener('resize', () => {
            if (chartInstance) chartInstance.render();
        });
    }

    // App Initialization Entrypoint
    document.addEventListener('DOMContentLoaded', () => {
        initDOM();
        if (DOM.chartCanvas) {
            chartInstance = new ChartEngine(DOM.chartCanvas);
            chartInstance.render();
        }
        updateOrderBook();
        startTickerLoop();
        setupWalletHandlers();
        setupSwapEngine();
        setupResizeListener();
    });

})();