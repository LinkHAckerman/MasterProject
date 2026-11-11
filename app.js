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
                { symbol: 'ETH', name: 'Ethereum', balance: 14.852, decimals: 18, price: 3450.75, icon: '\u039e' },
                { symbol: 'USDT', name: 'Tether USD', balance: 42500.00, decimals: 6, price: 1.00, icon: '\u20ae' },
                { symbol: 'BTC', name: 'Bitcoin', balance: 0.65, decimals: 8, price: 64200.00, icon: '\u20bf' },
                { symbol: 'SOL', name: 'Solana', balance: 12.5, decimals: 9, price: 145.20, icon: '\u25ce' },
                { symbol: 'OPUS', name: 'Magnum Opus Governance', balance: 10000.0, decimals: 18, price: 0.45, icon: '\u2756' }
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

    // ---------------------------------------------------------------------
    // Utility Functions
    // ---------------------------------------------------------------------
    /**
     * Formats a number with a fixed number of decimal places and thousands separators.
     */
    function formatNumber(num, decimals) {
        const options = {
            minimumFractionDigits: decimals,
            maximumFractionDigits: decimals,
            useGrouping: true
        };
        return Number(num).toLocaleString(undefined, options);
    }

    /**
     * Retrieves a token object from the wallet token list by its symbol.
     */
    function getToken(symbol) {
        return state.wallet.tokens.find(t => t.symbol === symbol) || null;
    }

    // ---------------------------------------------------------------------
    // State Persistence (localStorage)
    // ---------------------------------------------------------------------
    const STORAGE_KEY = 'magnum_opus_state';

    function loadState() {
        try {
            const raw = localStorage.getItem(STORAGE_KEY);
            if (raw) {
                const persisted = JSON.parse(raw);
                // Deep merge persisted values onto the default state
                Object.assign(state, persisted);
                // Merge nested objects where appropriate
                if (persisted.wallet && persisted.wallet.tokens) {
                    state.wallet.tokens = persisted.wallet.tokens;
                }
                if (persisted.settings) {
                    Object.assign(state.settings, persisted.settings);
                }
                console.log('🔄 State loaded from localStorage');
            }
        } catch (e) {
            console.warn('Failed to load persisted state:', e);
        }
    }

    function saveState() {
        try {
            const snapshot = {
                wallet: {
                    connected: state.wallet.connected,
                    address: state.wallet.address,
                    tokens: state.wallet.tokens
                },
                settings: state.settings,
                swap: state.swap,
                staking: state.staking
            };
            localStorage.setItem(STORAGE_KEY, JSON.stringify(snapshot));
            console.log('💾 State saved to localStorage');
        } catch (e) {
            console.warn('Failed to persist state:', e);
        }
    }

    // ---------------------------------------------------------------------
    // Market Data Refresh (mocked fetch)
    // ---------------------------------------------------------------------
    async function refreshMarketData() {
        try {
            // In a real implementation this would call a backend API.
            // Here we simulate latency and random price drift.
            await new Promise(r => setTimeout(r, 500));
            const pair = state.market.selectedPair;
            const rate = PAIR_RATES[pair];
            if (!rate) return;
            // Simulate a small random price change +/-0.5%
            const drift = (Math.random() - 0.5) * 0.01;
            const newPrice = +(rate.price * (1 + drift)).toFixed(rate.decimals);
            rate.price = newPrice;
            state.market.price = newPrice;
            state.market.change24h = +(drift * 100).toFixed(2);
            // Update chart data (simple rolling window)
            const now = new Date();
            state.market.chartData.labels.push(now.toLocaleTimeString());
            state.market.chartData.prices.push(newPrice);
            if (state.market.chartData.labels.length > 30) {
                state.market.chartData.labels.shift();
                state.market.chartData.prices.shift();
            }
            // Notify UI (if a render hook exists)
            if (typeof window.dispatchEvent === 'function') {
                window.dispatchEvent(new CustomEvent('magnum:market-updated', { detail: { pair, price: newPrice } }));
            }
        } catch (e) {
            console.error('Market refresh failed:', e);
        }
    }

    // ---------------------------------------------------------------------
    // Swap Engine
    // ---------------------------------------------------------------------
    function calculateSwap() {
        const { fromToken, toToken, fromAmount, slippage } = state.swap;
        if (!fromAmount || isNaN(fromAmount) || fromAmount <= 0) {
            state.swap.toAmount = '';
            return;
        }
        const pairKey = `${fromToken}/${toToken}`;
        const reverseKey = `${toToken}/${fromToken}`;
        let rateInfo = PAIR_RATES[pairKey];
        let direction = 1; // forward
        if (!rateInfo) {
            rateInfo = PAIR_RATES[reverseKey];
            direction = -1; // reverse
        }
        if (!rateInfo) {
            console.warn('No rate available for pair', fromToken, toToken);
            state.swap.toAmount = '';
            return;
        }
        const rawPrice = rateInfo.price;
        const price = direction === 1 ? rawPrice : 1 / rawPrice;
        // Apply slippage tolerance (worst‑case execution price)
        const effectivePrice = price * (1 + (slippage || state.settings.slippageTolerance) / 100);
        const toAmount = direction === 1
            ? fromAmount * effectivePrice
            : fromAmount / effectivePrice;
        const decimals = rateInfo.decimals;
        state.swap.toAmount = formatNumber(toAmount, decimals);
    }

    // ---------------------------------------------------------------------
    // UI Bindings (lightweight, no framework)
    // ---------------------------------------------------------------------
    function bindUI() {
        // Wallet connect button
        const connectBtn = document.getElementById('btn-connect-wallet');
        if (connectBtn) {
            connectBtn.addEventListener('click', async () => {
                if (window.ethereum) {
                    try {
                        const accounts = await window.ethereum.request({ method: 'eth_requestAccounts' });
                        state.wallet.connected = true;
                        state.wallet.address = accounts[0];
                        saveState();
                        // Simple UI feedback
                        connectBtn.textContent = 'Connected';
                        console.log('Wallet connected:', accounts[0]);
                    } catch (err) {
                        console.error('User rejected wallet connection');
                    }
                } else {
                    alert('MetaMask not detected. Please install it to use the wallet features.');
                }
            });
        }

        // Swap input fields
        const fromInput = document.getElementById('swap-from-amount');
        const toInput = document.getElementById('swap-to-amount');
        if (fromInput) {
            fromInput.addEventListener('input', e => {
                state.swap.fromAmount = parseFloat(e.target.value);
                calculateSwap();
                if (toInput) toInput.value = state.swap.toAmount;
            });
        }
        // Token selector change
        const fromSelect = document.getElementById('swap-from-token');
        const toSelect = document.getElementById('swap-to-token');
        if (fromSelect && toSelect) {
            const updatePair = () => {
                state.swap.fromToken = fromSelect.value;
                state.swap.toToken = toSelect.value;
                calculateSwap();
                if (toInput) toInput.value = state.swap.toAmount;
            };
            fromSelect.addEventListener('change', updatePair);
            toSelect.addEventListener('change', updatePair);
        }

        // Theme toggle
        const themeToggle = document.getElementById('theme-toggle');
        if (themeToggle) {
            themeToggle.addEventListener('click', () => {
                const newTheme = state.settings.theme === 'dark' ? 'light' : 'dark';
                state.settings.theme = newTheme;
                document.documentElement.setAttribute('data-theme', newTheme);
                saveState();
            });
        }
    }

    // ---------------------------------------------------------------------
    // Initialization
    // ---------------------------------------------------------------------
    loadState();
    bindUI();
    // Initial market fetch and then periodic refresh based on settings
    refreshMarketData();
    setInterval(refreshMarketData, state.settings.autoRefreshInterval);

    // Expose a minimal API for debugging / external scripts
    window.MagnumOpus = {
        state,
        calculateSwap,
        refreshMarketData,
        formatNumber,
        getToken
    };
})();