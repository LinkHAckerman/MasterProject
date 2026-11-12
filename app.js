(function () {
    'use strict';

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
                { symbol: 'ETH', name: 'Ethereum', balance: 14.852, decimals: 18, price: 3450.75, icon: 'ETH' },
                { symbol: 'USDT', name: 'Tether USD', balance: 42500.00, decimals: 6, price: 1.00, icon: 'USDT' },
                { symbol: 'BTC', name: 'Bitcoin', balance: 0.65, decimals: 8, price: 64200.00, icon: 'BTC' },
                { symbol: 'SOL', name: 'Solana', balance: 12.5, decimals: 9, price: 145.20, icon: 'SOL' },
                { symbol: 'OPUS', name: 'Magnum Opus Governance', balance: 10000.0, decimals: 18, price: 0.45, icon: 'OPUS' }
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
                name: 'Cyber Opus 001',
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
                name: 'Cyber Opus 042',
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
                name: 'Aether Shield 108',
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

    const formatCurrency = (value, symbol) => {
        const safeValue = Number(value) || 0;
        const options = {
            minimumFractionDigits: 2,
            maximumFractionDigits: 2
        };
        const formatted = safeValue.toLocaleString('en-US', options);
        return symbol ? formatted + ' ' + symbol : formatted;
    };

    const formatTokenAmount = (value, decimals) => {
        const safeValue = Number(value) || 0;
        const divisor = Math.pow(10, Number(decimals) || 18);
        const normalized = safeValue / divisor;
        return normalized.toFixed(4);
    };

    const getPortfolioValue = () => {
        let total = 0;
        const tokens = state.wallet.tokens || [];
        for (let i = 0; i < tokens.length; i++) {
            const token = tokens[i];
            total += (Number(token.balance) || 0) * (Number(token.price) || 0);
        }
        const ethPrice = Number(state.market.price) || 0;
        total += (Number(state.wallet.balanceEth) || 0) * ethPrice;
        const usdtValue = (Number(state.wallet.balanceUsdt) || 0) / (Number(state.market.price) || 1);
        total += usdtValue;
        const btcToken = state.wallet.tokens.find(t => t.symbol === 'BTC');
        const solToken = state.wallet.tokens.find(t => t.symbol === 'SOL');
        const opusToken = state.wallet.tokens.find(t => t.symbol === 'OPUS');
        const btcValue = (Number(state.wallet.balanceBtc) || 0) * (Number(btcToken?.price) || 0);
        total += btcValue;
        const solValue = (Number(state.wallet.balanceSol) || 0) * (Number(solToken?.price) || 0);
        total += solValue;
        const opusValue = (Number(state.wallet.balanceOpus) || 0) * (Number(opusToken?.price) || 0);
        total += opusValue;
        return total;
    };

    const renderPortfolio = () => {
        const valueElement = document.getElementById('portfolioValue');
        if (valueElement) {
            valueElement.textContent = formatCurrency(getPortfolioValue(), 'USD');
        }
    };

    const renderMarket = () => {
        const priceElement = document.getElementById('marketPrice');
        if (priceElement) {
            const pairParts = state.market.selectedPair.split('/');
            const base = pairParts[0] || 'ETH';
            const quote = pairParts[1] || 'USDT';
            priceElement.textContent = formatCurrency(state.market.price, base + '/' + quote);
        }
    };

    const renderSwap = () => {
        const fromElement = document.getElementById('swapFromAmount');
        const toElement = document.getElementById('swapToAmount');
        if (fromElement && toElement) {
            const fromAmount = Number(fromElement.value) || 0;
            const rate = Number(state.market.price) || 1;
            const expected = fromAmount * rate;
            toElement.value = expected.toFixed(2);
        }
    };

    const renderStaking = () => {
        const claimButton = document.getElementById('claimRewards');
        if (claimButton) {
            claimButton.disabled = !(state.staking.pendingRewards > 0);
        }
    };

    const renderNfts = () => {
        const grid = document.getElementById('nftGrid');
        if (!grid) {
            return;
        }
        grid.innerHTML = '';
        const nfts = state.nfts || [];
        for (let i = 0; i < nfts.length; i++) {
            const nft = nfts[i];
            const card = document.createElement('div');
            card.className = 'nftCard';
            card.innerHTML = '<div class="nftName">' + nft.name + '</div><div class="nftPrice">' + nft.price + '</div>';
            grid.appendChild(card);
        }
    };

    const renderTransactions = () => {
        const list = document.getElementById('transactionList');
        if (!list) {
            return;
        }
        list.innerHTML = '';
        const transactions = state.transactions || [];
        for (let i = 0; i < transactions.length; i++) {
            const tx = transactions[i];
            const row = document.createElement('div');
            row.className = 'transactionRow';
            row.innerHTML = '<span>' + tx.type + '</span><span>' + tx.status + '</span>';
            list.appendChild(row);
        }
    };

    const updateUI = () => {
        renderPortfolio();
        renderMarket();
        renderSwap();
        renderStaking();
        renderNfts();
        renderTransactions();
    };

    const init = () => {
        updateUI();
        const claimButton = document.getElementById('claimRewards');
        if (claimButton) {
            claimButton.addEventListener('click', () => {
                state.staking.pendingRewards = 0;
                state.staking.lastClaimed = Date.now();
                updateUI();
            });
        }
        const swapFrom = document.getElementById('swapFromAmount');
        if (swapFrom) {
            swapFrom.addEventListener('input', () => {
                renderSwap();
            });
        }
    };

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
    } else {
        init();
    }
})();