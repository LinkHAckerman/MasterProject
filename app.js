(function () {
    'use strict';

    // Global State Management
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
                { symbol: 'ETH', name: 'Ethereum', balance: 14.852, decimals: 18, price: 3450.75, icon: 'ETH', change24h: 3.42 },
                { symbol: 'USDT', name: 'Tether USD', balance: 42500.00, decimals: 6, price: 1.00, icon: 'USDT', change24h: 0.01 },
                { symbol: 'BTC', name: 'Bitcoin', balance: 0.65, decimals: 8, price: 64200.00, icon: 'BTC', change24h: 1.85 },
                { symbol: 'SOL', name: 'Solana', balance: 12.5, decimals: 9, price: 145.20, icon: 'SOL', change24h: 6.12 },
                { symbol: 'OPUS', name: 'Magnum Opus Governance', balance: 10000.0, decimals: 18, price: 0.45, icon: 'OPUS', change24h: 12.40 }
            ]
        },
        gas: {
            slow: 12,
            standard: 18,
            fast: 24,
            current: 18,
            selectedTier: 'standard',
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
                volumes: []
            }
        },
        orderBook: {
            bids: [],
            asks: [],
            maxDepth: 12,
            spread: 0.05
        },
        swap: {
            fromToken: 'ETH',
            toToken: 'USDT',
            fromAmount: '',
            toAmount: '',
            slippage: 0.5,
            priceImpact: 0.04,
            routing: 'Magnum Smart Routing v2 (Uniswap v3 + Curve)'
        },
        staking: {
            stakedOpus: 2500.0,
            rewardRateApy: 18.5,
            pendingRewards: 14.8241,
            totalClaimed: 124.50,
            lockPeriodDays: 30,
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
                rank: 4,
                image: '\u001b[38;5;208m\u001b[48;5;16m\u001b[1m\u001b[3m\u001b[4m\u001b[5m\u001b[7m\u001b[8m\u001b[9m\u001b[30m\u001b[31m\u001b[32m\u001b[33m\u001b[34m\u001b[35m\u001b[36m\u001b[37m\u001b[40m\u001b[41m\u001b[42m\u001b[43m\u001b[44m\u001b[45m\u001b[46m\u001b[47m\u001b[0m',
                attributes: [
                    { trait: 'Background', value: 'Neon Nebula' },
                    { trait: 'Core', value: 'Quantum Heart' },
                    { trait: 'Aura', value: 'Chrono Pulse' }
                ]
            },
            {
                id: 2,
                name: 'Cyber Opus #042',
                collection: 'Opus Genesis',
                price: '1.2 ETH',
                priceVal: 1.2,
                rarity: 'Rare',
                rank: 142,
                image: '\u001b[38;5;208m\u001b[48;5;16m\u001b[1m\u001b[3m\u001b[4m\u001b[5m\u001b[7m\u001b[8m\u001b[9m\u001b[30m\u001b[31m\u001b[32m\u001b[33m\u001b[34m\u001b[35m\u001b[36m\u001b[37m\u001b[40m\u001b[41m\u001b[42m\u001b[43m\u001b[44m\u001b[45m\u001b[46m\u001b[47m\u001b[0m',
                attributes: [
                    { trait: 'Background', value: 'Deep Cyber' },
                    { trait: 'Core', value: 'Plasma Engine' },
                    { trait: 'Aura', value: 'Overclock' }
                ]
            },
            {
                id: 3,
                name: 'Aether Shield #108',
                collection: 'Relics of DeFi',
                price: '0.85 ETH',
                priceVal: 0.85,
                rarity: 'Epic',
                rank: 45,
                image: '\u001b[38;5;208m\u001b[48;5;16m\u001b[1m\u001b[3m\u001b[4m\u001b[5m\u001b[7m\u001b[8m\u001b[9m\u001b[30m\u001b[31m\u001b[32m\u001b[33m\u001b[34m\u001b[35m\u001b[36m\u001b[37m\u001b[40m\u001b[41m\u001b[42m\u001b[43m\u001b[44m\u001b[45m\u001b[46m\u001b[47m\u001b[0m',
                attributes: [
                    { trait: 'Power', value: 'Yield Multiplier 2.5x' },
                    { trait: 'Element', value: 'Starlight' }
                ]
            },
            {
                id: 4,
                name: 'Vortex Sentinel #777',
                collection: 'Relics of DeFi',
                price: '3.1 ETH',
                priceVal: 3.1,
                rarity: 'Mythic',
                rank: 1,
                image: '\u001b[38;5;208m\u001b[48;5;16m\u001b[1m\u001b[3m\u001b[4m\u001b[5m\u001b[7m\u001b[8m\u001b[9m\u001b[30m\u001b[31m\u001b[32m\u001b[33m\u001b[34m\u001b[35m\u001b[36m\u001b[37m\u001b[40m\u001b[41m\u001b[42m\u001b[43m\u001b[44m\u001b[45m\u001b[46m\u001b[47m\u001b[0m',
                attributes: [
                    { trait: 'Power', value: 'Zero Gas Transmutation' },
                    { trait: 'Element', value: 'Dark Matter' }
                ]
            }
        ],
        transactions: [
            {
                hash: '0x71a48c9f2b1d3e4a5b6c7d8e9f0a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f89e',
                displayHash: '0x71a...f89e',
                type: 'Swap',
                description: 'Swapped 1.5 ETH for 5,176.12 USDT',
                amount: '-1.5 ETH',
                status: 'Confirmed',
                timestamp: Date.now() - 3600000,
                blockNumber: 19842105
            },
            {
                hash: '0x32c81d7f6e5d4c3b2a1f0e9d8c7b6a5f4e3d2c1b0a9f8e7d6c5b4a3f2e1e11b',
                displayHash: '0x32c...e11b',
                type: 'Stake',
                description: 'Staked 2,500 OPUS in Yield Vault',
                amount: '2,500 OPUS',
                status: 'Confirmed',
                timestamp: Date.now() - 86400000,
                blockNumber: 19835012
            },
            {
                hash: '0x99f12a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e0f1a2b3c4d5e6f7a8b9c0d1e2f',
                displayHash: '0x99f...1e2f',
                type: 'Claim',
                description: 'Claimed Staking Rewards',
                amount: '+14.82 OPUS',
                status: 'Confirmed',
                timestamp: Date.now() - 172800000,
                blockNumber: 19821099
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

    // Web Audio Synthesizer Engine for Cybernetic Feedback
    const SoundEngine = {
        ctx: null,
        init() {
            try {
                if (!this.ctx && typeof AudioContext !== 'undefined') {
                    this.ctx = new (window.AudioContext || window.webkitAudioContext)();
                }
            } catch (e) {
                console.warn('AudioContext not supported or blocked');
            }
        },
        play(type) {
            if (!state.settings.enableSounds) return;
            this.init();
            if (!this.ctx) return;

            const now = this.ctx.currentTime;
            const osc = this.ctx.createOscillator();
            const gain = this.ctx.createGain();
            osc.connect(gain);
            gain.connect(this.ctx.destination);

            if (type === 'click') {
                osc.type = 'sine';
                osc.frequency.setValueAtTime(800, now);
                osc.frequency.exponentialRampToValueAtTime(400, now + 0.05);
                gain.gain.setValueAtTime(0.08, now);
                gain.gain.exponentialRampToValueAtTime(0.001, now + 0.05);
                osc.start(now);
                osc.stop(now + 0.05);
            } else if (type === 'success') {
                osc.type = 'triangle';
                osc.frequency.setValueAtTime(523.25, now); // C5
                osc.frequency.setValueAtTime(659.25, now + 0.08); // E5
                osc.frequency.setValueAtTime(783.99, now + 0.16); // G5
                gain.gain.setValueAtTime(0.1, now);
                gain.gain.exponentialRampToValueAtTime(0.001, now + 0.3);
                osc.start(now);
                osc.stop(now + 0.3);
            } else if (type === 'swap') {
                osc.type = 'sawtooth';
                osc.frequency.setValueAtTime(300, now);
                osc.frequency.linearRampToValueAtTime(1200, now + 0.15);
                gain.gain.setValueAtTime(0.05, now);
                gain.gain.exponentialRampToValueAtTime(0.001, now + 0.2);
                osc.start(now);
                osc.stop(now + 0.2);
            } else if (type === 'error') {
                osc.type = 'square';
                osc.frequency.setValueAtTime(180, now);
                osc.frequency.exponentialRampToValueAtTime(120, now + 0.1);
                gain.gain.setValueAtTime(0.07, now);
                gain.gain.exponentialRampToValueAtTime(0.001, now + 0.2);
                osc.start(now);
                osc.stop(now + 0.2);
            }
        }
    };

    // Utility: Simple fetch wrapper with JSON handling
    async function fetchJSON(url, options = {}) {
        const response = await fetch(url, Object.assign({ headers: { 'Accept': 'application/json' } }, options));
        if (!response.ok) {
            throw new Error(`Network error: ${response.status} ${response.statusText}`);
        }
        return await response.json();
    }

    // Update market data from a public API (placeholder)
    async function updateMarketData() {
        try {
            // Example using CoinGecko public endpoint
            const data = await fetchJSON('https://api.coingecko.com/api/v3/simple/price?ids=ethereum,usd-coin,bitcoin,solana&vs_currencies=usd');
            const ethPrice = data.ethereum.usd;
            const btcPrice = data.bitcoin.usd;
            const solPrice = data.solana.usd;
            const usdtPrice = data['usd-coin'].usd;

            // Update state.market and token prices
            state.market.price = ethPrice;
            state.market.change24h = ((ethPrice - state.market.price) / state.market.price * 100).toFixed(2);
            state.wallet.tokens.find(t => t.symbol === 'ETH').price = ethPrice;
            state.wallet.tokens.find(t => t.symbol === 'BTC').price = btcPrice;
            state.wallet.tokens.find(t => t.symbol === 'SOL').price = solPrice;
            state.wallet.tokens.find(t => t.symbol === 'USDT').price = usdtPrice;

            renderMarket();
        } catch (err) {
            console.error('Failed to update market data', err);
            SoundEngine.play('error');
        }
    }

    // Render market summary UI (placeholder implementation)
    function renderMarket() {
        const marketEl = document.getElementById('market-summary');
        if (!marketEl) return;
        marketEl.innerHTML = `
            <div class="pair">${state.market.selectedPair}</div>
            <div class="price">$${state.market.price.toLocaleString(undefined, {minimumFractionDigits: 2, maximumFractionDigits: 2})}</div>
            <div class="change ${state.market.change24h >= 0 ? 'up' : 'down'}">${state.market.change24h}%</div>
        `;
    }

    // Render wallet balances UI (placeholder implementation)
    function renderWallet() {
        const walletEl = document.getElementById('wallet-balance');
        if (!walletEl) return;
        const rows = state.wallet.tokens.map(tok => {
            const usdValue = (tok.balance * tok.price).toLocaleString(undefined, {minimumFractionDigits: 2, maximumFractionDigits: 2});
            return `<div class="token-row">
                <span class="token-icon">${tok.icon}</span>
                <span class="token-symbol">${tok.symbol}</span>
                <span class="token-balance">${tok.balance}</span>
                <span class="token-usd">$${usdValue}</span>
            </div>`;
        }).join('');
        walletEl.innerHTML = rows;
    }

    // Render recent transactions UI (placeholder implementation)
    function renderTransactions() {
        const txEl = document.getElementById('tx-history');
        if (!txEl) return;
        const rows = state.transactions.map(tx => {
            const date = new Date(tx.timestamp).toLocaleString();
            return `<div class="tx-row ${tx.status.toLowerCase()}">
                <span class="tx-hash">${tx.displayHash}</span>
                <span class="tx-type">${tx.type}</span>
                <span class="tx-amount">${tx.amount}</span>
                <span class="tx-status">${tx.status}</span>
                <span class="tx-time">${date}</span>
            </div>`;
        }).join('');
        txEl.innerHTML = rows;
    }

    // Initialize the application UI and start periodic refreshes
    function initApp() {
        // Attach basic UI event listeners
        document.addEventListener('click', function (e) {
            if (e.target.matches('.btn')) {
                SoundEngine.play('click');
            }
        });

        // Initial render
        renderWallet();
        renderMarket();
        renderTransactions();

        // Periodic market refresh based on settings
        setInterval(updateMarketData, state.settings.autoRefreshInterval);
    }

    // Expose some debug helpers
    window.MagnumOpus = {
        state,
        updateMarketData,
        renderWallet,
        renderTransactions,
        SoundEngine
    };

    // Kick off the app once DOM is ready
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', initApp);
    } else {
        initApp();
    }

})();