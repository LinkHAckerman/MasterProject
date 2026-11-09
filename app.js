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
            balanceOpus: 10000.0,
            chainId: '0x1',
            networkName: 'Ethereum Mainnet',
            tokens: [
                { symbol: 'ETH', name: 'Ethereum', balance: 14.852, decimals: 18, price: 3450.75, icon: 'Ξ' },
                { symbol: 'USDT', name: 'Tether USD', balance: 42500.00, decimals: 6, price: 1.00, icon: '₮' },
                { symbol: 'BTC', name: 'Bitcoin', balance: 0.65, decimals: 8, price: 64200.00, icon: '₿' },
                { symbol: 'SOL', name: 'Solana', balance: 12.5, decimals: 9, price: 145.20, icon: '◎' },
                { symbol: 'OPUS', name: 'Magnum Opus Governance', balance: 10000.0, decimals: 18, price: 0.45, icon: '❖' }
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
                prices: []
            }
        },
        orderBook: {
            bids: [],
            asks: [],
            maxDepth: 12
        },
        swap: {
            fromToken: 'ETH',
            toToken: 'USDT',
            fromAmount: '',
            toAmount: '',
            slippage: 0.5,
            priceImpact: 0.04
        },
        staking: {
            stakedOpus: 2500.0,
            rewardRateApy: 18.5,
            pendingRewards: 14.82,
            lastClaimed: Date.now() - 432000000
        },
        nfts: [
            {
                id: 1,
                name: 'Cyber Opus #001',
                collection: 'Opus Genesis',
                price: '2.5 ETH',
                priceVal: 2.5,
                rarity: 'Legendary',
                attributes: [
                    { trait: 'Background', value: 'Neon Nebula' },
                    { trait: 'Core', value: 'Quantum Heart' }
                ]
            },
            {
                id: 2,
                name: 'Cyber Opus #042',
                collection: 'Opus Genesis',
                price: '1.2 ETH',
                priceVal: 1.2,
                rarity: 'Rare',
                attributes: [
                    { trait: 'Background', value: 'Deep Cyber' },
                    { trait: 'Core', value: 'Plasma Engine' }
                ]
            },
            {
                id: 3,
                name: 'Aether Shield #108',
                collection: 'Relics of DeFi',
                price: '0.85 ETH',
                priceVal: 0.85,
                rarity: 'Epic',
                attributes: [
                    { trait: 'Power', value: 'Yield Multiplier 2x' }
                ]
            }
        ],
        transactions: [
            {
                hash: '0x71a...f89e',
                fullHash: '0x71a48c9f2b1d3e4a5b6c7d8e9f0a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f89e',
                type: 'Swap',
                description: 'Swapped 1.5 ETH for 5,176.12 USDT',
                amount: '1.5 ETH',
                status: 'Confirmed',
                timestamp: Date.now() - 3600000,
                blockNumber: 19842105
            },
            {
                hash: '0x32c...e11b',
                fullHash: '0x32c81d7f6e5d4c3b2a1f0e9d8c7b6a5f4e3d2c1b0a9f8e7d6c5b4a3f2e1e11b',
                type: 'Stake',
                description: 'Staked 2,500 OPUS in Yield Vault',
                amount: '2,500 OPUS',
                status: 'Confirmed',
                timestamp: Date.now() - 86400000,
                blockNumber: 19835012
            }
        ],
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
    // Pair Exchange Rates Dictionary & Engine Configuration
    // ---------------------------------------------------------------------
    const PAIR_RATES = {
        'ETH/USDT': { base: 'ETH', quote: 'USDT', price: 3450.75, decimals: 2 },
        'BTC/USDT': { base: 'BTC', quote: 'USDT', price: 64200.00, decimals: 2 },
        'SOL/USDT': { base: 'SOL', quote: 'USDT', price: 145.20, decimals: 2 },
        'OPUS/USDT': { base: 'OPUS', quote: 'USDT', price: 0.45, decimals: 4 },
        'ETH/BTC': { base: 'ETH', quote: 'BTC', price: 0.0537, decimals: 6 }
    };

    let marketInterval = null;
    let gasInterval = null;
    let stakingInterval = null;
    let audioCtx = null;

    // ---------------------------------------------------------------------
    // Web Audio Sound Synthesizer Engine
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
            const now = audioCtx.currentTime;
            const osc = audioCtx.createOscillator();
            const gain = audioCtx.createGain();
            osc.connect(gain);
            gain.connect(audioCtx.destination);

            if (type === 'click') {
                osc.type = 'sine';
                osc.frequency.setValueAtTime(600, now);
                osc.frequency.exponentialRampToValueAtTime(300, now + 0.05);
                gain.gain.setValueAtTime(0.08, now);
                gain.gain.exponentialRampToValueAtTime(0.001, now + 0.05);
                osc.start(now);
                osc.stop(now + 0.05);
            } else if (type === 'success') {
                osc.type = 'triangle';
                osc.frequency.setValueAtTime(523.25, now); // C5
                osc.frequency.setValueAtTime(659.25, now + 0.08); // E5
                osc.frequency.setValueAtTime(783.99, now + 0.16); // G5
                gain.gain.setValueAtTime(0.12, now);
                gain.gain.exponentialRampToValueAtTime(0.001, now + 0.35);
                osc.start(now);
                osc.stop(now + 0.35);
            } else if (type === 'error') {
                osc.type = 'sawtooth';
                osc.frequency.setValueAtTime(300, now);
                osc.frequency.setValueAtTime(220, now + 0.1);
                gain.gain.setValueAtTime(0.1, now);
                gain.gain.exponentialRampToValueAtTime(0.001, now + 0.25);
                osc.start(now);
                osc.stop(now + 0.25);
            } else if (type === 'swap') {
                osc.type = 'sine';
                osc.frequency.setValueAtTime(440, now);
                osc.frequency.exponentialRampToValueAtTime(880, now + 0.15);
                gain.gain.setValueAtTime(0.1, now);
                gain.gain.exponentialRampToValueAtTime(0.001, now + 0.2);
                osc.start(now);
                osc.stop(now + 0.2);
            }
        } catch (err) {
            console.debug('Audio playback skipped:', err);
        }
    }

    // ---------------------------------------------------------------------
    // Toast Notification System
    // ---------------------------------------------------------------------
    function showToast(message, type = 'info') {
        const container = document.getElementById('toast-container') || createToastContainer();
        const toast = document.createElement('div');
        toast.className = `toast toast-${type}`;
        
        const icons = {
            success: '✓',
            error: '✕',
            warning: '⚠',
            info: 'ℹ'
        };
        
        toast.innerHTML = `
            <span class="toast-icon">${icons[type] || 'ℹ'}</span>
            <span class="toast-message">${escapeHtml(message)}</span>
            <button class="toast-close">&times;</button>
        `;
        
        const closeBtn = toast.querySelector('.toast-close');
        closeBtn.addEventListener('click', () => {
            toast.classList.add('toast-hiding');
            setTimeout(() => toast.remove(), 300);
        });

        container.appendChild(toast);
        playSound(type === 'error' ? 'error' : (type === 'success' ? 'success' : 'click'));

        setTimeout(() => {
            if (toast.parentNode) {
                toast.classList.add('toast-hiding');
                setTimeout(() => toast.remove(), 300);
            }
        }, 4000);
    }

    function createToastContainer() {
        let container = document.getElementById('toast-container');
        if (!container) {
            container = document.createElement('div');
            container.id = 'toast-container';
            container.className = 'toast-container';
            document.body.appendChild(container);
        }
        return container;
    }

    function escapeHtml(str) {
        return String(str).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
    }

    // ---------------------------------------------------------------------
    // Format Utilities
    // ---------------------------------------------------------------------
    function formatCurrency(val, decimals = 2) {
        return new Intl.NumberFormat('en-US', {
            style: 'currency',
            currency: 'USD',
            minimumFractionDigits: decimals,
            maximumFractionDigits: decimals
        }).format(val);
    }

    function formatNumber(val, decimals = 4) {
        return new Intl.NumberFormat('en-US', {
            minimumFractionDigits: decimals,
            maximumFractionDigits: decimals
        }).format(val);
    }

    function formatTruncatedAddress(address) {
        if (!address) return '';
        return `${address.substring(0, 6)}...${address.substring(address.length - 4)}`;
    }

    // ---------------------------------------------------------------------
    // Wallet Engine & EIP-1193 Connector
    // ---------------------------------------------------------------------
    async function connectWallet() {
        playSound('click');
        const btn = document.getElementById('connect-wallet-btn');
        if (btn) btn.disabled = true;

        try {
            if (window.ethereum) {
                const accounts = await window.ethereum.request({ method: 'eth_requestAccounts' });
                if (accounts && accounts.length > 0) {
                    state.wallet.address = accounts[0];
                    state.wallet.connected = true;
                    showToast(`Wallet connected: ${formatTruncatedAddress(accounts[0])}`, 'success');
                }
            } else {
                // Mock fallback for demonstration
                await new Promise(res => setTimeout(res, 600));
                state.wallet.address = '0x8F3Cf7ad23Cd3CaDbD9735AFf958023239c6A063';
                state.wallet.connected = true;
                showToast(`Demo Wallet Connected: ${formatTruncatedAddress(state.wallet.address)}`, 'success');
            }
            updateWalletUI();
        } catch (err) {
            showToast(err.message || 'Failed to connect wallet', 'error');
        } finally {
            if (btn) btn.disabled = false;
        }
    }

    function disconnectWallet() {
        playSound('click');
        state.wallet.connected = false;
        state.wallet.address = null;
        updateWalletUI();
        showToast('Wallet disconnected', 'info');
    }

    function updateWalletUI() {
        const walletBtn = document.getElementById('connect-wallet-btn');
        const walletStatus = document.getElementById('wallet-status');
        const walletAddrEl = document.getElementById('wallet-address-display');
        const ethBalEl = document.getElementById('wallet-eth-balance');
        const usdtBalEl = document.getElementById('wallet-usdt-balance');

        if (state.wallet.connected) {
            if (walletBtn) {
                walletBtn.textContent = formatTruncatedAddress(state.wallet.address);
                walletBtn.classList.add('connected');
            }
            if (walletStatus) walletStatus.textContent = 'Connected';
            if (walletAddrEl) walletAddrEl.textContent = state.wallet.address;
        } else {
            if (walletBtn) {
                walletBtn.textContent = 'Connect Wallet';
                walletBtn.classList.remove('connected');
            }
            if (walletStatus) walletStatus.textContent = 'Not Connected';
            if (walletAddrEl) walletAddrEl.textContent = '0x0000...0000';
        }

        if (ethBalEl) ethBalEl.textContent = `${formatNumber(state.wallet.balanceEth, 4)} ETH`;
        if (usdtBalEl) usdtBalEl.textContent = formatCurrency(state.wallet.balanceUsdt);

        renderPortfolio();
    }

    // ---------------------------------------------------------------------
    // Market Simulation & Orderbook Engine
    // ---------------------------------------------------------------------
    function initMarketData() {
        const currentRate = PAIR_RATES[state.market.selectedPair] || PAIR_RATES['ETH/USDT'];
        state.market.price = currentRate.price;
        
        // Seed initial history
        state.market.chartData.labels = [];
        state.market.chartData.prices = [];
        let basePrice = state.market.price;
        const now = Date.now();
        
        for (let i = 30; i >= 0; i--) {
            const timeStr = new Date(now - i * 60000).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
            const delta = (Math.random() - 0.49) * (basePrice * 0.004);
            basePrice += delta;
            state.market.chartData.labels.push(timeStr);
            state.market.chartData.prices.push(basePrice);
        }

        updateMarketDisplay();
        updateOrderBook();
        renderMarketChart();
    }

    function startMarketTicker() {
        if (marketInterval) clearInterval(marketInterval);
        marketInterval = setInterval(() => {
            const pair = state.market.selectedPair;
            const rate = PAIR_RATES[pair];
            if (!rate) return;

            const fluctuation = (Math.random() - 0.495) * (rate.price * 0.003);
            rate.price = Math.max(0.0001, rate.price + fluctuation);
            state.market.price = rate.price;

            const pctChange = ((Math.random() - 0.48) * 0.1);
            state.market.change24h = parseFloat((state.market.change24h + pctChange).toFixed(2));

            // Update chart data
            const timeStr = new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
            state.market.chartData.labels.push(timeStr);
            state.market.chartData.prices.push(rate.price);
            if (state.market.chartData.labels.length > 35) {
                state.market.chartData.labels.shift();
                state.market.chartData.prices.shift();
            }

            updateMarketDisplay();
            updateOrderBook();
            renderMarketChart();
        }, state.settings.autoRefreshInterval);
    }

    function updateMarketDisplay() {
        const priceEl = document.getElementById('market-price-val');
        const changeEl = document.getElementById('market-change-val');
        const highEl = document.getElementById('market-high-val');
        const lowEl = document.getElementById('market-low-val');
        const volEl = document.getElementById('market-vol-val');

        const pair = state.market.selectedPair;
        const rate = PAIR_RATES[pair];
        const decimals = rate ? rate.decimals : 2;

        if (priceEl) priceEl.textContent = pair.endsWith('/USDT') ? formatCurrency(state.market.price, decimals) : formatNumber(state.market.price, decimals);
        
        if (changeEl) {
            const sign = state.market.change24h >= 0 ? '+' : '';
            changeEl.textContent = `${sign}${state.market.change24h}%`;
            changeEl.className = `stat-value ${state.market.change24h >= 0 ? 'text-green' : 'text-red'}`;
        }

        if (highEl) highEl.textContent = formatCurrency(state.market.high24h);
        if (lowEl) lowEl.textContent = formatCurrency(state.market.low24h);
        if (volEl) volEl.textContent = `$${(state.market.volume24h / 1e6).toFixed(2)}M`;
    }

    function updateOrderBook() {
        const bidsEl = document.getElementById('orderbook-bids');
        const asksEl = document.getElementById('orderbook-asks');
        if (!bidsEl || !asksEl) return;

        const currentPrice = state.market.price;
        state.orderBook.bids = [];
        state.orderBook.asks = [];

        for (let i = 1; i <= 6; i++) {
            const askPrice = currentPrice * (1 + i * 0.0008);
            const askSize = Math.random() * 2.5 + 0.1;
            state.orderBook.asks.push({ price: askPrice, size: askSize, total: askPrice * askSize });

            const bidPrice = currentPrice * (1 - i * 0.0008);
            const bidSize = Math.random() * 2.5 + 0.1;
            state.orderBook.bids.push({ price: bidPrice, size: bidSize, total: bidPrice * bidSize });
        }

        asksEl.innerHTML = state.orderBook.asks.slice().reverse().map(a => `
            <div class="ob-row ob-ask">
                <span class="ob-price">${formatNumber(a.price, 2)}</span>
                <span class="ob-size">${formatNumber(a.size, 3)}</span>
                <span class="ob-total">${formatNumber(a.total, 2)}</span>
            </div>
        `).join('');

        bidsEl.innerHTML = state.orderBook.bids.map(b => `
            <div class="ob-row ob-bid">
                <span class="ob-price">${formatNumber(b.price, 2)}</span>
                <span class="ob-size">${formatNumber(b.size, 3)}</span>
                <span class="ob-total">${formatNumber(b.total, 2)}</span>
            </div>
        `).join('');
    }

    // ---------------------------------------------------------------------
    // Interactive HTML5 Canvas Price Chart Renderer
    // ---------------------------------------------------------------------
    function renderMarketChart() {
        const canvas = document.getElementById('price-chart-canvas');
        if (!canvas) return;
        const ctx = canvas.getContext('2d');
        if (!ctx) return;

        const dpr = window.devicePixelRatio || 1;
        const rect = canvas.getBoundingClientRect();
        if (rect.width === 0 || rect.height === 0) return;

        canvas.width = rect.width * dpr;
        canvas.height = rect.height * dpr;
        ctx.scale(dpr, dpr);

        const w = rect.width;
        const h = rect.height;
        const prices = state.market.chartData.prices;
        if (!prices || prices.length < 2) return;

        ctx.clearRect(0, 0, w, h);

        const minPrice = Math.min(...prices) * 0.998;
        const maxPrice = Math.max(...prices) * 1.002;
        const range = maxPrice - minPrice || 1;

        const paddingBottom = 25;
        const paddingTop = 15;
        const paddingLeft = 10;
        const paddingRight = 45;
        const graphW = w - paddingLeft - paddingRight;
        const graphH = h - paddingTop - paddingBottom;

        // Background Grid lines
        ctx.strokeStyle = 'rgba(255, 255, 255, 0.05)';
        ctx.lineWidth = 1;
        const gridLines = 4;
        for (let i = 0; i <= gridLines; i++) {
            const y = paddingTop + (graphH / gridLines) * i;
            ctx.beginPath();
            ctx.moveTo(paddingLeft, y);
            ctx.lineTo(w - paddingRight, y);
            ctx.stroke();

            // Y-axis price label
            const priceVal = maxPrice - (range / gridLines) * i;
            ctx.fillStyle = '#64748b';
            ctx.font = '10px monospace';
            ctx.textAlign = 'left';
            ctx.fillText(priceVal.toFixed(2), w - paddingRight + 5, y + 3);
        }

        // Chart Line & Gradient
        const points = prices.map((p, idx) => {
            const x = paddingLeft + (idx / (prices.length - 1)) * graphW;
            const y = paddingTop + graphH - ((p - minPrice) / range) * graphH;
            return { x, y };
        });

        // Fill Area
        const gradient = ctx.createLinearGradient(0, paddingTop, 0, h - paddingBottom);
        const isPositive = prices[prices.length - 1] >= prices[0];
        const strokeColor = isPositive ? '#10b981' : '#ef4444';
        const fillColorStart = isPositive ? 'rgba(16, 185, 129, 0.25)' : 'rgba(239, 68, 68, 0.25)';
        const fillColorEnd = isPositive ? 'rgba(16, 185, 129, 0.0)' : 'rgba(239, 68, 68, 0.0)';

        gradient.addColorStop(0, fillColorStart);
        gradient.addColorStop(1, fillColorEnd);

        ctx.beginPath();
        ctx.moveTo(points[0].x, points[0].y);
        for (let i = 1; i < points.length; i++) {
            const xc = (points[i].x + points[i - 1].x) / 2;
            const yc = (points[i].y + points[i - 1].y) / 2;
            ctx.quadraticCurveTo(points[i - 1].x, points[i - 1].y, xc, yc);
        }
        ctx.lineTo(points[points.length - 1].x, points[points.length - 1].y);
        ctx.lineTo(points[points.length - 1].x, h - paddingBottom);
        ctx.lineTo(points[0].x, h - paddingBottom);
        ctx.closePath();
        ctx.fillStyle = gradient;
        ctx.fill();

        // Stroke Line
        ctx.beginPath();
        ctx.moveTo(points[0].x, points[0].y);
        for (let i = 1; i < points.length; i++) {
            const xc = (points[i].x + points[i - 1].x) / 2;
            const yc = (points[i].y + points[i - 1].y) / 2;
            ctx.quadraticCurveTo(points[i - 1].x, points[i - 1].y, xc, yc);
        }
        ctx.lineTo(points[points.length - 1].x, points[points.length - 1].y);
        ctx.strokeStyle = strokeColor;
        ctx.lineWidth = 2;
        ctx.stroke();

        // Current price glowing pulse dot
        const lastPt = points[points.length - 1];
        ctx.beginPath();
        ctx.arc(lastPt.x, lastPt.y, 4, 0, Math.PI * 2);
        ctx.fillStyle = strokeColor;
        ctx.shadowColor = strokeColor;
        ctx.shadowBlur = 8;
        ctx.fill();
        ctx.shadowBlur = 0;
    }

    // ---------------------------------------------------------------------
    // Gas Tracker Feed
    // ---------------------------------------------------------------------
    function startGasTracker() {
        if (gasInterval) clearInterval(gasInterval);
        gasInterval = setInterval(() => {
            const baseGas = Math.floor(Math.random() * 8) + 14;
            state.gas.slow = baseGas - 4;
            state.gas.standard = baseGas;
            state.gas.fast = baseGas + 6;
            state.gas.current = baseGas;
            updateGasDisplay();
        }, 5000);
    }

    function updateGasDisplay() {
        const gasEl = document.getElementById('gas-tracker-value');
        if (gasEl) gasEl.textContent = `${state.gas.current} ${state.gas.unit}`;
    }

    // ---------------------------------------------------------------------
    // DeFi Swap Engine
    // ---------------------------------------------------------------------
    function handleSwapInput(e) {
        const fromAmount = parseFloat(e.target.value) || 0;
        state.swap.fromAmount = e.target.value;

        const fromToken = state.swap.fromToken;
        const toToken = state.swap.toToken;

        const fromPrice = getTokenPrice(fromToken);
        const toPrice = getTokenPrice(toToken);

        if (fromAmount > 0 && toPrice > 0) {
            const calculatedTo = (fromAmount * fromPrice) / toPrice;
            state.swap.toAmount = calculatedTo.toFixed(6);
            const toInput = document.getElementById('swap-to-amount');
            if (toInput) toInput.value = state.swap.toAmount;
        } else {
            state.swap.toAmount = '';
            const toInput = document.getElementById('swap-to-amount');
            if (toInput) toInput.value = '';
        }
    }

    function switchSwapTokens() {
        playSound('click');
        const temp = state.swap.fromToken;
        state.swap.fromToken = state.swap.toToken;
        state.swap.toToken = temp;

        const fromSelect = document.getElementById('swap-from-token');
        const toSelect = document.getElementById('swap-to-token');
        if (fromSelect) fromSelect.value = state.swap.fromToken;
        if (toSelect) toSelect.value = state.swap.toToken;

        const fromInput = document.getElementById('swap-from-amount');
        if (fromInput) handleSwapInput({ target: fromInput });
    }

    function getTokenPrice(symbol) {
        if (symbol === 'USDT') return 1.0;
        const t = state.wallet.tokens.find(tok => tok.symbol === symbol);
        return t ? t.price : 1.0;
    }

    function executeSwap() {
        playSound('click');
        const amount = parseFloat(state.swap.fromAmount);
        if (!amount || amount <= 0) {
            showToast('Please enter a valid swap amount', 'warning');
            return;
        }

        const fromToken = state.swap.fromToken;
        const toToken = state.swap.toToken;
        const fromAsset = state.wallet.tokens.find(t => t.symbol === fromToken);

        if (fromAsset && fromAsset.balance < amount) {
            showToast(`Insufficient ${fromToken} balance`, 'error');
            return;
        }

        // Deduct and Credit balances
        if (fromAsset) fromAsset.balance -= amount;
        const toAsset = state.wallet.tokens.find(t => t.symbol === toToken);
        const received = parseFloat(state.swap.toAmount) || 0;
        if (toAsset) toAsset.balance += received;

        if (fromToken === 'ETH') state.wallet.balanceEth = Math.max(0, state.wallet.balanceEth - amount);
        if (toToken === 'ETH') state.wallet.balanceEth += received;
        if (fromToken === 'USDT') state.wallet.balanceUsdt = Math.max(0, state.wallet.balanceUsdt - amount);
        if (toToken === 'USDT') state.wallet.balanceUsdt += received;

        const newTx = {
            hash: `0x${Math.random().toString(16).substring(2, 6)}...${Math.random().toString(16).substring(2, 6)}`,
            fullHash: `0x${Math.random().toString(16).substring(2)}${Math.random().toString(16).substring(2)}`,
            type: 'Swap',
            description: `Swapped ${amount} ${fromToken} for ${formatNumber(received, 4)} ${toToken}`,
            amount: `${amount} ${fromToken}`,
            status: 'Confirmed',
            timestamp: Date.now(),
            blockNumber: 19842100 + Math.floor(Math.random() * 500)
        };

        state.transactions.unshift(newTx);
        renderTransactions();
        updateWalletUI();
        playSound('swap');
        showToast(`Successfully swapped ${amount} ${fromToken} for ${formatNumber(received, 4)} ${toToken}`, 'success');

        // Reset input
        state.swap.fromAmount = '';
        state.swap.toAmount = '';
        const fromInput = document.getElementById('swap-from-amount');
        const toInput = document.getElementById('swap-to-amount');
        if (fromInput) fromInput.value = '';
        if (toInput) toInput.value = '';
    }

    // ---------------------------------------------------------------------
    // Staking Vault & Rewards Engine
    // ---------------------------------------------------------------------
    function startStakingTicker() {
        if (stakingInterval) clearInterval(stakingInterval);
        stakingInterval = setInterval(() => {
            // Yield per second based on APY
            const annualRate = state.staking.rewardRateApy / 100;
            const secYield = (state.staking.stakedOpus * annualRate) / (365 * 24 * 3600);
            state.staking.pendingRewards += secYield;
            updateStakingDisplay();
        }, 1000);
    }

    function updateStakingDisplay() {
        const stakedEl = document.getElementById('staked-opus-val');
        const rewardsEl = document.getElementById('pending-rewards-val');
        const apyEl = document.getElementById('vault-apy-val');

        if (stakedEl) stakedEl.textContent = `${formatNumber(state.staking.stakedOpus, 2)} OPUS`;
        if (rewardsEl) rewardsEl.textContent = `${formatNumber(state.staking.pendingRewards, 4)} OPUS`;
        if (apyEl) apyEl.textContent = `${state.staking.rewardRateApy}%`;
    }

    function claimStakingRewards() {
        playSound('click');
        if (state.staking.pendingRewards <= 0) {
            showToast('No pending rewards to claim', 'warning');
            return;
        }

        const amount = state.staking.pendingRewards;
        const opusToken = state.wallet.tokens.find(t => t.symbol === 'OPUS');
        if (opusToken) opusToken.balance += amount;
        state.wallet.balanceOpus += amount;
        state.staking.pendingRewards = 0;

        const newTx = {
            hash: `0x${Math.random().toString(16).substring(2, 6)}...${Math.random().toString(16).substring(2, 6)}`,
            fullHash: `0x${Math.random().toString(16).substring(2)}${Math.random().toString(16).substring(2)}`,
            type: 'Claim',
            description: `Claimed ${formatNumber(amount, 4)} OPUS Vault Rewards`,
            amount: `${formatNumber(amount, 4)} OPUS`,
            status: 'Confirmed',
            timestamp: Date.now(),
            blockNumber: 19842100 + Math.floor(Math.random() * 500)
        };

        state.transactions.unshift(newTx);
        renderTransactions();
        updateWalletUI();
        showToast(`Successfully claimed ${formatNumber(amount, 4)} OPUS rewards!`, 'success');
    }

    // ---------------------------------------------------------------------
    // Portfolio Analytics Rendering
    // ---------------------------------------------------------------------
    function renderPortfolio() {
        const listContainer = document.getElementById('portfolio-asset-list');
        const totalBalEl = document.getElementById('portfolio-total-val');
        if (!listContainer) return;

        let totalVal = 0;
        const assetValues = state.wallet.tokens.map(tok => {
            const val = tok.balance * tok.price;
            totalVal += val;
            return { ...tok, value: val };
        });

        if (totalBalEl) totalBalEl.textContent = formatCurrency(totalVal);

        listContainer.innerHTML = assetValues.map(asset => {
            const alloc = totalVal > 0 ? ((asset.value / totalVal) * 100).toFixed(1) : 0;
            return `
                <div class="asset-card-row">
                    <div class="asset-info">
                        <span class="asset-icon">${asset.icon}</span>
                        <div>
                            <div class="asset-name">${escapeHtml(asset.name)}</div>
                            <div class="asset-symbol">${escapeHtml(asset.symbol)}</div>
                        </div>
                    </div>
                    <div class="asset-balance-col">
                        <div class="asset-balance">${formatNumber(asset.balance, 4)}</div>
                        <div class="asset-value">${formatCurrency(asset.value)}</div>
                    </div>
                    <div class="asset-alloc-col">
                        <div class="asset-alloc-bar-bg">
                            <div class="asset-alloc-bar-fill" style="width: ${alloc}%"></div>
                        </div>
                        <span class="asset-alloc-pct">${alloc}%</span>
                    </div>
                </div>
            `;
        }).join('');
    }

    // ---------------------------------------------------------------------
    // NFT Gallery Engine
    // ---------------------------------------------------------------------
    function renderNftGallery() {
        const galleryEl = document.getElementById('nft-grid-container');
        if (!galleryEl) return;

        galleryEl.innerHTML = state.nfts.map(nft => `
            <div class="nft-card" data-nft-id="${nft.id}">
                <div class="nft-media-box">
                    <div class="nft-placeholder-art ${nft.rarity.toLowerCase()}">
                        <span class="nft-art-icon">❖</span>
                        <span class="nft-rarity-badge">${escapeHtml(nft.rarity)}</span>
                    </div>
                </div>
                <div class="nft-details">
                    <div class="nft-collection">${escapeHtml(nft.collection)}</div>
                    <div class="nft-title">${escapeHtml(nft.name)}</div>
                    <div class="nft-footer">
                        <div class="nft-price-tag">
                            <span class="lbl">Price</span>
                            <span class="val">${escapeHtml(nft.price)}</span>
                        </div>
                        <button class="btn btn-sm btn-primary buy-nft-btn" data-id="${nft.id}">Purchase</button>
                    </div>
                </div>
            </div>
        `).join('');

        galleryEl.querySelectorAll('.buy-nft-btn').forEach(btn => {
            btn.addEventListener('click', (e) => {
                const id = parseInt(e.target.getAttribute('data-id'), 10);
                buyNft(id);
            });
        });
    }

    function buyNft(id) {
        playSound('click');
        const nft = state.nfts.find(item => item.id === id);
        if (!nft) return;

        if (state.wallet.balanceEth < nft.priceVal) {
            showToast(`Insufficient ETH balance to buy ${nft.name}`, 'error');
            return;
        }

        state.wallet.balanceEth -= nft.priceVal;
        const ethToken = state.wallet.tokens.find(t => t.symbol === 'ETH');
        if (ethToken) ethToken.balance -= nft.priceVal;

        const newTx = {
            hash: `0x${Math.random().toString(16).substring(2, 6)}...${Math.random().toString(16).substring(2, 6)}`,
            fullHash: `0x${Math.random().toString(16).substring(2)}${Math.random().toString(16).substring(2)}`,
            type: 'NFT Buy',
            description: `Purchased NFT: ${nft.name}`,
            amount: nft.price,
            status: 'Confirmed',
            timestamp: Date.now(),
            blockNumber: 19842100 + Math.floor(Math.random() * 500)
        };

        state.transactions.unshift(newTx);
        renderTransactions();
        updateWalletUI();
        showToast(`Successfully purchased ${nft.name}!`, 'success');
    }

    // ---------------------------------------------------------------------
    // Transaction History Table Generator
    // ---------------------------------------------------------------------
    function renderTransactions(filterType = 'all') {
        const tableBody = document.getElementById('tx-history-tbody');
        if (!tableBody) return;

        const filtered = state.transactions.filter(tx => {
            if (filterType === 'all') return true;
            return tx.type.toLowerCase() === filterType.toLowerCase();
        });

        if (filtered.length === 0) {
            tableBody.innerHTML = `<tr><td colspan="6" class="text-center text-muted">No transactions found</td></tr>`;
            return;
        }

        tableBody.innerHTML = filtered.map(tx => {
            const timeAgo = Math.floor((Date.now() - tx.timestamp) / 60000);
            const timeStr = timeAgo < 1 ? 'Just now' : `${timeAgo}m ago`;
            return `
                <tr>
                    <td>
                        <a href="#" class="tx-hash-link" data-hash="${escapeHtml(tx.fullHash)}">${escapeHtml(tx.hash)}</a>
                    </td>
                    <td><span class="badge badge-${tx.type.toLowerCase()}">${escapeHtml(tx.type)}</span></td>
                    <td>${escapeHtml(tx.description)}</td>
                    <td>${escapeHtml(tx.amount)}</td>
                    <td><span class="status-pill status-${tx.status.toLowerCase()}">${escapeHtml(tx.status)}</span></td>
                    <td class="text-muted">${timeStr}</td>
                </tr>
            `;
        }).join('');

        tableBody.querySelectorAll('.tx-hash-link').forEach(link => {
            link.addEventListener('click', (e) => {
                e.preventDefault();
                const full = e.target.getAttribute('data-hash');
                if (navigator.clipboard) {
                    navigator.clipboard.writeText(full);
                    showToast('Transaction hash copied to clipboard', 'info');
                }
            });
        });
    }

    // ---------------------------------------------------------------------
    // Navigation Tab & Modal Manager
    // ---------------------------------------------------------------------
    function initNavigation() {
        const navItems = document.querySelectorAll('.nav-link[data-tab]');
        const tabPanes = document.querySelectorAll('.tab-pane');

        navItems.forEach(item => {
            item.addEventListener('click', (e) => {
                e.preventDefault();
                playSound('click');
                const targetTab = item.getAttribute('data-tab');

                navItems.forEach(n => n.classList.remove('active'));
                tabPanes.forEach(p => p.classList.remove('active'));

                item.classList.add('active');
                const targetPane = document.getElementById(`tab-${targetTab}`);
                if (targetPane) targetPane.classList.add('active');

                if (targetTab === 'analytics' || targetTab === 'dashboard') {
                    setTimeout(renderMarketChart, 50);
                }
            });
        });
    }

    function initModals() {
        const modalTriggers = document.querySelectorAll('[data-modal-target]');
        modalTriggers.forEach(btn => {
            btn.addEventListener('click', () => {
                playSound('click');
                const targetId = btn.getAttribute('data-modal-target');
                const modal = document.getElementById(targetId);
                if (modal) modal.classList.add('open');
            });
        });

        const closeBtns = document.querySelectorAll('.modal-close, .modal-backdrop');
        closeBtns.forEach(btn => {
            btn.addEventListener('click', () => {
                playSound('click');
                const modal = btn.closest('.modal');
                if (modal) modal.classList.remove('open');
            });
        });
    }

    // ---------------------------------------------------------------------
    // DOM Event Bindings & Initializer
    // ---------------------------------------------------------------------
    function bindEvents() {
        // Wallet buttons
        const connectBtn = document.getElementById('connect-wallet-btn');
        if (connectBtn) connectBtn.addEventListener('click', connectWallet);

        const disconnectBtn = document.getElementById('disconnect-wallet-btn');
        if (disconnectBtn) disconnectBtn.addEventListener('click', disconnectWallet);

        // Pair Selector
        const pairSelect = document.getElementById('market-pair-select');
        if (pairSelect) {
            pairSelect.addEventListener('change', (e) => {
                playSound('click');
                state.market.selectedPair = e.target.value;
                initMarketData();
            });
        }

        // Swap inputs & controls
        const swapFromInput = document.getElementById('swap-from-amount');
        if (swapFromInput) swapFromInput.addEventListener('input', handleSwapInput);

        const switchBtn = document.getElementById('swap-switch-btn');
        if (switchBtn) switchBtn.addEventListener('click', switchSwapTokens);

        const executeSwapBtn = document.getElementById('execute-swap-btn');
        if (executeSwapBtn) executeSwapBtn.addEventListener('click', executeSwap);

        // Staking
        const claimBtn = document.getElementById('claim-rewards-btn');
        if (claimBtn) claimBtn.addEventListener('click', claimStakingRewards);

        // Filter tabs for transactions
        const txFilters = document.querySelectorAll('.tx-filter-btn');
        txFilters.forEach(btn => {
            btn.addEventListener('click', () => {
                playSound('click');
                txFilters.forEach(b => b.classList.remove('active'));
                btn.classList.add('active');
                renderTransactions(btn.getAttribute('data-filter'));
            });
        });

        // Responsive Window Resize Handler for Canvas
        window.addEventListener('resize', () => {
            renderMarketChart();
        });
    }

    function initApp() {
        console.log('🚀 MAGNUM OPUS // Nexus Web3 Core Initializing...');
        initNavigation();
        initModals();
        bindEvents();
        
        initMarketData();
        startMarketTicker();
        startGasTracker();
        startStakingTicker();

        renderPortfolio();
        renderNftGallery();
        renderTransactions();
        updateWalletUI();
        
        console.log('✅ MAGNUM OPUS // All Subsystems Operational.');
    }

    // Run initialization on DOM Ready
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', initApp);
    } else {
        initApp();
    }
})();
