-- PostgreSQL schema for Magnum Opus: Enhanced with support for NFTs, DeFi contracts, and multi-chain asset tracking
-- Updated for full-stack Web3 ecosystem integration

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Enum for transaction status
CREATE TYPE tx_status AS ENUM ('pending', 'confirmed', 'failed', 'reverted');

-- Enum for transaction types
CREATE TYPE tx_type AS ENUM ('transfer', 'swap', 'stake', 'unstake', 'deposit', 'withdraw', 'mint', 'burn', 'liquidation');

-- Enum for order side
CREATE TYPE order_side AS ENUM ('buy', 'sell');

-- Enum for order type
CREATE TYPE order_type AS ENUM ('limit', 'market', 'stop_loss', 'take_profit');

-- Enum for order status
CREATE TYPE order_status AS ENUM ('open', 'filled', 'partially_filled', 'cancelled', 'expired');

-- Enum for position status
CREATE TYPE position_status AS ENUM ('active', 'closed', 'liquidated');

-- Enum for lending protocol action
CREATE TYPE lending_action AS ENUM ('supply', 'borrow', 'repay', 'withdraw', 'liquidate');

-- Helper trigger function to auto-update the updated_at timestamp
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Core Users Table
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email VARCHAR(255) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    full_name VARCHAR(255),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    status VARCHAR(20) NOT NULL DEFAULT 'active',
    is_verified BOOLEAN NOT NULL DEFAULT FALSE,
    verification_token VARCHAR(255),
    verification_expires TIMESTAMPTZ,
    metadata JSONB DEFAULT '{}'::jsonb,
    CONSTRAINT chk_user_status CHECK (status IN ('active', 'suspended', 'deleted', 'verified'))
);

CREATE TRIGGER trg_users_updated_at
BEFORE UPDATE ON users
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- Wallet Hierarchy and Network Support
CREATE TABLE IF NOT EXISTS wallets (
    wallet_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    address VARCHAR(66) NOT NULL UNIQUE,
    network VARCHAR(30) NOT NULL,
    label VARCHAR(100),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'::jsonb,
    CONSTRAINT chk_network CHECK (network IN ('Ethereum', 'Polygon', 'BinanceSmartChain', 'Solana', 'Avalanche', 'PolygonZK', 'Arbitrum', 'Optimism', 'Base', 'Mantle'))
);

CREATE TRIGGER trg_wallets_updated_at
BEFORE UPDATE ON wallets
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- Token and NFT Classification
CREATE TABLE IF NOT EXISTS assets (
    asset_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    symbol VARCHAR(20) NOT NULL,
    name VARCHAR(100) NOT NULL,
    decimals SMALLINT NOT NULL CHECK (decimals BETWEEN 0 AND 30),
    contract_address VARCHAR(66),
    network VARCHAR(30) NOT NULL,
    is_nft BOOLEAN NOT NULL DEFAULT FALSE,
    is_token BOOLEAN NOT NULL DEFAULT TRUE,
    token_type VARCHAR(50) CHECK (token_type IN ('ERC20', 'ERC721', 'ERC1155', 'BEP20', 'BEP2', 'BSCToken', 'SolanaSPL', 'AVAXToken', 'PolygonToken', 'WrappedToken')),
    total_supply NUMERIC(38,18) DEFAULT 0,
    price_usd NUMERIC(24,8) DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (symbol, network),
    CONSTRAINT chk_token_network CHECK (network IN ('Ethereum', 'Polygon', 'BinanceSmartChain', 'Solana', 'Avalanche', 'PolygonZK', 'Arbitrum', 'Optimism', 'Base', 'Mantle'))
);

