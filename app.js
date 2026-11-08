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
            const oscillator = audioCtx.createOscillator();
            oscillator.type = 'sine';
            oscillator.frequency.value = 440;
            oscillator.connect(audioCtx.destination);
            oscillator.start();
            oscillator.stop(audioCtx.currentTime + 1);
        } catch (error) {
            console.error('Error playing sound:', error);
        }
    }

    // ---------------------------------------------------------------------
    // Market Data Updates
    // ---------------------------------------------------------------------
    function updateMarketData() {
        // Simulate market data updates
        state.market.price = Math.random() * 10000;
        state.market.change24h = Math.random() * 10;
        state.market.volume24h = Math.random() * 1000000000;
        state.market.high24h = Math.random() * 10000;
        state.market.low24h = Math.random() * 10000;
    }

    // ---------------------------------------------------------------------
    // Gas Price Updates
    // ---------------------------------------------------------------------
    function updateGasPrice() {
        // Simulate gas price updates
        state.gas.slow = Math.random() * 10;
        state.gas.standard = Math.random() * 10;
        state.gas.fast = Math.random() * 10;
    }

    // ---------------------------------------------------------------------
    // Staking Rewards Updates
    // ---------------------------------------------------------------------
    function updateStakingRewards() {
        // Simulate staking rewards updates
        state.staking.stakedOpus = Math.random() * 10000;
        state.staking.rewardRateApy = Math.random() * 100;
        state.staking.pendingRewards = Math.random() * 100;
    }

    // ---------------------------------------------------------------------
    // Initialize Intervals
    // ---------------------------------------------------------------------
    function initIntervals() {
        marketInterval = setInterval(updateMarketData, 1000);
        gasInterval = setInterval(updateGasPrice, 1000);
        stakingInterval = setInterval(updateStakingRewards, 1000);
    }

    // ---------------------------------------------------------------------
    // Main Initialization
    // ---------------------------------------------------------------------
    function init() {
        initIntervals();
        initAudio();
    }

    init();
})();