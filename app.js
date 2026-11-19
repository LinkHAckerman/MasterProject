/**
 * MAGNUM OPUS // Web3 & DeFi Nexus Engine - Core Application Engine
 * Version 4.2.0 - Production Grade Full-Stack Web3 Client Architecture
 */

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
                image: '[38;5;208m[48;5;16m[1m[3m[4m[5m[7m[8m[9m[30m[31m[32m[33m[34m[35m[36m[37m[40m[41m[42m[43m[44m[45m[46m[47m[0m',
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
                image: '[38;5;208m[48;5;16m[1m[3m[4m[5m[7m[8m[9m[30m[31m[32m[33m[34m[35m[36m[37m[40m[41m[42m[43m[44m[45m[46m[47m[0m',
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
                image: '[38;5;208m[48;5;16m[1m[3m[4m[5m[7m[8m[9m[30m[31m[32m[33m[34m[35m[36m[37m[40m[41m[42m[43m[44m[45m[46m[47m[0m',
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
                image: '[38;5;208m[48;5;16m[1m[3m[4m[5m[7m[8m[9m[30m[31m[32m[33m[34m[35m[36m[37m[40m[41m[42m[43m[44m[45m[46m[47m[0m',
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

            try {
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
                    osc.frequency.setValueAtTime(120, now + 0.1);
                    gain.gain.setValueAtTime(0.1, now);
                    gain.gain.exponentialRampToValueAtTime(0.001, now + 0.25);
                    osc.start(now);
                    osc.stop(now + 0.25);
                }
            } catch (err) {
                // Ignore audio errors
            }
        }
    };

    // Core Utilities & Formatters
    const Utils = {
        formatCurrency(value, symbol = '', decimals = 2) {
            const safeValue = Number(value) || 0;
            const formatted = safeValue.toLocaleString('en-US', {
                minimumFractionDigits: decimals,
                maximumFractionDigits: decimals
            });
            return `${symbol}${formatted}`;
        },
        formatAddress(address) {
            if (!address) return '';
            return `${address.substring(0, 6)}...${address.substring(address.length - 4)}`;
        },
        formatPercentage(value, decimals = 2) {
            const safeValue = Number(value) || 0;
            return `${safeValue.toFixed(decimals)}%`;
        },
        formatDate(timestamp) {
            const date = new Date(timestamp);
            return date.toLocaleString('en-US', {
                month: 'short',
                day: 'numeric',
                hour: '2-digit',
                minute: '2-digit'
            });
        },
        formatTokenAmount(amount, decimals = 18) {
            const safeAmount = Number(amount) || 0;
            const divisor = Math.pow(10, decimals);
            return safeAmount / divisor;
        },
        calculatePriceImpact(fromAmount, toAmount, expectedAmount) {
            if (!fromAmount || !toAmount || !expectedAmount) return 0;
            const impact = ((expectedAmount - toAmount) / expectedAmount) * 100;
            return Math.abs(impact);
        },
        calculateSlippage(fromAmount, toAmount, expectedAmount) {
            if (!fromAmount || !toAmount || !expectedAmount) return 0;
            const slippage = ((expectedAmount - toAmount) / expectedAmount) * 100;
            return Math.abs(slippage);
        },
        generateRandomHash() {
            return `0x${Math.random().toString(16).substring(2, 18)}...${Math.random().toString(16).substring(2, 6)}`;
        },
        generateRandomBlockNumber() {
            return Math.floor(Math.random() * 10000000) + 19800000;
        },
        generateRandomPriceChange() {
            return (Math.random() * 10 - 5).toFixed(2);
        },
        generateRandomVolume() {
            return Math.floor(Math.random() * 1000000000);
        },
        generateRandomPrice() {
            return (Math.random() * 1000 + 1000).toFixed(2);
        },
        generateRandomAmount() {
            return (Math.random() * 10).toFixed(4);
        },
        generateRandomToken() {
            const tokens = ['ETH', 'USDT', 'BTC', 'SOL', 'OPUS'];
            return tokens[Math.floor(Math.random() * tokens.length)];
        },
        generateRandomTransactionType() {
            const types = ['Swap', 'Stake', 'Claim', 'Transfer', 'Approve'];
            return types[Math.floor(Math.random() * types.length)];
        },
        generateRandomTransactionDescription(type, amount, token) {
            switch (type) {
                case 'Swap':
                    return `Swapped ${amount} ${token} for ${(amount * 1000).toFixed(2)} USDT`;
                case 'Stake':
                    return `Staked ${amount} ${token} in Yield Vault`;
                case 'Claim':
                    return `Claimed Staking Rewards`;
                case 'Transfer':
                    return `Transferred ${amount} ${token} to 0x...`;
                case 'Approve':
                    return `Approved ${amount} ${token} for spending`;
                default:
                    return `Processed ${amount} ${token} transaction`;
            }
        },
        generateRandomTransaction() {
            const type = this.generateRandomTransactionType();
            const token = this.generateRandomToken();
            const amount = this.generateRandomAmount();
            return {
                hash: this.generateRandomHash(),
                displayHash: this.generateRandomHash(),
                type,
                description: this.generateRandomTransactionDescription(type, amount, token),
                amount: `${amount} ${token}`,
                status: 'Confirmed',
                timestamp: Date.now() - Math.floor(Math.random() * 86400000),
                blockNumber: this.generateRandomBlockNumber()
            };
        },
        generateRandomNFT() {
            const rarities = ['Common', 'Rare', 'Epic', 'Legendary', 'Mythic'];
            const collections = ['Opus Genesis', 'Relics of DeFi', 'Cybernetic Artifacts', 'Digital Frontiers'];
            const rarity = rarities[Math.floor(Math.random() * rarities.length)];
            const collection = collections[Math.floor(Math.random() * collections.length)];
            const price = (Math.random() * 5 + 0.1).toFixed(2);
            const id = Math.floor(Math.random() * 1000);
            const rank = Math.floor(Math.random() * 100) + 1;
            const attributes = [
                { trait: 'Background', value: ['Neon Nebula', 'Deep Cyber', 'Starlight', 'Dark Matter'][Math.floor(Math.random() * 4)] },
                { trait: 'Core', value: ['Quantum Heart', 'Plasma Engine', 'Yield Multiplier', 'Zero Gas Transmutation'][Math.floor(Math.random() * 4)] },
                { trait: 'Aura', value: ['Chrono Pulse', 'Overclock', 'Starlight', 'Dark Matter'][Math.floor(Math.random() * 4)] }
            ];
            return {
                id,
                name: `${collection.split(' ')[0]} #${id.toString().padStart(3, '0')}`,
                collection,
                price: `${price} ETH`,
                priceVal: parseFloat(price),
                rarity,
                rank,
                image: '[38;5;208m[48;5;16m[1m[3m[4m[5m[7m[8m[9m[30m[31m[32m[33m[34m[35m[36m[37m[40m[41m[42m[43m[44m[45m[46m[47m[0m',
                attributes
            };
        },
        generateRandomChartData() {
            const labels = [];
            const prices = [];
            const volumes = [];
            const now = Date.now();
            const startPrice = state.market.price;

            for (let i = 0; i < 24; i++) {
                const timestamp = now - (24 - i) * 3600000;
                const date = new Date(timestamp);
                labels.push(date.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' }));
                prices.push((startPrice + (Math.random() * 100 - 50)).toFixed(2));
                volumes.push(Math.floor(Math.random() * 1000000));
            }

            return { labels, prices, volumes };
        },
        generateRandomOrderBook() {
            const bids = [];
            const asks = [];
            const midPrice = state.market.price;
            const spread = state.orderBook.spread;
            const maxDepth = state.orderBook.maxDepth;

            for (let i = 0; i < maxDepth; i++) {
                const bidPrice = (midPrice - (i + 1) * spread).toFixed(2);
                const askPrice = (midPrice + (i + 1) * spread).toFixed(2);
                const bidAmount = (Math.random() * 10 + 0.1).toFixed(4);
                const askAmount = (Math.random() * 10 + 0.1).toFixed(4);

                bids.push({ price: bidPrice, amount: bidAmount });
                asks.push({ price: askPrice, amount: askAmount });
            }

            return { bids, asks };
        },
        generateRandomMarketData() {
            const price = (state.market.price + (Math.random() * 100 - 50)).toFixed(2);
            const change24h = ((price - state.market.price) / state.market.price * 100).toFixed(2);
            const volume24h = Math.floor(Math.random() * 1000000000);
            const high24h = (parseFloat(price) + (Math.random() * 100)).toFixed(2);
            const low24h = (parseFloat(price) - (Math.random() * 100)).toFixed(2);

            return {
                price,
                change24h,
                volume24h,
                high24h,
                low24h,
                chartData: this.generateRandomChartData(),
                orderBook: this.generateRandomOrderBook()
            };
        },
        generateRandomStakingData() {
            const stakedOpus = state.staking.stakedOpus;
            const rewardRateApy = state.staking.rewardRateApy;
            const pendingRewards = (stakedOpus * rewardRateApy / 100 / 365).toFixed(4);
            const totalClaimed = (state.staking.totalClaimed + parseFloat(pendingRewards)).toFixed(2);
            const lastClaimed = Date.now();

            return {
                stakedOpus,
                rewardRateApy,
                pendingRewards,
                totalClaimed,
                lastClaimed
            };
        },
        generateRandomSwapData() {
            const fromToken = state.swap.fromToken;
            const toToken = state.swap.toToken;
            const fromAmount = state.swap.fromAmount;
            const toAmount = state.swap.toAmount;
            const slippage = state.swap.slippage;
            const priceImpact = state.swap.priceImpact;
            const routing = state.swap.routing;

            return {
                fromToken,
                toToken,
                fromAmount,
                toAmount,
                slippage,
                priceImpact,
                routing
            };
        },
        generateRandomGasData() {
            const slow = state.gas.slow;
            const standard = state.gas.standard;
            const fast = state.gas.fast;
            const current = state.gas.current;
            const selectedTier = state.gas.selectedTier;
            const unit = state.gas.unit;

            return {
                slow,
                standard,
                fast,
                current,
                selectedTier,
                unit
            };
        },
        generateRandomWalletData() {
            const connected = state.wallet.connected;
            const address = state.wallet.address;
            const balanceEth = state.wallet.balanceEth;
            const balanceUsdt = state.wallet.balanceUsdt;
            const balanceBtc = state.wallet.balanceBtc;
            const balanceSol = state.wallet.balanceSol;
            const balanceOpus = state.wallet.balanceOpus;
            const chainId = state.wallet.chainId;
            const networkName = state.wallet.networkName;
            const tokens = state.wallet.tokens.map(token => ({
                ...token,
                balance: (token.balance + (Math.random() * 2 - 1)).toFixed(token.decimals),
                price: (token.price + (Math.random() * 100 - 50)).toFixed(2),
                change24h: (token.change24h + (Math.random() * 2 - 1)).toFixed(2)
            }));

            return {
                connected,
                address,
                balanceEth,
                balanceUsdt,
                balanceBtc,
                balanceSol,
                balanceOpus,
                chainId,
                networkName,
                tokens
            };
        },
        generateRandomSettingsData() {
            const theme = state.settings.theme;
            const currency = state.settings.currency;
            const language = state.settings.language;
            const slippageTolerance = state.settings.slippageTolerance;
            const enableSounds = state.settings.enableSounds;
            const autoRefreshInterval = state.settings.autoRefreshInterval;

            return {
                theme,
                currency,
                language,
                slippageTolerance,
                enableSounds,
                autoRefreshInterval
            };
        },
        generateRandomData() {
            return {
                wallet: this.generateRandomWalletData(),
                gas: this.generateRandomGasData(),
                market: this.generateRandomMarketData(),
                swap: this.generateRandomSwapData(),
                staking: this.generateRandomStakingData(),
                nfts: Array(4).fill().map(() => this.generateRandomNFT()),
                transactions: Array(3).fill().map(() => this.generateRandomTransaction()),
                settings: this.generateRandomSettingsData()
            };
        }
    };

    // DOM Element Selectors
    const Selectors = {
        wallet: {
            connectButton: '#connect-wallet',
            address: '#wallet-address',
            balanceEth: '#balance-eth',
            balanceUsdt: '#balance-usdt',
            balanceBtc: '#balance-btc',
            balanceSol: '#balance-sol',
            balanceOpus: '#balance-opus',
            network: '#network-name',
            tokens: '#token-list',
            tokenTemplate: '#token-template'
        },
        gas: {
            slow: '#gas-slow',
            standard: '#gas-standard',
            fast: '#gas-fast',
            current: '#gas-current',
            tier: '#gas-tier'
        },
        market: {
            pair: '#market-pair',
            price: '#market-price',
            change24h: '#market-change-24h',
            volume24h: '#market-volume-24h',
            high24h: '#market-high-24h',
            low24h: '#market-low-24h',
            timeframe: '#market-timeframe',
            chart: '#market-chart',
            orderBook: '#order-book',
            bidTemplate: '#bid-template',
            askTemplate: '#ask-template'
        },
        swap: {
            fromToken: '#swap-from-token',
            toToken: '#swap-to-token',
            fromAmount: '#swap-from-amount',
            toAmount: '#swap-to-amount',
            slippage: '#swap-slippage',
            priceImpact: '#swap-price-impact',
            routing: '#swap-routing',
            swapButton: '#swap-button'
        },
        staking: {
            stakedOpus: '#staked-opus',
            rewardRateApy: '#reward-rate-apy',
            pendingRewards: '#pending-rewards',
            totalClaimed: '#total-claimed',
            lockPeriod: '#lock-period',
            lastClaimed: '#last-claimed',
            stakeButton: '#stake-button',
            claimButton: '#claim-button'
        },
        nfts: {
            container: '#nft-container',
            template: '#nft-template'
        },
        transactions: {
            container: '#transaction-container',
            template: '#transaction-template'
        },
        settings: {
            theme: '#settings-theme',
            currency: '#settings-currency',
            language: '#settings-language',
            slippageTolerance: '#settings-slippage-tolerance',
            enableSounds: '#settings-enable-sounds',
            autoRefreshInterval: '#settings-auto-refresh-interval'
        }
    };

    // DOM Element Cache
    const Elements = {
        wallet: {
            connectButton: document.querySelector(Selectors.wallet.connectButton),
            address: document.querySelector(Selectors.wallet.address),
            balanceEth: document.querySelector(Selectors.wallet.balanceEth),
            balanceUsdt: document.querySelector(Selectors.wallet.balanceUsdt),
            balanceBtc: document.querySelector(Selectors.wallet.balanceBtc),
            balanceSol: document.querySelector(Selectors.wallet.balanceSol),
            balanceOpus: document.querySelector(Selectors.wallet.balanceOpus),
            network: document.querySelector(Selectors.wallet.network),
            tokens: document.querySelector(Selectors.wallet.tokens),
            tokenTemplate: document.querySelector(Selectors.wallet.tokenTemplate)
        },
        gas: {
            slow: document.querySelector(Selectors.gas.slow),
            standard: document.querySelector(Selectors.gas.standard),
            fast: document.querySelector(Selectors.gas.fast),
            current: document.querySelector(Selectors.gas.current),
            tier: document.querySelector(Selectors.gas.tier)
        },
        market: {
            pair: document.querySelector(Selectors.market.pair),
            price: document.querySelector(Selectors.market.price),
            change24h: document.querySelector(Selectors.market.change24h),
            volume24h: document.querySelector(Selectors.market.volume24h),
            high24h: document.querySelector(Selectors.market.high24h),
            low24h: document.querySelector(Selectors.market.low24h),
            timeframe: document.querySelector(Selectors.market.timeframe),
            chart: document.querySelector(Selectors.market.chart),
            orderBook: document.querySelector(Selectors.market.orderBook),
            bidTemplate: document.querySelector(Selectors.market.bidTemplate),
            askTemplate: document.querySelector(Selectors.market.askTemplate)
        },
        swap: {
            fromToken: document.querySelector(Selectors.swap.fromToken),
            toToken: document.querySelector(Selectors.swap.toToken),
            fromAmount: document.querySelector(Selectors.swap.fromAmount),
            toAmount: document.querySelector(Selectors.swap.toAmount),
            slippage: document.querySelector(Selectors.swap.slippage),
            priceImpact: document.querySelector(Selectors.swap.priceImpact),
            routing: document.querySelector(Selectors.swap.routing),
            swapButton: document.querySelector(Selectors.swap.swapButton)
        },
        staking: {
            stakedOpus: document.querySelector(Selectors.staking.stakedOpus),
            rewardRateApy: document.querySelector(Selectors.staking.rewardRateApy),
            pendingRewards: document.querySelector(Selectors.staking.pendingRewards),
            totalClaimed: document.querySelector(Selectors.staking.totalClaimed),
            lockPeriod: document.querySelector(Selectors.staking.lockPeriod),
            lastClaimed: document.querySelector(Selectors.staking.lastClaimed),
            stakeButton: document.querySelector(Selectors.staking.stakeButton),
            claimButton: document.querySelector(Selectors.staking.claimButton)
        },
        nfts: {
            container: document.querySelector(Selectors.nfts.container),
            template: document.querySelector(Selectors.nfts.template)
        },
        transactions: {
            container: document.querySelector(Selectors.transactions.container),
            template: document.querySelector(Selectors.transactions.template)
        },
        settings: {
            theme: document.querySelector(Selectors.settings.theme),
            currency: document.querySelector(Selectors.settings.currency),
            language: document.querySelector(Selectors.settings.language),
            slippageTolerance: document.querySelector(Selectors.settings.slippageTolerance),
            enableSounds: document.querySelector(Selectors.settings.enableSounds),
            autoRefreshInterval: document.querySelector(Selectors.settings.autoRefreshInterval)
        }
    };

    // Event Handlers
    const Handlers = {
        wallet: {
            connect: () => {
                SoundEngine.play('click');
                state.wallet.connected = true;
                state.wallet.address = '0x742d35Cc6634C0532925a3b844Bc454e4438f44e';
                Render.wallet();
            }
        },
        gas: {
            selectTier: (tier) => {
                SoundEngine.play('click');
                state.gas.selectedTier = tier;
                state.gas.current = state.gas[tier];
                Render.gas();
            }
        },
        market: {
            selectPair: (pair) => {
                SoundEngine.play('click');
                state.market.selectedPair = pair;
                Render.market();
            },
            selectTimeframe: (timeframe) => {
                SoundEngine.play('click');
                state.market.timeframe = timeframe;
                Render.market();
            }
        },
        swap: {
            selectFromToken: (token) => {
                SoundEngine.play('click');
                state.swap.fromToken = token;
                Render.swap();
            },
            selectToToken: (token) => {
                SoundEngine.play('click');
                state.swap.toToken = token;
                Render.swap();
            },
            updateFromAmount: (amount) => {
                state.swap.fromAmount = amount;
                Render.swap();
            },
            updateToAmount: (amount) => {
                state.swap.toAmount = amount;
                Render.swap();
            },
            updateSlippage: (slippage) => {
                SoundEngine.play('click');
                state.swap.slippage = slippage;
                Render.swap();
            },
            swap: () => {
                SoundEngine.play('swap');
                const fromToken = state.wallet.tokens.find(token => token.symbol === state.swap.fromToken);
                const toToken = state.wallet.tokens.find(token => token.symbol === state.swap.toToken);
                const fromAmount = parseFloat(state.swap.fromAmount);
                const toAmount = parseFloat(state.swap.toAmount);

                if (fromToken && toToken && fromAmount && toAmount) {
                    fromToken.balance = (parseFloat(fromToken.balance) - fromAmount).toFixed(fromToken.decimals);
                    toToken.balance = (parseFloat(toToken.balance) + toAmount).toFixed(toToken.decimals);

                    const transaction = {
                        hash: Utils.generateRandomHash(),
                        displayHash: Utils.generateRandomHash(),
                        type: 'Swap',
                        description: `Swapped ${fromAmount} ${fromToken.symbol} for ${toAmount} ${toToken.symbol}`,
                        amount: `${fromAmount} ${fromToken.symbol}`,
                        status: 'Confirmed',
                        timestamp: Date.now(),
                        blockNumber: Utils.generateRandomBlockNumber()
                    };

                    state.transactions.unshift(transaction);
                    state.swap.fromAmount = '';
                    state.swap.toAmount = '';

                    Render.wallet();
                    Render.transactions();
                    Render.swap();
                }
            }
        },
        staking: {
            stake: () => {
                SoundEngine.play('success');
                const amount = parseFloat(state.swap.fromAmount);
                const token = state.wallet.tokens.find(token => token.symbol === 'OPUS');

                if (token && amount) {
                    token.balance = (parseFloat(token.balance) - amount).toFixed(token.decimals);
                    state.staking.stakedOpus = (parseFloat(state.staking.stakedOpus) + amount).toFixed(2);

                    const transaction = {
                        hash: Utils.generateRandomHash(),
                        displayHash: Utils.generateRandomHash(),
                        type: 'Stake',
                        description: `Staked ${amount} OPUS in Yield Vault`,
                        amount: `${amount} OPUS`,
                        status: 'Confirmed',
                        timestamp: Date.now(),
                        blockNumber: Utils.generateRandomBlockNumber()
                    };

                    state.transactions.unshift(transaction);
                    state.swap.fromAmount = '';

                    Render.wallet();
                    Render.transactions();
                    Render.staking();
                }
            },
            claim: () => {
                SoundEngine.play('success');
                const rewards = parseFloat(state.staking.pendingRewards);
                const token = state.wallet.tokens.find(token => token.symbol === 'OPUS');

                if (token && rewards) {
                    token.balance = (parseFloat(token.balance) + rewards).toFixed(token.decimals);
                    state.staking.totalClaimed = (parseFloat(state.staking.totalClaimed) + rewards).toFixed(2);
                    state.staking.pendingRewards = '0.0000';
                    state.staking.lastClaimed = Date.now();

                    const transaction = {
                        hash: Utils.generateRandomHash(),
                        displayHash: Utils.generateRandomHash(),
                        type: 'Claim',
                        description: 'Claimed Staking Rewards',
                        amount: `+${rewards} OPUS`,
                        status: 'Confirmed',
                        timestamp: Date.now(),
                        blockNumber: Utils.generateRandomBlockNumber()
                    };

                    state.transactions.unshift(transaction);

                    Render.wallet();
                    Render.transactions();
                    Render.staking();
                }
            }
        },
        nfts: {
            buy: (nft) => {
                SoundEngine.play('success');
                const token = state.wallet.tokens.find(token => token.symbol === 'ETH');

                if (token && nft.priceVal) {
                    token.balance = (parseFloat(token.balance) - nft.priceVal).toFixed(token.decimals);

                    const transaction = {
                        hash: Utils.generateRandomHash(),
                        displayHash: Utils.generateRandomHash(),
                        type: 'Buy NFT',
                        description: `Bought ${nft.name} for ${nft.price}`,
                        amount: `${nft.price}`,
                        status: 'Confirmed',
                        timestamp: Date.now(),
                        blockNumber: Utils.generateRandomBlockNumber()
                    };

                    state.transactions.unshift(transaction);
                    state.nfts = state.nfts.filter(item => item.id !== nft.id);

                    Render.wallet();
                    Render.transactions();
                    Render.nfts();
                }
            }
        },
        settings: {
            updateTheme: (theme) => {
                SoundEngine.play('click');
                state.settings.theme = theme;
                Render.settings();
            },
            updateCurrency: (currency) => {
                SoundEngine.play('click');
                state.settings.currency = currency;
                Render.settings();
            },
            updateLanguage: (language) => {
                SoundEngine.play('click');
                state.settings.language = language;
                Render.settings();
            },
            updateSlippageTolerance: (slippage) => {
                SoundEngine.play('click');
                state.settings.slippageTolerance = slippage;
                Render.settings();
            },
            toggleSounds: () => {
                SoundEngine.play('click');
                state.settings.enableSounds = !state.settings.enableSounds;
                Render.settings();
            },
            updateAutoRefreshInterval: (interval) => {
                SoundEngine.play('click');
                state.settings.autoRefreshInterval = interval;
                Render.settings();
            }
        }
    };

    // Render Functions
    const Render = {
        wallet: () => {
            if (Elements.wallet.connectButton) {
                Elements.wallet.connectButton.style.display = state.wallet.connected ? 'none' : 'block';
            }

            if (Elements.wallet.address) {
                Elements.wallet.address.textContent = state.wallet.connected ? Utils.formatAddress(state.wallet.address) : 'Not Connected';
            }

            if (Elements.wallet.balanceEth) {
                Elements.wallet.balanceEth.textContent = Utils.formatCurrency(state.wallet.balanceEth, '', 4);
            }

            if (Elements.wallet.balanceUsdt) {
                Elements.wallet.balanceUsdt.textContent = Utils.formatCurrency(state.wallet.balanceUsdt, '', 2);
            }

            if (Elements.wallet.balanceBtc) {
                Elements.wallet.balanceBtc.textContent = Utils.formatCurrency(state.wallet.balanceBtc, '', 4);
            }

            if (Elements.wallet.balanceSol) {
                Elements.wallet.balanceSol.textContent = Utils.formatCurrency(state.wallet.balanceSol, '', 4);
            }

            if (Elements.wallet.balanceOpus) {
                Elements.wallet.balanceOpus.textContent = Utils.formatCurrency(state.wallet.balanceOpus, '', 4);
            }

            if (Elements.wallet.network) {
                Elements.wallet.network.textContent = state.wallet.networkName;
            }

            if (Elements.wallet.tokens && Elements.wallet.tokenTemplate) {
                Elements.wallet.tokens.innerHTML = '';
                state.wallet.tokens.forEach(token => {
                    const tokenElement = Elements.wallet.tokenTemplate.content.cloneNode(true);
                    const symbolElement = tokenElement.querySelector('.token-symbol');
                    const nameElement = tokenElement.querySelector('.token-name');
                    const balanceElement = tokenElement.querySelector('.token-balance');
                    const priceElement = tokenElement.querySelector('.token-price');
                    const changeElement = tokenElement.querySelector('.token-change');

                    if (symbolElement) symbolElement.textContent = token.symbol;
                    if (nameElement) nameElement.textContent = token.name;
                    if (balanceElement) balanceElement.textContent = Utils.formatCurrency(token.balance, '', token.decimals);
                    if (priceElement) priceElement.textContent = Utils.formatCurrency(token.price, '$');
                    if (changeElement) {
                        changeElement.textContent = Utils.formatPercentage(token.change24h);
                        changeElement.className = `token-change ${token.change24h >= 0 ? 'positive' : 'negative'}`;
                    }

                    Elements.wallet.tokens.appendChild(tokenElement);
                });
            }
        },
        gas: () => {
            if (Elements.gas.slow) {
                Elements.gas.slow.textContent = `${state.gas.slow} ${state.gas.unit}`;
            }

            if (Elements.gas.standard) {
                Elements.gas.standard.textContent = `${state.gas.standard} ${state.gas.unit}`;
            }

            if (Elements.gas.fast) {
                Elements.gas.fast.textContent = `${state.gas.fast} ${state.gas.unit}`;
            }

            if (Elements.gas.current) {
                Elements.gas.current.textContent = `${state.gas.current} ${state.gas.unit}`;
            }

            if (Elements.gas.tier) {
                Elements.gas.tier.textContent = state.gas.selectedTier;
            }
        },
        market: () => {
            if (Elements.market.pair) {
                Elements.market.pair.textContent = state.market.selectedPair;
            }

            if (Elements.market.price) {
                Elements.market.price.textContent = Utils.formatCurrency(state.market.price, '$');
            }

            if (Elements.market.change24h) {
                Elements.market.change24h.textContent = Utils.formatPercentage(state.market.change24h);
                Elements.market.change24h.className = `market-change ${state.market.change24h >= 0 ? 'positive' : 'negative'}`;
            }

            if (Elements.market.volume24h) {
                Elements.market.volume24h.textContent = Utils.formatCurrency(state.market.volume24h, '$');
            }

            if (Elements.market.high24h) {
                Elements.market.high24h.textContent = Utils.formatCurrency(state.market.high24h, '$');
            }

            if (Elements.market.low24h) {
                Elements.market.low24h.textContent = Utils.formatCurrency(state.market.low24h, '$');
            }

            if (Elements.market.timeframe) {
                Elements.market.timeframe.textContent = state.market.timeframe;
            }

            if (Elements.market.chart) {
                // Render chart using state.market.chartData
            }

            if (Elements.market.orderBook && Elements.market.bidTemplate && Elements.market.askTemplate) {
                Elements.market.orderBook.innerHTML = '';
                state.orderBook.bids.forEach(bid => {
                    const bidElement = Elements.market.bidTemplate.content.cloneNode(true);
                    const priceElement = bidElement.querySelector('.bid-price');
                    const amountElement = bidElement.querySelector('.bid-amount');

                    if (priceElement) priceElement.textContent = Utils.formatCurrency(bid.price, '$');
                    if (amountElement) amountElement.textContent = Utils.formatCurrency(bid.amount, '', 4);

                    Elements.market.orderBook.appendChild(bidElement);
                });

                state.orderBook.asks.forEach(ask => {
                    const askElement = Elements.market.askTemplate.content.cloneNode(true);
                    const priceElement = askElement.querySelector('.ask-price');
                    const amountElement = askElement.querySelector('.ask-amount');

                    if (priceElement) priceElement.textContent = Utils.formatCurrency(ask.price, '$');
                    if (amountElement) amountElement.textContent = Utils.formatCurrency(ask.amount, '', 4);

                    Elements.market.orderBook.appendChild(askElement);
                });
            }
        },
        swap: () => {
            if (Elements.swap.fromToken) {
                Elements.swap.fromToken.textContent = state.swap.fromToken;
            }

            if (Elements.swap.toToken) {
                Elements.swap.toToken.textContent = state.swap.toToken;
            }

            if (Elements.swap.fromAmount) {
                Elements.swap.fromAmount.value = state.swap.fromAmount;
            }

            if (Elements.swap.toAmount) {
                Elements.swap.toAmount.value = state.swap.toAmount;
            }

            if (Elements.swap.slippage) {
                Elements.swap.slippage.textContent = Utils.formatPercentage(state.swap.slippage);
            }

            if (Elements.swap.priceImpact) {
                Elements.swap.priceImpact.textContent = Utils.formatPercentage(state.swap.priceImpact);
            }

            if (Elements.swap.routing) {
                Elements.swap.routing.textContent = state.swap.routing;
            }
        },
        staking: () => {
            if (Elements.staking.stakedOpus) {
                Elements.staking.stakedOpus.textContent = Utils.formatCurrency(state.staking.stakedOpus, '', 2);
            }

            if (Elements.staking.rewardRateApy) {
                Elements.staking.rewardRateApy.textContent = Utils.formatPercentage(state.staking.rewardRateApy);
            }

            if (Elements.staking.pendingRewards) {
                Elements.staking.pendingRewards.textContent = Utils.formatCurrency(state.staking.pendingRewards, '', 4);
            }

            if (Elements.staking.totalClaimed) {
                Elements.staking.totalClaimed.textContent = Utils.formatCurrency(state.staking.totalClaimed, '', 2);
            }

            if (Elements.staking.lockPeriod) {
                Elements.staking.lockPeriod.textContent = `${state.staking.lockPeriodDays} days`;
            }

            if (Elements.staking.lastClaimed) {
                Elements.staking.lastClaimed.textContent = Utils.formatDate(state.staking.lastClaimed);
            }
        },
        nfts: () => {
            if (Elements.nfts.container && Elements.nfts.template) {
                Elements.nfts.container.innerHTML = '';
                state.nfts.forEach(nft => {
                    const nftElement = Elements.nfts.template.content.cloneNode(true);
                    const imageElement = nftElement.querySelector('.nft-image');
                    const nameElement = nftElement.querySelector('.nft-name');
                    const collectionElement = nftElement.querySelector('.nft-collection');
                    const priceElement = nftElement.querySelector('.nft-price');
                    const rarityElement = nftElement.querySelector('.nft-rarity');
                    const rankElement = nftElement.querySelector('.nft-rank');
                    const attributesElement = nftElement.querySelector('.nft-attributes');
                    const buyButton = nftElement.querySelector('.nft-buy-button');

                    if (imageElement) imageElement.textContent = nft.image;
                    if (nameElement) nameElement.textContent = nft.name;
                    if (collectionElement) collectionElement.textContent = nft.collection;
                    if (priceElement) priceElement.textContent = nft.price;
                    if (rarityElement) rarityElement.textContent = nft.rarity;
                    if (rankElement) rankElement.textContent = `#${nft.rank}`;

                    if (attributesElement) {
                        attributesElement.innerHTML = '';
                        nft.attributes.forEach(attribute => {
                            const attributeElement = document.createElement('div');
                            attributeElement.className = 'nft-attribute';
                            attributeElement.innerHTML = `<strong>${attribute.trait}:</strong> ${attribute.value}`;
                            attributesElement.appendChild(attributeElement);
                        });
                    }

                    if (buyButton) {
                        buyButton.addEventListener('click', () => Handlers.nfts.buy(nft));
                    }

                    Elements.nfts.container.appendChild(nftElement);
                });
            }
        },
        transactions: () => {
            if (Elements.transactions.container && Elements.transactions.template) {
                Elements.transactions.container.innerHTML = '';
                state.transactions.forEach(transaction => {
                    const transactionElement = Elements.transactions.template.content.cloneNode(true);
                    const hashElement = transactionElement.querySelector('.transaction-hash');
                    const typeElement = transactionElement.querySelector('.transaction-type');
                    const descriptionElement = transactionElement.querySelector('.transaction-description');
                    const amountElement = transactionElement.querySelector('.transaction-amount');
                    const statusElement = transactionElement.querySelector('.transaction-status');
                    const timestampElement = transactionElement.querySelector('.transaction-timestamp');
                    const blockNumberElement = transactionElement.querySelector('.transaction-block-number');

                    if (hashElement) hashElement.textContent = transaction.displayHash;
                    if (typeElement) typeElement.textContent = transaction.type;
                    if (descriptionElement) descriptionElement.textContent = transaction.description;
                    if (amountElement) amountElement.textContent = transaction.amount;
                    if (statusElement) statusElement.textContent = transaction.status;
                    if (timestampElement) timestampElement.textContent = Utils.formatDate(transaction.timestamp);
                    if (blockNumberElement) blockNumberElement.textContent = transaction.blockNumber;

                    Elements.transactions.container.appendChild(transactionElement);
                });
            }
        },
        settings: () => {
            if (Elements.settings.theme) {
                Elements.settings.theme.value = state.settings.theme;
            }

            if (Elements.settings.currency) {
                Elements.settings.currency.value = state.settings.currency;
            }

            if (Elements.settings.language) {
                Elements.settings.language.value = state.settings.language;
            }

            if (Elements.settings.slippageTolerance) {
                Elements.settings.slippageTolerance.value = state.settings.slippageTolerance;
            }

            if (Elements.settings.enableSounds) {
                Elements.settings.enableSounds.checked = state.settings.enableSounds;
            }

            if (Elements.settings.autoRefreshInterval) {
                Elements.settings.autoRefreshInterval.value = state.settings.autoRefreshInterval;
            }
        },
        all: () => {
            Render.wallet();
            Render.gas();
            Render.market();
            Render.swap();
            Render.staking();
            Render.nfts();
            Render.transactions();
            Render.settings();
        }
    };

    // Event Listeners
    const Listeners = {
        wallet: () => {
            if (Elements.wallet.connectButton) {
                Elements.wallet.connectButton.addEventListener('click', Handlers.wallet.connect);
            }
        },
        gas: () => {
            if (Elements.gas.slow) {
                Elements.gas.slow.addEventListener('click', () => Handlers.gas.selectTier('slow'));
            }

            if (Elements.gas.standard) {
                Elements.gas.standard.addEventListener('click', () => Handlers.gas.selectTier('standard'));
            }

            if (Elements.gas.fast) {
                Elements.gas.fast.addEventListener('click', () => Handlers.gas.selectTier('fast'));
            }
        },
        market: () => {
            if (Elements.market.pair) {
                Elements.market.pair.addEventListener('click', () => Handlers.market.selectPair('ETH/USDT'));
            }

            if (Elements.market.timeframe) {
                Elements.market.timeframe.addEventListener('click', () => Handlers.market.selectTimeframe('24H'));
            }
        },
        swap: () => {
            if (Elements.swap.fromToken) {
                Elements.swap.fromToken.addEventListener('click', () => Handlers.swap.selectFromToken('ETH'));
            }

            if (Elements.swap.toToken) {
                Elements.swap.toToken.addEventListener('click', () => Handlers.swap.selectToToken('USDT'));
            }

            if (Elements.swap.fromAmount) {
                Elements.swap.fromAmount.addEventListener('input', (e) => Handlers.swap.updateFromAmount(e.target.value));
            }

            if (Elements.swap.toAmount) {
                Elements.swap.toAmount.addEventListener('input', (e) => Handlers.swap.updateToAmount(e.target.value));
            }

            if (Elements.swap.slippage) {
                Elements.swap.slippage.addEventListener('click', () => Handlers.swap.updateSlippage(0.5));
            }

            if (Elements.swap.swapButton) {
                Elements.swap.swapButton.addEventListener('click', Handlers.swap.swap);
            }
        },
        staking: () => {
            if (Elements.staking.stakeButton) {
                Elements.staking.stakeButton.addEventListener('click', Handlers.staking.stake);
            }

            if (Elements.staking.claimButton) {
                Elements.staking.claimButton.addEventListener('click', Handlers.staking.claim);
            }
        },
        settings: () => {
            if (Elements.settings.theme) {
                Elements.settings.theme.addEventListener('change', (e) => Handlers.settings.updateTheme(e.target.value));
            }

            if (Elements.settings.currency) {
                Elements.settings.currency.addEventListener('change', (e) => Handlers.settings.updateCurrency(e.target.value));
            }

            if (Elements.settings.language) {
                Elements.settings.language.addEventListener('change', (e) => Handlers.settings.updateLanguage(e.target.value));
            }

            if (Elements.settings.slippageTolerance) {
                Elements.settings.slippageTolerance.addEventListener('change', (e) => Handlers.settings.updateSlippageTolerance(e.target.value));
            }

            if (Elements.settings.enableSounds) {
                Elements.settings.enableSounds.addEventListener('change', Handlers.settings.toggleSounds);
            }

            if (Elements.settings.autoRefreshInterval) {
                Elements.settings.autoRefreshInterval.addEventListener('change', (e) => Handlers.settings.updateAutoRefreshInterval(e.target.value));
            }
        },
        all: () => {
            Listeners.wallet();
            Listeners.gas();
            Listeners.market();
            Listeners.swap();
            Listeners.staking();
            Listeners.settings();
        }
    };

    // Auto-refresh functionality
    const AutoRefresh = {
        intervalId: null,
        start: () => {
            AutoRefresh.stop();
            AutoRefresh.intervalId = setInterval(() => {
                const newData = Utils.generateRandomData();
                state.wallet = newData.wallet;
                state.gas = newData.gas;
                state.market = newData.market;
                state.swap = newData.swap;
                state.staking = newData.staking;
                state.nfts = newData.nfts;
                state.transactions = newData.transactions;
                state.settings = newData.settings;
                Render.all();
            }, state.settings.autoRefreshInterval);
        },
        stop: () => {
            if (AutoRefresh.intervalId) {
                clearInterval(AutoRefresh.intervalId);
                AutoRefresh.intervalId = null;
            }
        }
    };

    // Initialize the application
    const init = () => {
        Render.all();
        Listeners.all();
        AutoRefresh.start();
    };

    // Expose the init function to the global scope
    window.MagnumOpus = {
        init,
        state,
        Utils,
        Render,
        Handlers,
        AutoRefresh
    };

    // Initialize the application when the DOM is loaded
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
    } else {
        init();
    }
})();