CREATE TRIGGER trg_assets_updated_at
BEFORE UPDATE ON assets
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- NFT Collection and Token Metadata
CREATE TABLE IF NOT EXISTS nft_collections (
    collection_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    asset_id UUID NOT NULL REFERENCES assets(asset_id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    image_url VARCHAR(512),
    metadata_uri VARCHAR(512),
    royalty_fee_bps INT DEFAULT 250 CHECK (royalty_fee_bps BETWEEN 0 AND 10000),
    attributes JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (asset_id)
);

CREATE TRIGGER trg_nft_collections_updated_at
BEFORE UPDATE ON nft_collections
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- NFT Token IDs and Ownership
CREATE TABLE IF NOT EXISTS nft_tokens (
    token_id VARCHAR(66) PRIMARY KEY,
    collection_id UUID NOT NULL REFERENCES nft_collections(collection_id) ON DELETE CASCADE,
    token_index BIGINT NOT NULL,
    owner_address VARCHAR(66) NOT NULL,
    metadata_uri VARCHAR(512),
    attributes JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (collection_id, token_index)
);

CREATE TRIGGER trg_nft_tokens_updated_at
BEFORE UPDATE ON nft_tokens
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- Balances (current snapshot per wallet per asset)
CREATE TABLE IF NOT EXISTS balances (
    balance_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    wallet_id UUID NOT NULL REFERENCES wallets(wallet_id) ON DELETE CASCADE,
    asset_id UUID NOT NULL REFERENCES assets(asset_id) ON DELETE CASCADE,
    amount NUMERIC(38,18) NOT NULL DEFAULT 0,
    locked_amount NUMERIC(38,18) NOT NULL DEFAULT 0,
    usd_value NUMERIC(24,8) DEFAULT 0,
    last_updated TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (wallet_id, asset_id)
);

CREATE INDEX idx_balances_wallet ON balances(wallet_id);
CREATE INDEX idx_balances_asset ON balances(asset_id);

-- Transaction History (immutable ledger)
CREATE TABLE IF NOT EXISTS transactions (
    tx_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    wallet_id UUID NOT NULL REFERENCES wallets(wallet_id) ON DELETE CASCADE,
    tx_hash VARCHAR(132) NOT NULL UNIQUE,
    network VARCHAR(30) NOT NULL,
    tx_type tx_type NOT NULL,
    status tx_status NOT NULL DEFAULT 'pending',
    from_address VARCHAR(66),
    to_address VARCHAR(66),
    asset_id UUID REFERENCES assets(asset_id) ON DELETE SET NULL,
    amount NUMERIC(38,18) NOT NULL DEFAULT 0,
    gas_fee NUMERIC(38,18) DEFAULT 0,
    gas_price NUMERIC(38,18) DEFAULT 0,
    block_number BIGINT,
    block_hash VARCHAR(132),
    confirmation_count INT DEFAULT 0,
    required_confirmations INT DEFAULT 12,
    error_message TEXT,
    metadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    confirmed_at TIMESTAMPTZ,
    CONSTRAINT chk_tx_network CHECK (network IN ('Ethereum', 'Polygon', 'BinanceSmartChain', 'Solana', 'Avalanche', 'PolygonZK', 'Arbitrum', 'Optimism', 'Base', 'Mantle'))
);

CREATE INDEX idx_transactions_wallet ON transactions(wallet_id);
CREATE INDEX idx_transactions_hash ON transactions(tx_hash);
CREATE INDEX idx_transactions_status ON transactions(status);
CREATE INDEX idx_transactions_created ON transactions(created_at DESC);
CREATE INDEX idx_transactions_network ON transactions(network);

-- Order Book (DEX trading engine)
CREATE TABLE IF NOT EXISTS orders (
    order_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    wallet_id UUID NOT NULL REFERENCES wallets(wallet_id) ON DELETE CASCADE,
    pair_id UUID NOT NULL REFERENCES trading_pairs(pair_id) ON DELETE CASCADE,
    side order_side NOT NULL,
    order_type order_type NOT NULL,
    status order_status NOT NULL DEFAULT 'open',
    price NUMERIC(36,18) NOT NULL,
    quantity NUMERIC(38,18) NOT NULL,
    filled_quantity NUMERIC(38,18) NOT NULL DEFAULT 0,
    remaining_quantity NUMERIC(38,18) NOT NULL,
    stop_price NUMERIC(36,18),
    fee_rate NUMERIC(10,8) DEFAULT 0.003,
    client_order_id VARCHAR(64),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ,
    metadata JSONB DEFAULT '{}'::jsonb
);

CREATE TRIGGER trg_orders_updated_at
BEFORE UPDATE ON orders
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

CREATE INDEX idx_orders_wallet ON orders(wallet_id);
CREATE INDEX idx_orders_pair ON orders(pair_id);
CREATE INDEX idx_orders_status ON orders(status);
CREATE INDEX idx_orders_side ON orders(side);
CREATE INDEX idx_orders_price ON orders(price);

-- Trading Pairs
CREATE TABLE IF NOT EXISTS trading_pairs (
    pair_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    base_asset_id UUID NOT NULL REFERENCES assets(asset_id) ON DELETE CASCADE,
    quote_asset_id UUID NOT NULL REFERENCES assets(asset_id) ON DELETE CASCADE,
    symbol VARCHAR(20) NOT NULL,
    base_decimals SMALLINT NOT NULL,
    quote_decimals SMALLINT NOT NULL,
    tick_size NUMERIC(36,18) DEFAULT 0.00000001,
    lot_size NUMERIC(38,18) DEFAULT 0.00000001,
    min_quantity NUMERIC(38,18) DEFAULT 0,
    max_quantity NUMERIC(38,18),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (base_asset_id, quote_asset_id)
);

CREATE TRIGGER trg_trading_pairs_updated_at
BEFORE UPDATE ON trading_pairs
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

CREATE INDEX idx_trading_pairs_symbol ON trading_pairs(symbol);

-- Order Trades (filled/cancelled trades)
CREATE TABLE IF NOT EXISTS trades (
    trade_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    pair_id UUID NOT NULL REFERENCES trading_pairs(pair_id) ON DELETE CASCADE,
    buyer_order_id UUID NOT NULL REFERENCES orders(order_id) ON DELETE CASCADE,
    seller_order_id UUID NOT NULL REFERENCES orders(order_id) ON DELETE CASCADE,
    buyer_wallet_id UUID NOT NULL REFERENCES wallets(wallet_id) ON DELETE CASCADE,
    seller_wallet_id UUID NOT NULL REFERENCES wallets(wallet_id) ON DELETE CASCADE,
    price NUMERIC(36,18) NOT NULL,
    quantity NUMERIC(38,18) NOT NULL,
    quote_quantity NUMERIC(38,18) NOT NULL,
    buyer_fee NUMERIC(38,18) DEFAULT 0,
    seller_fee NUMERIC(38,18) DEFAULT 0,
    tx_hash VARCHAR(132),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_trades_pair ON trades(pair_id);
CREATE INDEX idx_trades_buyer ON trades(buyer_wallet_id);
CREATE INDEX idx_trades_seller ON trades(seller_wallet_id);
CREATE INDEX idx_trades_created ON trades(created_at DESC);

-- Yield Farming / Staking Positions
CREATE TABLE IF NOT EXISTS staking_positions (
    position_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    wallet_id UUID NOT NULL REFERENCES wallets(wallet_id) ON DELETE CASCADE,
    pool_id UUID NOT NULL REFERENCES staking_pools(pool_id) ON DELETE CASCADE,
    asset_id UUID NOT NULL REFERENCES assets(asset_id) ON DELETE CASCADE,
    staked_amount NUMERIC(38,18) NOT NULL DEFAULT 0,
    rewards_accumulated NUMERIC(38,18) NOT NULL DEFAULT 0,
    rewards_claimed NUMERIC(38,18) NOT NULL DEFAULT 0,
    entry_price NUMERIC(24,8),
    current_value NUMERIC(24,8),
    apy NUMERIC(10,4),
    status VARCHAR(20) NOT NULL DEFAULT 'active',
    started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ended_at TIMESTAMPTZ,
    CONSTRAINT chk_position_status CHECK (status IN ('active', 'completed', 'withdrawn'))
);

CREATE TRIGGER trg_staking_positions_updated_at
BEFORE UPDATE ON staking_positions
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

CREATE INDEX idx_staking_positions_wallet ON staking_positions(wallet_id);
CREATE INDEX idx_staking_positions_pool ON staking_positions(pool_id);

-- Staking Pools
CREATE TABLE IF NOT EXISTS staking_pools (
    pool_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    asset_id UUID NOT NULL REFERENCES assets(asset_id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    reward_token_id UUID REFERENCES assets(asset_id) ON DELETE SET NULL,
    reward_rate NUMERIC(38,18) DEFAULT 0,
    apy NUMERIC(10,4) DEFAULT 0,
    lockup_period_days INT DEFAULT 0,
    min_stake NUMERIC(38,18) DEFAULT 0,
    max_stake NUMERIC(38,18),
    total_staked NUMERIC(38,18) DEFAULT 0,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_staking_pools_updated_at
BEFORE UPDATE ON staking_pools
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- Lending & Borrowing (DeFi)
CREATE TABLE IF NOT EXISTS lending_positions (
    position_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    wallet_id UUID NOT NULL REFERENCES wallets(wallet_id) ON DELETE CASCADE,
    supply_asset_id UUID NOT NULL REFERENCES assets(asset_id) ON DELETE CASCADE,
    borrow_asset_id UUID REFERENCES assets(asset_id) ON DELETE CASCADE,
    supply_amount NUMERIC(38,18) DEFAULT 0,
    borrow_amount NUMERIC(38,18) DEFAULT 0,
    collateral_factor NUMERIC(5,4) DEFAULT 0.75,
    liquidation_threshold NUMERIC(5,4) DEFAULT 0.85,
    health_factor NUMERIC(10,4),
    supply_apy NUMERIC(10,4),
    borrow_apy NUMERIC(10,4),
    status position_status NOT NULL DEFAULT 'active',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    closed_at TIMESTAMPTZ
);

CREATE TRIGGER trg_lending_positions_updated_at
BEFORE UPDATE ON lending_positions
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

CREATE INDEX idx_lending_positions_wallet ON lending_positions(wallet_id);
CREATE INDEX idx_lending_positions_status ON lending_positions(status);

-- Lending Market Rates
CREATE TABLE IF NOT EXISTS lending_rates (
    rate_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    asset_id UUID NOT NULL REFERENCES assets(asset_id) ON DELETE CASCADE,
    supply_rate NUMERIC(10,4) DEFAULT 0,
    borrow_rate NUMERIC(10,4) DEFAULT 0,
    utilization_rate NUMERIC(10,4) DEFAULT 0,
    total_supply NUMERIC(38,18) DEFAULT 0,
    total_borrow NUMERIC(38,18) DEFAULT 0,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (asset_id)
);

CREATE TRIGGER trg_lending_rates_updated_at
BEFORE UPDATE ON lending_rates
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- Price Oracle Feeds
CREATE TABLE IF NOT EXISTS price_feeds (
    feed_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    asset_id UUID NOT NULL REFERENCES assets(asset_id) ON DELETE CASCADE,
    source VARCHAR(50) NOT NULL,
    price_usd NUMERIC(24,8) NOT NULL,
    confidence NUMERIC(10,4),
    timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_price_feeds_asset ON price_feeds(asset_id);
CREATE INDEX idx_price_feeds_timestamp ON price_feeds(timestamp DESC);

-- API Keys and Sessions
CREATE TABLE IF NOT EXISTS api_keys (
    key_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    key_hash VARCHAR(255) NOT NULL UNIQUE,
    name VARCHAR(100),
    permissions JSONB DEFAULT '[]'::jsonb,
    rate_limit INT DEFAULT 1000,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    last_used TIMESTAMPTZ,
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_api_keys_user ON api_keys(user_id);

-- Notification Preferences
CREATE TABLE IF NOT EXISTS notifications (
    notification_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    type VARCHAR(50) NOT NULL,
    title VARCHAR(255) NOT NULL,
    message TEXT,
    is_read BOOLEAN NOT NULL DEFAULT FALSE,
    metadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_notifications_user ON notifications(user_id);
CREATE INDEX idx_notifications_read ON notifications(is_read);

-- Audit Log (for compliance and security)
CREATE TABLE IF NOT EXISTS audit_log (
    log_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    action VARCHAR(100) NOT NULL,
    resource_type VARCHAR(50),
    resource_id UUID,
    ip_address INET,
    user_agent TEXT,
    metadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_audit_log_user ON audit_log(user_id);
CREATE INDEX idx_audit_log_action ON audit_log(action);
CREATE INDEX idx_audit_log_created ON audit_log(created_at DESC);

-- Smart Contract Registry
CREATE TABLE IF NOT EXISTS contract_registry (
    contract_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    network VARCHAR(30) NOT NULL,
    contract_address VARCHAR(66) NOT NULL,
    contract_type VARCHAR(50) NOT NULL,
    name VARCHAR(100),
    abi JSONB,
    bytecode TEXT,
    deployer_address VARCHAR(66),
    deployment_tx VARCHAR(132),
    block_number BIGINT,
    is_verified BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (network, contract_address)
);

CREATE INDEX idx_contract_registry_network ON contract_registry(network);
CREATE INDEX idx_contract_registry_type ON contract_registry(contract_type);

-- Gas Price Oracle Cache
CREATE TABLE IF NOT EXISTS gas_prices (
    network VARCHAR(30) PRIMARY KEY,
    slow NUMERIC(38,18) NOT NULL,
    normal NUMERIC(38,18) NOT NULL,
    fast NUMERIC(38,18) NOT NULL,
    instant NUMERIC(38,18),
    unit VARCHAR(10) DEFAULT 'gwei',
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Token Allowances (for DeFi integrations)
CREATE TABLE IF NOT EXISTS allowances (
    allowance_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    wallet_id UUID NOT NULL REFERENCES wallets(wallet_id) ON DELETE CASCADE,
    owner_address VARCHAR(66) NOT NULL,
    spender_address VARCHAR(66) NOT NULL,
    asset_id UUID NOT NULL REFERENCES assets(asset_id) ON DELETE CASCADE,
    amount NUMERIC(38,18) NOT NULL DEFAULT 0,
    block_number BIGINT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (owner_address, spender_address, asset_id)
);

CREATE INDEX idx_allowances_wallet ON allowances(wallet_id);
CREATE INDEX idx_allowances_owner ON allowances(owner_address);

-- Multi-chain Bridge Transactions
CREATE TABLE IF NOT EXISTS bridge_transactions (
    bridge_tx_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    source_network VARCHAR(30) NOT NULL,
    target_network VARCHAR(30) NOT NULL,
    source_tx_hash VARCHAR(132),
    target_tx_hash VARCHAR(132),
    asset_id UUID NOT NULL REFERENCES assets(asset_id) ON DELETE CASCADE,
    amount NUMERIC(38,18) NOT NULL,
    source_address VARCHAR(66) NOT NULL,
    target_address VARCHAR(66) NOT NULL,
    status tx_status NOT NULL DEFAULT 'pending',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    confirmed_at TIMESTAMPTZ
);

CREATE INDEX idx_bridge_transactions_user ON bridge_transactions(user_id);
CREATE INDEX idx_bridge_transactions_status ON bridge_transactions(status);

-- Subscriptions for premium features
CREATE TABLE IF NOT EXISTS subscriptions (
    subscription_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    plan_name VARCHAR(50) NOT NULL,
    plan_price NUMERIC(12,2) NOT NULL,
    currency VARCHAR(3) DEFAULT 'USD',
    status VARCHAR(20) NOT NULL DEFAULT 'active',
    started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ,
    cancelled_at TIMESTAMPTZ,
    metadata JSONB DEFAULT '{}'::jsonb,
    CONSTRAINT chk_subscription_status CHECK (status IN ('active', 'cancelled', 'expired'))
);

CREATE INDEX idx_subscriptions_user ON subscriptions(user_id);
