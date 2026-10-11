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
            balanceBtc: 0.65,
            balanceSol: 12.5,
            chainId: '0x1',
            networkName: 'Ethereum Mainnet',
            tokens: [
                { symbol: 'ETH', name: 'Ethereum', balance: 14.852, decimals: 18 },
                { symbol: 'USDT', name: 'Tether USD', balance: 42500.00, decimals: 6 },
                { symbol: 'BTC', name: 'Bitcoin', balance: 0.65, decimals: 8 },
                { symbol: 'SOL', name: 'Solana', balance: 12.5, decimals: 9 },
                { symbol: 'OPUS', name: 'Magnum Opus Governance', balance: 10000.0, decimals: 18 }
            ]
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
            asks: [],
            maxDepth: 12
        },
        transactions: [],
        portfolio: [
            { symbol: 'ETH', name: 'Ethereum', balance: 14.852, price: 3450.75, value: 51249.54, allocation: 53.8 },
            { symbol: 'BTC', name: 'Bitcoin', balance: 0.65, price: 64200.00, value: 41730.00, allocation: 43.8 },
            { symbol: 'SOL', name: 'Solana', balance: 12.5, price: 145.20, value: 1815.00, allocation: 1.9 },
            { symbol: 'OPUS', name: 'Magnum Opus', balance: 1000.0, price: 0.45, value: 450.00, allocation: 0.5 }
        ],
        staking: {
            stakedOpus: 2500.0,
            rewardRateApy: 18.5,
            pendingRewards: 14.82
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

    // Chart instance
    let priceChart = null;

    // Tickers & intervals
    let marketInterval = null;
    let gasInterval = null;
    let orderBookInterval = null;

    // Audio context for sound effects
    let audioCtx = null;

    /**
     * Initialization
     */
    function init() {
        loadPersistedSettings();
        initDOM();
        initChartData();
        setupEventListeners();
        initializeChart();
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
            txList: document.getElementById('transaction-history-list'),
            swapFromAmount: document.getElementById('swap-from-amount'),
            swapToAmount: document.getElementById('swap-to-amount'),
            swapFromToken: document.getElementById('swap-from-token'),
            swapToToken: document.getElementById('swap-to-token'),
            swapBtn: document.getElementById('execute-swap-btn'),
            chartCanvas: document.getElementById('price-chart-canvas'),
            notificationContainer: document.getElementById('notification-container'),
            portfolioTable: document.getElementById('portfolio-table-body'),
            themeToggle: document.getElementById('theme-toggle'),
            settingsModal: document.getElementById('settings-modal'),
            settingsForm: document.getElementById('settings-form'),
            modalClose: document.querySelectorAll('.modal-close'),
            openSettingsBtn: document.getElementById('open-settings-btn'),
            stakedBalance: document.getElementById('staked-balance-display'),
            claimRewardsBtn: document.getElementById('claim-rewards-btn'),
            slippageInput: document.getElementById('slippage-tolerance-input')
        };
    }

    function initChartData() {
        const points = 30;
        let current = state.market.price;
        const now = Date.now();
        state.market.chartData.labels = [];
        state.market.chartData.prices = [];

        for (let i = points; i >= 0; i--) {
            const time = new Date(now - i * 60000);
            const timeStr = time.getHours().toString().padStart(2, '0') + ':' + time.getMinutes().toString().padStart(2, '0');
            const delta = (Math.random() - 0.49) * (current * 0.008);
            current = Math.max(current + delta, 10);
            state.market.chartData.labels.push(timeStr);
            state.market.chartData.prices.push(parseFloat(current.toFixed(2)));
        }
    }

    function setupEventListeners() {
        if (DOM.connectBtn) DOM.connectBtn.addEventListener('click', toggleWalletConnection);
        if (DOM.pairSelect) DOM.pairSelect.addEventListener('change', updateMarketPair);
        if (DOM.swapBtn) DOM.swapBtn.addEventListener('click', executeSwap);
        if (DOM.swapFromAmount) DOM.swapFromAmount.addEventListener('input', calculateSwap);
        if (DOM.swapFromToken) DOM.swapFromToken.addEventListener('change', calculateSwap);
        if (DOM.swapToToken) DOM.swapToToken.addEventListener('change', calculateSwap);
        if (DOM.themeToggle) DOM.themeToggle.addEventListener('click', toggleTheme);
        if (DOM.settingsForm) DOM.settingsForm.addEventListener('submit', saveSettings);
        if (DOM.openSettingsBtn) DOM.openSettingsBtn.addEventListener('click', () => openModal(DOM.settingsModal));
        if (DOM.claimRewardsBtn) DOM.claimRewardsBtn.addEventListener('click', claimStakingRewards);

        if (DOM.modalClose) {
            DOM.modalClose.forEach(btn => {
                btn.addEventListener('click', () => {
                    const modal = btn.closest('.modal') || DOM.settingsModal;
                    closeModal(modal);
                });
            });
        }

        window.addEventListener('keydown', (e) => {
            if (e.key === 'Escape' && DOM.settingsModal) {
                closeModal(DOM.settingsModal);
            }
        });
    }

    function playTone(freq, type = 'sine', duration = 0.1) {
        if (!state.settings.enableSounds) return;
        try {
            if (!audioCtx) {
                const AudioContextClass = window.AudioContext || window.webkitAudioContext;
                if (AudioContextClass) audioCtx = new AudioContextClass();
            }
            if (audioCtx && audioCtx.state === 'suspended') {
                audioCtx.resume();
            }
            if (!audioCtx) return;
            const osc = audioCtx.createOscillator();
            const gain = audioCtx.createGain();
            osc.type = type;
            osc.frequency.setValueAtTime(freq, audioCtx.currentTime);
            gain.gain.setValueAtTime(0.08, audioCtx.currentTime);
            gain.gain.exponentialRampToValueAtTime(0.0001, audioCtx.currentTime + duration);
            osc.connect(gain);
            gain.connect(audioCtx.destination);
            osc.start();
            osc.stop(audioCtx.currentTime + duration);
        } catch (e) {
            // Audio disabled or unsupported in environment
        }
    }

    /**
     * Web3 Provider & Wallet Logic
     */
    async function toggleWalletConnection() {
        if (state.wallet.connected) {
            disconnectWallet();
        } else {
            await connectWallet();
        }
    }

    async function connectWallet() {
        if (window.ethereum) {
            try {
                const accounts = await window.ethereum.request({ method: 'eth_requestAccounts' });
                if (accounts && accounts.length > 0) {
                    state.wallet.address = accounts[0];
                    state.wallet.connected = true;
                    const chainId = await window.ethereum.request({ method: 'eth_chainId' });
                    state.wallet.chainId = chainId;
                    updateNetworkName(chainId);
                    addNotification('Wallet Connected', `Connected to ${shortenAddress(accounts[0])}`, 'success');
                    playTone(660);
                    updateUI();
                    return;
                }
            } catch (err) {
                console.warn('User rejected or error requesting Web3 accounts, falling back to simulated wallet:', err);
            }
        }

        // Fallback: Simulated Web3 Wallet
        state.wallet.address = '0x71C840502123737b57b15e7f5399f7d2073998F6';
        state.wallet.connected = true;
        state.wallet.networkName = 'Magnum Opus L2 Mainnet';
        addNotification('Simulated Wallet Attached', `Active address: ${shortenAddress(state.wallet.address)}`, 'success');
        playTone(520);
        updateUI();
    }

    function disconnectWallet() {
        state.wallet.connected = false;
        state.wallet.address = null;
        addNotification('Wallet Disconnected', 'Disconnected from Web3 provider.', 'info');
        playTone(330);
        updateUI();
    }

    function updateNetworkName(chainId) {
        switch (chainId) {
            case '0x1': state.wallet.networkName = 'Ethereum Mainnet'; break;
            case '0x5': state.wallet.networkName = 'Goerli Testnet'; break;
            case '0xaa36a7': state.wallet.networkName = 'Sepolia Testnet'; break;
            case '0x89': state.wallet.networkName = 'Polygon PoS'; break;
            case '0xa4b1': state.wallet.networkName = 'Arbitrum One'; break;
            default: state.wallet.networkName = 'Custom Network (' + chainId + ')'; break;
        }
    }

    function setupWeb3Listeners() {
        if (window.ethereum) {
            window.ethereum.on('accountsChanged', (accounts) => {
                if (accounts && accounts.length > 0) {
                    state.wallet.address = accounts[0];
                    state.wallet.connected = true;
                    addNotification('Account Changed', `Switched to ${shortenAddress(accounts[0])}`, 'info');
                } else {
                    state.wallet.connected = false;
                    state.wallet.address = null;
                    addNotification('Account Disconnected', 'Provider disconnected accounts', 'warning');
                }
                updateUI();
            });

            window.ethereum.on('chainChanged', (chainId) => {
                state.wallet.chainId = chainId;
                updateNetworkName(chainId);
                addNotification('Network Changed', `Switched to ${state.wallet.networkName}`, 'info');
                updateUI();
            });
        }
    }

    function shortenAddress(addr) {
        if (!addr) return '';
        return addr.slice(0, 6) + '...' + addr.slice(-4);
    }

    /**
     * Chart Canvas Engine (Chart.js or Canvas 2D fallback)
     */
    function initializeChart() {
        if (!DOM.chartCanvas) return;
        const ctx = DOM.chartCanvas.getContext('2d');

        if (typeof Chart !== 'undefined') {
            priceChart = new Chart(ctx, {
                type: 'line',
                data: {
                    labels: state.market.chartData.labels,
                    datasets: [{
                        label: state.market.selectedPair,
                        data: state.market.chartData.prices,
                        borderColor: '#38bdf8',
                        backgroundColor: 'rgba(56, 189, 248, 0.08)',
                        borderWidth: 2,
                        fill: true,
                        tension: 0.35,
                        pointRadius: 0,
                        pointHoverRadius: 4,
                        pointHoverBackgroundColor: '#a855f7'
                    }]
                },
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    interaction: {
                        intersect: false,
                        mode: 'index'
                    },
                    scales: {
                        x: {
                            grid: { display: false, color: 'rgba(255,255,255,0.05)' },
                            ticks: { color: '#64748b', maxTicksLimit: 6, font: { size: 10 } }
                        },
                        y: {
                            position: 'right',
                            grid: { color: 'rgba(255,255,255,0.05)' },
                            ticks: { color: '#64748b', font: { size: 10 } }
                        }
                    },
                    plugins: {
                        legend: { display: false },
                        tooltip: {
                            backgroundColor: '#0a0f24',
                            borderColor: '#38bdf8',
                            borderWidth: 1,
                            titleColor: '#94a3b8',
                            bodyColor: '#38bdf8',
                            displayColors: false
                        }
                    }
                }
            });
        } else {
            // Fallback direct 2D canvas chart renderer
            renderFallbackCanvasChart(ctx);
        }
    }

    function renderFallbackCanvasChart(ctx) {
        if (!ctx) return;
        const canvas = ctx.canvas;
        const w = canvas.width = canvas.parentElement ? canvas.parentElement.clientWidth : 600;
        const h = canvas.height = canvas.parentElement ? canvas.parentElement.clientHeight : 260;
        const prices = state.market.chartData.prices;
        if (prices.length < 2) return;

        ctx.clearRect(0, 0, w, h);

        const min = Math.min(...prices) * 0.998;
        const max = Math.max(...prices) * 1.002;
        const range = max - min || 1;

        ctx.beginPath();
        for (let i = 0; i < prices.length; i++) {
            const x = (i / (prices.length - 1)) * (w - 40) + 10;
            const y = h - ((prices[i] - min) / range) * (h - 30) - 15;
            if (i === 0) ctx.moveTo(x, y);
            else ctx.lineTo(x, y);
        }
        ctx.strokeStyle = '#38bdf8';
        ctx.lineWidth = 2;
        ctx.stroke();

        // Area fill
        ctx.lineTo((w - 40) + 10, h);
        ctx.lineTo(10, h);
        ctx.closePath();
        const grad = ctx.createLinearGradient(0, 0, 0, h);
        grad.addColorStop(0, 'rgba(56, 189, 248, 0.25)');
        grad.addColorStop(1, 'rgba(56, 189, 248, 0.0)');
        ctx.fillStyle = grad;
        ctx.fill();
    }

    function updateChart(newPrice) {
        const now = new Date();
        const timeStr = now.getHours().toString().padStart(2, '0') + ':' + now.getMinutes().toString().padStart(2, '0');
        state.market.chartData.labels.push(timeStr);
        state.market.chartData.prices.push(newPrice);

        if (state.market.chartData.labels.length > 40) {
            state.market.chartData.labels.shift();
            state.market.chartData.prices.shift();
        }

        if (priceChart) {
            priceChart.data.labels = state.market.chartData.labels;
            priceChart.data.datasets[0].data = state.market.chartData.prices;
            priceChart.data.datasets[0].label = state.market.selectedPair;
            priceChart.update('none');
        } else if (DOM.chartCanvas) {
            renderFallbackCanvasChart(DOM.chartCanvas.getContext('2d'));
        }
    }

    /**
     * Market & Order Book Simulation Engine
     */
    function populateOrderBook() {
        const p = state.market.price;
        state.orderBook.bids = [];
        state.orderBook.asks = [];

        for (let i = 1; i <= state.orderBook.maxDepth; i++) {
            const bidPrice = p * (1 - (i * 0.0008 + Math.random() * 0.0003));
            const askPrice = p * (1 + (i * 0.0008 + Math.random() * 0.0003));
            const bidAmt = parseFloat((Math.random() * 2.8 + 0.15).toFixed(4));
            const askAmt = parseFloat((Math.random() * 2.8 + 0.15).toFixed(4));
            state.orderBook.bids.push({ price: bidPrice, amount: bidAmt, total: bidPrice * bidAmt });
            state.orderBook.asks.push({ price: askPrice, amount: askAmt, total: askPrice * askAmt });
        }
        state.orderBook.asks.sort((a, b) => b.price - a.price);
        state.orderBook.bids.sort((a, b) => b.price - a.price);
    }

    function renderOrderBook() {
        if (DOM.orderBookAsks) {
            DOM.orderBookAsks.innerHTML = state.orderBook.asks.map(item => `
                <div class="orderbook-row ask flex justify-between py-1 px-2 text-xs hover:bg-red-500/10 cursor-pointer">
                    <span class="text-red-400 font-mono">${item.price.toFixed(2)}</span>
                    <span class="text-slate-300 font-mono">${item.amount.toFixed(4)}</span>
                    <span class="text-slate-500 font-mono">${(item.total).toFixed(1)}</span>
                </div>
            `).join('');
        }

        if (DOM.orderBookBids) {
            DOM.orderBookBids.innerHTML = state.orderBook.bids.map(item => `
                <div class="orderbook-row bid flex justify-between py-1 px-2 text-xs hover:bg-emerald-500/10 cursor-pointer">
                    <span class="text-emerald-400 font-mono">${item.price.toFixed(2)}</span>
                    <span class="text-slate-300 font-mono">${item.amount.toFixed(4)}</span>
                    <span class="text-slate-500 font-mono">${(item.total).toFixed(1)}</span>
                </div>
            `).join('');
        }
    }

    function startSimulationEngines() {
        // Live market tick
        marketInterval = setInterval(() => {
            const delta = (Math.random() - 0.495) * (state.market.price * 0.0035);
            const newPrice = Math.max(state.market.price + delta, 0.0001);
            state.market.price = parseFloat(newPrice.toFixed(4));

            // Recalculate 24h change slightly
            state.market.change24h = parseFloat((state.market.change24h + (delta / state.market.price) * 10).toFixed(2));
            updateMarketDisplays();
            updateChart(state.market.price);
            populateOrderBook();
            renderOrderBook();
        }, state.settings.autoRefreshInterval);

        // Gas price fluctuation simulation
        gasInterval = setInterval(() => {
            const gasDelta = Math.floor((Math.random() * 5) - 2);
            state.gas.current = Math.max(8, state.gas.current + gasDelta);
            if (DOM.gasPrice) {
                DOM.gasPrice.textContent = `${state.gas.current} Gwei`;
            }
        }, 5000);

        // Staking incremental accrual
        setInterval(() => {
            if (state.staking.stakedOpus > 0) {
                const annualFraction = (state.settings.autoRefreshInterval / 1000) / (365 * 86400);
                const reward = state.staking.stakedOpus * (state.staking.rewardRateApy / 100) * annualFraction;
                state.staking.pendingRewards += reward;
                if (DOM.stakedBalance) {
                    DOM.stakedBalance.textContent = state.staking.pendingRewards.toFixed(6) + ' OPUS';
                }
            }
        }, 2000);
    }

    function updateMarketDisplays() {
        if (DOM.currentPrice) {
            DOM.currentPrice.textContent = `$${state.market.price.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 4 })}`;
        }
        if (DOM.priceChange) {
            const isPositive = state.market.change24h >= 0;
            DOM.priceChange.textContent = `${isPositive ? '+' : ''}${state.market.change24h}%`;
            DOM.priceChange.className = `price-change font-semibold ${isPositive ? 'text-emerald-400' : 'text-rose-400'}`;
        }
    }

    function updateMarketPair() {
        if (!DOM.pairSelect) return;
        const pair = DOM.pairSelect.value;
        if (PAIR_RATES[pair]) {
            state.market.selectedPair = pair;
            state.market.price = PAIR_RATES[pair].price;
            state.market.change24h = (Math.random() * 8 - 4);
            initChartData();
            updateMarketDisplays();
            if (priceChart) {
                priceChart.data.labels = state.market.chartData.labels;
                priceChart.data.datasets[0].data = state.market.chartData.prices;
                priceChart.data.datasets[0].label = pair;
                priceChart.update();
            }
            populateOrderBook();
            renderOrderBook();
            addNotification('Market Pair Changed', `Switched to active trading pair ${pair}`, 'info');
        }
    }

    /**
     * AMM Swap Engine (Constant Product Formula with Slippage & Fee)
     */
    function calculateSwap() {
        if (!DOM.swapFromAmount || !DOM.swapToAmount) return;
        const inAmt = parseFloat(DOM.swapFromAmount.value);
        if (isNaN(inAmt) || inAmt <= 0) {
            DOM.swapToAmount.value = '';
            return;
        }

        const fromToken = DOM.swapFromToken ? DOM.swapFromToken.value : 'ETH';
        const toToken = DOM.swapToToken ? DOM.swapToToken.value : 'USDT';

        if (fromToken === toToken) {
            DOM.swapToAmount.value = inAmt.toString();
            return;
        }

        // Approximate pricing via USDT standard intermediary
        const getPriceInUsdt = (token) => {
            if (token === 'USDT') return 1;
            if (token === 'ETH') return state.market.price;
            if (token === 'BTC') return 64200;
            if (token === 'SOL') return 145.2;
            if (token === 'OPUS') return 0.45;
            return 1;
        };

        const fromUsdt = getPriceInUsdt(fromToken);
        const toUsdt = getPriceInUsdt(toToken);
        const swapFee = 0.003; // 0.3% LP fee
        const grossTo = (inAmt * fromUsdt) / toUsdt;
        const netTo = grossTo * (1 - swapFee);

        DOM.swapToAmount.value = netTo.toFixed(4);
    }

    async function executeSwap() {
        const inAmt = parseFloat(DOM.swapFromAmount ? DOM.swapFromAmount.value : '0');
        const outAmt = parseFloat(DOM.swapToAmount ? DOM.swapToAmount.value : '0');
        const fromToken = DOM.swapFromToken ? DOM.swapFromToken.value : 'ETH';
        const toToken = DOM.swapToToken ? DOM.swapToToken.value : 'USDT';

        if (isNaN(inAmt) || inAmt <= 0) {
            addNotification('Swap Failed', 'Please enter a valid amount to swap.', 'error');
            return;
        }

        if (DOM.swapBtn) {
            DOM.swapBtn.disabled = true;
            DOM.swapBtn.innerText = 'Transacting On-Chain...';
        }

        playTone(440, 'triangle', 0.15);

        // Simulate on-chain confirmation delay
        setTimeout(() => {
            const txHash = '0x' + Array.from({ length: 64 }, () => Math.floor(Math.random() * 16).toString(16)).join('');
            const newTx = {
                hash: txHash,
                type: `Swap ${fromToken} for ${toToken}`,
                amount: `${inAmt} ${fromToken} -> ${outAmt} ${toToken}`,
                timestamp: new Date().toLocaleTimeString(),
                status: 'Confirmed'
            };
            state.transactions.unshift(newTx);
            if (state.transactions.length > 20) state.transactions.pop();

            renderTransactions();
            addNotification('Swap Executed', `Swapped ${inAmt} ${fromToken} for ${outAmt} ${toToken}`, 'success');
            playTone(880, 'sine', 0.25);

            if (DOM.swapBtn) {
                DOM.swapBtn.disabled = false;
                DOM.swapBtn.innerText = 'Execute Swap';
            }
            if (DOM.swapFromAmount) DOM.swapFromAmount.value = '';
            if (DOM.swapToAmount) DOM.swapToAmount.value = '';
        }, 1200);
    }

    function claimStakingRewards() {
        if (state.staking.pendingRewards <= 0) {
            addNotification('No Rewards', 'Pending rewards are currently zero.', 'warning');
            return;
        }
        const claimed = state.staking.pendingRewards.toFixed(4);
        state.staking.pendingRewards = 0;
        addNotification('Rewards Claimed', `Successfully claimed ${claimed} OPUS into your wallet!`, 'success');
        playTone(740, 'triangle', 0.3);
        if (DOM.stakedBalance) {
            DOM.stakedBalance.textContent = '0.000000 OPUS';
        }
    }

    /**
     * Portfolio & Transaction Renderers
     */
    function renderPortfolio() {
        if (!DOM.portfolioTable) return;
        const totalValue = state.portfolio.reduce((sum, item) => sum + item.value, 0);
        DOM.portfolioTable.innerHTML = state.portfolio.map(item => `
            <tr class="border-b border-slate-800/60 hover:bg-slate-800/30 transition-colors text-sm">
                <td class="py-3 px-4 font-semibold text-white flex items-center space-x-2">
                    <span class="w-2 h-2 rounded-full bg-cyan-400 inline-block"></span>
                    <span>${item.name} (${item.symbol})</span>
                </td>
                <td class="py-3 px-4 font-mono text-slate-300">${item.balance.toLocaleString()} ${item.symbol}</td>
                <td class="py-3 px-4 font-mono text-slate-300">$${item.price.toLocaleString(undefined, { minimumFractionDigits: 2 })}</td>
                <td class="py-3 px-4 font-mono font-medium text-white">$${item.value.toLocaleString(undefined, { minimumFractionDigits: 2 })}</td>
                <td class="py-3 px-4 font-mono text-cyan-400">${((item.value / totalValue) * 100).toFixed(1)}%</td>
            </tr>
        `).join('');
    }

    function renderTransactions() {
        if (!DOM.txList) return;
        if (state.transactions.length === 0) {
            DOM.txList.innerHTML = '<li class="text-slate-500 py-3 text-center text-xs">No transactions yet.</li>';
            return;
        }
        DOM.txList.innerHTML = state.transactions.map(tx => `
            <li class="py-2 px-3 border-b border-slate-800/50 flex items-center justify-between text-xs hover:bg-slate-800/20">
                <div class="flex flex-col">
                    <span class="font-medium text-slate-200">${tx.type}</span>
                    <span class="text-[10px] text-slate-500 font-mono">${tx.hash.slice(0, 10)}...${tx.hash.slice(-8)}</span>
                </div>
                <div class="flex flex-col items-end">
                    <span class="text-cyan-400 font-mono">${tx.amount}</span>
                    <span class="text-[10px] text-emerald-400">${tx.status} • ${tx.timestamp}</span>
                </div>
            </li>
        `).join('');
    }

    /**
     * Toast Notification System
     */
    function addNotification(title, message, type = 'info') {
        const id = 'notif_' + Date.now() + '_' + Math.floor(Math.random() * 1000);
        const notif = { id, title, message, type };
        state.notifications.push(notif);

        if (!DOM.notificationContainer) {
            let container = document.getElementById('notification-container');
            if (!container) {
                container = document.createElement('div');
                container.id = 'notification-container';
                container.className = 'fixed bottom-5 right-5 z-50 flex flex-col space-y-2 pointer-events-none';
                document.body.appendChild(container);
            }
            DOM.notificationContainer = container;
        }

        const elem = document.createElement('div');
        const borderColors = {
            info: 'border-cyan-500 bg-slate-900/90 text-slate-100',
            success: 'border-emerald-500 bg-slate-900/90 text-slate-100',
            warning: 'border-amber-500 bg-slate-900/90 text-slate-100',
            error: 'border-rose-500 bg-slate-900/90 text-slate-100'
        };
        elem.className = `p-3.5 rounded-lg border shadow-xl backdrop-blur-md pointer-events-auto transform transition-all duration-300 ease-out max-w-sm ${borderColors[type] || borderColors.info}`;
        elem.innerHTML = `
            <div class="flex justify-between items-start">
                <h4 class="font-semibold text-xs tracking-wide uppercase">${title}</h4>
                <button class="text-slate-400 hover:text-white ml-2 text-xs">&times;</button>
            </div>
            <p class="text-xs mt-1 text-slate-300 leading-snug">${message}</p>
        `;

        const closeBtn = elem.querySelector('button');
        closeBtn.onclick = () => removeNotifElem(elem, id);

        DOM.notificationContainer.appendChild(elem);

        setTimeout(() => {
            removeNotifElem(elem, id);
        }, 5000);
    }

    function removeNotifElem(elem, id) {
        elem.classList.add('opacity-0', 'translate-x-4');
        setTimeout(() => {
            if (elem.parentNode) elem.parentNode.removeChild(elem);
            state.notifications = state.notifications.filter(n => n.id !== id);
        }, 300);
    }

    /**
     * UI State Sync & Modal Handlers
     */
    function updateUI() {
        if (DOM.connectBtn) {
            if (state.wallet.connected) {
                DOM.connectBtn.textContent = shortenAddress(state.wallet.address);
                DOM.connectBtn.classList.add('connected');
            } else {
                DOM.connectBtn.textContent = 'Connect Wallet';
                DOM.connectBtn.classList.remove('connected');
            }
        }

        if (DOM.walletAddress) {
            DOM.walletAddress.textContent = state.wallet.connected ? state.wallet.address : 'Not Connected';
        }

        if (DOM.walletBalance) {
            DOM.walletBalance.textContent = state.wallet.connected ? `${state.wallet.balanceEth.toFixed(4)} ETH` : '--';
        }

        updateMarketDisplays();
    }

    function toggleTheme() {
        state.settings.theme = state.settings.theme === 'dark' ? 'light' : 'dark';
        document.documentElement.setAttribute('data-theme', state.settings.theme);
        saveSettingsToStorage();
        addNotification('Theme Changed', `Theme updated to ${state.settings.theme} mode.`, 'info');
    }

    function openModal(modal) {
        if (modal) {
            modal.classList.remove('hidden');
            modal.classList.add('flex');
        }
    }

    function closeModal(modal) {
        if (modal) {
            modal.classList.add('hidden');
            modal.classList.remove('flex');
        }
    }

    function saveSettings(e) {
        if (e) e.preventDefault();
        if (DOM.slippageInput) {
            const val = parseFloat(DOM.slippageInput.value);
            if (!isNaN(val) && val > 0 && val <= 50) {
                state.settings.slippageTolerance = val;
            }
        }
        saveSettingsToStorage();
        if (DOM.settingsModal) closeModal(DOM.settingsModal);
        addNotification('Settings Saved', 'Platform preferences updated successfully.', 'success');
    }

    // Expose core interface globally for integration
    window.MagnumOpusApp = {
        state,
        connectWallet,
        disconnectWallet,
        executeSwap,
        addNotification,
        updateMarketPair
    };

    // Bootstrap on DOM ready
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
    } else {
        init();
    }
})();
