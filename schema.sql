-- PostgreSQL schema for Magnum Opus: Enhanced with support for NFTs, DeFi contracts, and multi-chain asset tracking
-- Full-stack Web3 & DeFi Nexus Platform Data Layer

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- =============================================================
-- Enumerations & Domain Types
-- =============================================================

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'tx_status') THEN
        CREATE TYPE tx_status AS ENUM ('pending', 'confirmed', 'failed', 'reverted');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'tx_type') THEN
        CREATE TYPE tx_type AS ENUM ('transfer', 'swap', 'stake', 'unstake', 'deposit', 'withdraw', 'mint', 'burn', 'liquidation', 'bridge');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'order_side') THEN
        CREATE TYPE order_side AS ENUM ('buy', 'sell');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'order_type') THEN
        CREATE TYPE order_type AS ENUM ('limit', 'market', 'stop_loss', 'take_profit');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'order_status') THEN
        CREATE TYPE order_status AS ENUM ('open', 'filled', 'partially_filled', 'cancelled', 'expired');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'position_status') THEN
        CREATE TYPE position_status AS ENUM ('active', 'closed', 'liquidated');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'lending_action') THEN
        CREATE TYPE lending_action AS ENUM ('supply', 'borrow', 'repay', 'withdraw', 'liquidate');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'proposal_status') THEN
        CREATE TYPE proposal_status AS ENUM ('draft', 'active', 'succeeded', 'defeated', 'executed', 'cancelled');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'bridge_status') THEN
        CREATE TYPE bridge_status AS ENUM ('initiated', 'pending_lock', 'verified', 'completed', 'failed', 'refunded');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'nft_rarity') THEN
        CREATE TYPE nft_rarity AS ENUM ('common', 'uncommon', 'rare', 'epic', 'legendary', 'mythic');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'pool_status') THEN
        CREATE TYPE pool_status AS ENUM ('active', 'paused', 'retired');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'vote_power') THEN
        CREATE TYPE vote_power AS ENUM ('yes', 'no', 'abstain');
    END IF;
END $$;

-- Helper trigger function to auto-update the updated_at timestamp
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Helper function to generate a unique transaction ID
CREATE OR REPLACE FUNCTION generate_tx_id()
RETURNS VARCHAR AS $$
BEGIN
    RETURN 'TX-' || UPPER(SUBSTRING(MD5(CAST(NOW() AS TEXT) || CAST(RANDOM() AS TEXT)) FROM 1 FOR 12));
END;
$$ LANGUAGE plpgsql;

-- =============================================================
-- Core Users Table
-- =============================================================
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email VARCHAR(255) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    full_name VARCHAR(255),
    status VARCHAR(20) NOT NULL DEFAULT 'active',
    is_verified BOOLEAN NOT NULL DEFAULT FALSE,
    verification_token VARCHAR(255),
    verification_expires TIMESTAMPTZ,
    two_factor_enabled BOOLEAN NOT NULL DEFAULT FALSE,
    two_factor_secret VARCHAR(255),
    backup_codes TEXT[],
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'::jsonb,
    CONSTRAINT chk_user_status CHECK (status IN ('active', 'suspended', 'deleted', 'verified'))
);

DROP TRIGGER IF EXISTS trg_users_updated_at ON users;
CREATE TRIGGER trg_users_updated_at
BEFORE UPDATE ON users
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- =============================================================
-- Wallet Hierarchy and Network Support
-- =============================================================
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

DROP TRIGGER IF EXISTS trg_wallets_updated_at ON wallets;
CREATE TRIGGER trg_wallets_updated_at
BEFORE UPDATE ON wallets
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- =============================================================
-- Token and NFT Classification
-- =============================================================
CREATE TABLE IF NOT EXISTS assets (
    asset_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    symbol VARCHAR(20) NOT NULL,
    name VARCHAR(100) NOT NULL,
    decimals SMALLINT NOT NULL CHECK (decimals BETWEEN 0 AND 30),
    contract_address VARCHAR(66),
    network VARCHAR(30) NOT NULL,
    is_nft BOOLEAN NOT NULL DEFAULT FALSE,
    total_supply NUMERIC(78, 0),
    max_supply NUMERIC(78, 0),
    description TEXT,
    image_url VARCHAR(500),
    external_url VARCHAR(500),
    attributes JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'::jsonb,
    CONSTRAINT chk_decimals CHECK (decimals >= 0 AND decimals <= 30)
);

DROP TRIGGER IF EXISTS trg_assets_updated_at ON assets;
CREATE TRIGGER trg_assets_updated_at
BEFORE UPDATE ON assets
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- =============================================================
-- NFT Collections
-- =============================================================
CREATE TABLE IF NOT EXISTS nft_collections (
    collection_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(200) NOT NULL,
    symbol VARCHAR(20),
    description TEXT,
    contract_address VARCHAR(66) NOT NULL,
    network VARCHAR(30) NOT NULL,
    standard VARCHAR(20) NOT NULL CHECK (standard IN ('ERC-721', 'ERC-1155', 'SPL', 'Native')),
    banner_image_url VARCHAR(500),
    logo_image_url VARCHAR(500),
    external_url VARCHAR(500),
    twitter_handle VARCHAR(100),
    discord_url VARCHAR(500),
    floor_price NUMERIC(78, 18),
    total_supply INTEGER,
    owner_count INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'::jsonb
);

DROP TRIGGER IF EXISTS trg_nft_collections_updated_at ON nft_collections;
CREATE TRIGGER trg_nft_collections_updated_at
BEFORE UPDATE ON nft_collections
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- =============================================================
-- Individual NFT Items
-- =============================================================
CREATE TABLE IF NOT EXISTS nft_items (
    nft_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    collection_id UUID NOT NULL REFERENCES nft_collections(collection_id) ON DELETE CASCADE,
    token_id VARCHAR(100) NOT NULL,
    owner_wallet_id UUID NOT NULL REFERENCES wallets(wallet_id) ON DELETE CASCADE,
    name VARCHAR(200),
    description TEXT,
    image_url VARCHAR(500),
    animation_url VARCHAR(500),
    external_url VARCHAR(500),
    rarity nft_rarity DEFAULT 'common',
    traits JSONB DEFAULT '[]'::jsonb,
    mint_price NUMERIC(78, 18),
    current_price NUMERIC(78, 18),
    listed BOOLEAN NOT NULL DEFAULT FALSE,
    listed_at TIMESTAMPTZ,
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'::jsonb,
    UNIQUE(collection_id, token_id)
);

DROP TRIGGER IF EXISTS trg_nft_items_updated_at ON nft_items;
CREATE TRIGGER trg_nft_items_updated_at
BEFORE UPDATE ON nft_items
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- =============================================================
-- Transaction History
-- =============================================================
CREATE TABLE IF NOT EXISTS transactions (
    tx_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tx_hash VARCHAR(128) UNIQUE,
    wallet_id UUID NOT NULL REFERENCES wallets(wallet_id) ON DELETE CASCADE,
    network VARCHAR(30) NOT NULL,
    tx_type tx_type NOT NULL,
    status tx_status NOT NULL DEFAULT 'pending',
    from_address VARCHAR(66),
    to_address VARCHAR(66),
    asset_symbol VARCHAR(20),
    asset_contract VARCHAR(66),
    amount NUMERIC(78, 18) NOT NULL DEFAULT 0,
    fee NUMERIC(78, 18) DEFAULT 0,
    gas_price NUMERIC(78, 0),
    gas_limit NUMERIC(78, 0),
    gas_used NUMERIC(78, 0),
    block_number BIGINT,
    block_hash VARCHAR(128),
    parent_tx_hash VARCHAR(128),
    contract_address VARCHAR(66),
    input_data TEXT,
    output_data TEXT,
    error_message TEXT,
    confirmations INTEGER DEFAULT 0,
    required_confirmations INTEGER DEFAULT 12,
    timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    indexed_at TIMESTAMPTZ,
    metadata JSONB DEFAULT '{}'::jsonb,
    CONSTRAINT chk_amount CHECK (amount >= 0)
);

DROP TRIGGER IF EXISTS trg_transactions_updated_at ON transactions;
CREATE TRIGGER trg_transactions_updated_at
BEFORE UPDATE ON transactions
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- Index for common queries
CREATE INDEX IF NOT EXISTS idx_transactions_wallet ON transactions(wallet_id);
CREATE INDEX IF NOT EXISTS idx_transactions_status ON transactions(status);
CREATE INDEX IF NOT EXISTS idx_transactions_tx_hash ON transactions(tx_hash);
CREATE INDEX IF NOT EXISTS idx_transactions_timestamp ON transactions(timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_transactions_network ON transactions(network);

-- =============================================================
-- DEX / Order Book
-- =============================================================
CREATE TABLE IF NOT EXISTS trading_pairs (
    pair_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    base_asset_id UUID NOT NULL REFERENCES assets(asset_id),
    quote_asset_id UUID NOT NULL REFERENCES assets(asset_id),
    base_symbol VARCHAR(20) NOT NULL,
    quote_symbol VARCHAR(20) NOT NULL,
    network VARCHAR(30) NOT NULL,
    pair_address VARCHAR(66),
    factory_address VARCHAR(66),
    fee_bps INTEGER NOT NULL DEFAULT 30 CHECK (fee_bps BETWEEN 0 AND 10000),
    tick_spacing INTEGER,
    pool_type VARCHAR(20) NOT NULL DEFAULT 'AMM' CHECK (pool_type IN ('AMM', 'OrderBook', 'ConcentratedLiquidity')),
    status pool_status DEFAULT 'active',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'::jsonb,
    UNIQUE(base_asset_id, quote_asset_id, network)
);

DROP TRIGGER IF EXISTS trg_trading_pairs_updated_at ON trading_pairs;
CREATE TRIGGER trg_trading_pairs_updated_at
BEFORE UPDATE ON trading_pairs
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

CREATE TABLE IF NOT EXISTS orders (
    order_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    wallet_id UUID NOT NULL REFERENCES wallets(wallet_id) ON DELETE CASCADE,
    pair_id UUID NOT NULL REFERENCES trading_pairs(pair_id),
    order_side order_side NOT NULL,
    order_type order_type NOT NULL,
    status order_status NOT NULL DEFAULT 'open',
    price NUMERIC(78, 18) NOT NULL,
    price_tick NUMERIC(78, 0),
    amount NUMERIC(78, 18) NOT NULL,
    filled_amount NUMERIC(78, 18) NOT NULL DEFAULT 0,
    remaining_amount NUMERIC(78, 18) NOT NULL DEFAULT 0,
    stop_price NUMERIC(78, 18),
    take_profit_price NUMERIC(78, 18),
    leverage NUMERIC(10, 4) DEFAULT 1,
    client_order_id VARCHAR(64),
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'::jsonb,
    CONSTRAINT chk_order_amount CHECK (amount > 0),
    CONSTRAINT chk_order_price CHECK (price >= 0)
);

DROP TRIGGER IF EXISTS trg_orders_updated_at ON orders;
CREATE TRIGGER trg_orders_updated_at
BEFORE UPDATE ON orders
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

CREATE INDEX IF NOT EXISTS idx_orders_user ON orders(user_id);
CREATE INDEX IF NOT EXISTS idx_orders_pair ON orders(pair_id);
CREATE INDEX IF NOT EXISTS idx_orders_status ON orders(status);
CREATE INDEX IF NOT EXISTS idx_orders_created ON orders(created_at DESC);

-- =============================================================
-- Liquidity Pools
-- =============================================================
CREATE TABLE IF NOT EXISTS liquidity_pools (
    pool_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    pair_id UUID NOT NULL REFERENCES trading_pairs(pair_id),
    pool_address VARCHAR(66) NOT NULL,
    network VARCHAR(30) NOT NULL,
    token0_symbol VARCHAR(20) NOT NULL,
    token1_symbol VARCHAR(20) NOT NULL,
    token0_reserve NUMERIC(78, 18) NOT NULL DEFAULT 0,
    token1_reserve NUMERIC(78, 18) NOT NULL DEFAULT 0,
    total_liquidity NUMERIC(78, 18) NOT NULL DEFAULT 0,
    k_constant NUMERIC(78, 0),
    apr NUMERIC(10, 4),
    volume_24h NUMERIC(78, 18) DEFAULT 0,
    tvl NUMERIC(78, 18) DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'::jsonb
);

DROP TRIGGER IF EXISTS trg_liquidity_pools_updated_at ON liquidity_pools;
CREATE TRIGGER trg_liquidity_pools_updated_at
BEFORE UPDATE ON liquidity_pools
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- =============================================================
-- User Positions & Lending
-- =============================================================
CREATE TABLE IF NOT EXISTS user_positions (
    position_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    wallet_id UUID NOT NULL REFERENCES wallets(wallet_id) ON DELETE CASCADE,
    pool_id UUID NOT NULL REFERENCES liquidity_pools(pool_id),
    lp_tokens NUMERIC(78, 18) NOT NULL DEFAULT 0,
    supplied_token0 NUMERIC(78, 18) NOT NULL DEFAULT 0,
    supplied_token1 NUMERIC(78, 18) NOT NULL DEFAULT 0,
    borrowed_token0 NUMERIC(78, 18) NOT NULL DEFAULT 0,
    borrowed_token1 NUMERIC(78, 18) NOT NULL DEFAULT 0,
    health_factor NUMERIC(10, 4),
    liquidation_threshold NUMERIC(10, 4),
    status position_status NOT NULL DEFAULT 'active',
    opened_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    closed_at TIMESTAMPTZ,
    metadata JSONB DEFAULT '{}'::jsonb
);

DROP TRIGGER IF EXISTS trg_user_positions_updated_at ON user_positions;
CREATE TRIGGER trg_user_positions_updated_at
BEFORE UPDATE ON user_positions
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

CREATE TABLE IF NOT EXISTS lending_events (
    event_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    position_id UUID NOT NULL REFERENCES user_positions(position_id),
    user_id UUID NOT NULL REFERENCES users(id),
    action lending_action NOT NULL,
    token_symbol VARCHAR(20) NOT NULL,
    amount NUMERIC(78, 18) NOT NULL,
    tx_hash VARCHAR(128),
    block_number BIGINT,
    timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS idx_lending_events_position ON lending_events(position_id);
CREATE INDEX IF NOT EXISTS idx_lending_events_user ON lending_events(user_id);
CREATE INDEX IF NOT EXISTS idx_lending_events_timestamp ON lending_events(timestamp DESC);

-- =============================================================
-- DAO Governance
-- =============================================================
CREATE TABLE IF NOT EXISTS dao_proposals (
    proposal_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    proposal_number SERIAL,
    title VARCHAR(500) NOT NULL,
    description TEXT NOT NULL,
    proposer_id UUID NOT NULL REFERENCES users(id),
    proposer_wallet VARCHAR(66) NOT NULL,
    status proposal_status NOT NULL DEFAULT 'draft',
    start_block BIGINT,
    end_block BIGINT,
    start_time TIMESTAMPTZ,
    end_time TIMESTAMPTZ,
    vote_threshold NUMERIC(78, 18),
    quorum NUMERIC(78, 18),
    total_votes_yes NUMERIC(78, 18) DEFAULT 0,
    total_votes_no NUMERIC(78, 18) DEFAULT 0,
    total_votes_abstain NUMERIC(78, 18) DEFAULT 0,
    total_voting_power NUMERIC(78, 18) DEFAULT 0,
    execution_data TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'::jsonb
);

DROP TRIGGER IF EXISTS trg_dao_proposals_updated_at ON dao_proposals;
CREATE TRIGGER trg_dao_proposals_updated_at
BEFORE UPDATE ON dao_proposals
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

CREATE TABLE IF NOT EXISTS dao_votes (
    vote_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    proposal_id UUID NOT NULL REFERENCES dao_proposals(proposal_id) ON DELETE CASCADE,
    voter_id UUID NOT NULL REFERENCES users(id),
    voter_wallet VARCHAR(66) NOT NULL,
    vote vote_power NOT NULL,
    voting_power NUMERIC(78, 18) NOT NULL,
    tx_hash VARCHAR(128),
    block_number BIGINT,
    timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'::jsonb,
    UNIQUE(proposal_id, voter_wallet)
);

CREATE INDEX IF NOT EXISTS idx_dao_votes_proposal ON dao_votes(proposal_id);
CREATE INDEX IF NOT EXISTS idx_dao_votes_voter ON dao_votes(voter_id);

-- =============================================================
-- Bridge Transactions
-- =============================================================
CREATE TABLE IF NOT EXISTS bridge_transactions (
    bridge_tx_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id),
    wallet_id UUID NOT NULL REFERENCES wallets(wallet_id),
    source_network VARCHAR(30) NOT NULL,
    target_network VARCHAR(30) NOT NULL,
    source_chain_tx_hash VARCHAR(128),
    target_chain_tx_hash VARCHAR(128),
    source_address VARCHAR(66) NOT NULL,
    target_address VARCHAR(66) NOT NULL,
    asset_symbol VARCHAR(20) NOT NULL,
    amount NUMERIC(78, 18) NOT NULL,
    fee NUMERIC(78, 18) DEFAULT 0,
    status bridge_status NOT NULL DEFAULT 'initiated',
    source_block_number BIGINT,
    target_block_number BIGINT,
    required_confirmations INTEGER DEFAULT 12,
    source_confirmations INTEGER DEFAULT 0,
    target_confirmations INTEGER DEFAULT 0,
    initiated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    locked_at TIMESTAMPTZ,
    verified_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    failed_at TIMESTAMPTZ,
    refunded_at TIMESTAMPTZ,
    error_message TEXT,
    metadata JSONB DEFAULT '{}'::jsonb,
    CONSTRAINT chk_bridge_amount CHECK (amount > 0)
);

CREATE INDEX IF NOT EXISTS idx_bridge_user ON bridge_transactions(user_id);
CREATE INDEX IF NOT EXISTS idx_bridge_status ON bridge_transactions(status);
CREATE INDEX IF NOT EXISTS idx_bridge_initiated ON bridge_transactions(initiated_at DESC);

-- =============================================================
-- Price Oracle Data
-- =============================================================
CREATE TABLE IF NOT EXISTS price_observations (
    obs_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    asset_symbol VARCHAR(20) NOT NULL,
    network VARCHAR(30) NOT NULL,
    price_usd NUMERIC(78, 18) NOT NULL,
    price_eth NUMERIC(78, 18),
    price_btc NUMERIC(78, 18),
    source VARCHAR(50) NOT NULL,
    block_number BIGINT,
    timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS idx_price_obs_symbol ON price_observations(asset_symbol, timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_price_obs_timestamp ON price_observations(timestamp DESC);

-- =============================================================
-- API Keys & Sessions
-- =============================================================
CREATE TABLE IF NOT EXISTS api_keys (
    key_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    key_hash VARCHAR(255) NOT NULL UNIQUE,
    key_prefix VARCHAR(16) NOT NULL,
    name VARCHAR(100),
    scopes TEXT[] DEFAULT '{}'::text[],
    rate_limit INTEGER DEFAULT 1000,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    last_used_at TIMESTAMPTZ,
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'::jsonb
);

DROP TRIGGER IF EXISTS trg_api_keys_updated_at ON api_keys;
CREATE TRIGGER trg_api_keys_updated_at
BEFORE UPDATE ON api_keys
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

CREATE TABLE IF NOT EXISTS sessions (
    session_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    refresh_token_hash VARCHAR(255) NOT NULL UNIQUE,
    ip_address INET,
    user_agent TEXT,
    device_fingerprint VARCHAR(128),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_active_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_sessions_user ON sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_sessions_active ON sessions(is_active, expires_at);

-- =============================================================
-- Audit Log
-- =============================================================
CREATE TABLE IF NOT EXISTS audit_logs (
    log_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    action VARCHAR(100) NOT NULL,
    resource VARCHAR(100),
    resource_id UUID,
    ip_address INET,
    user_agent TEXT,
    details JSONB DEFAULT '{}'::jsonb,
    severity VARCHAR(20) DEFAULT 'info' CHECK (severity IN ('info', 'warning', 'error', 'critical')),
    timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_audit_logs_user ON audit_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_action ON audit_logs(action);
CREATE INDEX IF NOT EXISTS idx_audit_logs_timestamp ON audit_logs(timestamp DESC);

-- =============================================================
-- Notifications
-- =============================================================
CREATE TABLE IF NOT EXISTS notifications (
    notification_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    type VARCHAR(50) NOT NULL,
    title VARCHAR(255) NOT NULL,
    message TEXT NOT NULL,
    priority VARCHAR(20) DEFAULT 'normal' CHECK (priority IN ('low', 'normal', 'high', 'urgent')),
    is_read BOOLEAN NOT NULL DEFAULT FALSE,
    read_at TIMESTAMPTZ,
    action_url VARCHAR(500),
    metadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_notifications_user ON notifications(user_id, is_read, created_at DESC);

-- =============================================================
-- Price Oracle Configurations
-- =============================================================
CREATE TABLE IF NOT EXISTS oracle_configs (
    config_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    asset_symbol VARCHAR(20) NOT NULL,
    network VARCHAR(30) NOT NULL,
    oracle_type VARCHAR(50) NOT NULL CHECK (oracle_type IN ('chainlink', 'uniswap_v2', 'uniswap_v3', 'pyth', 'custom')),
    oracle_address VARCHAR(66),
    heartbeat_interval INTEGER NOT NULL DEFAULT 3600,
    deviation_threshold NUMERIC(10, 4) DEFAULT 0.01,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'::jsonb,
    UNIQUE(asset_symbol, network, oracle_type)
);

DROP TRIGGER IF EXISTS trg_oracle_configs_updated_at ON oracle_configs;
CREATE TRIGGER trg_oracle_configs_updated_at
BEFORE UPDATE ON oracle_configs
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- =============================================================
-- Subscriptions & Plans
-- =============================================================
CREATE TABLE IF NOT EXISTS subscription_plans (
    plan_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(100) NOT NULL,
    description TEXT,
    price_usd NUMERIC(10, 2) NOT NULL DEFAULT 0,
    billing_cycle VARCHAR(20) NOT NULL DEFAULT 'monthly' CHECK (billing_cycle IN ('monthly', 'yearly', 'one_time')),
    features JSONB DEFAULT '[]'::jsonb,
    api_rate_limit INTEGER DEFAULT 1000,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

DROP TRIGGER IF EXISTS trg_subscription_plans_updated_at ON subscription_plans;
CREATE TRIGGER trg_subscription_plans_updated_at
BEFORE UPDATE ON subscription_plans
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

CREATE TABLE IF NOT EXISTS user_subscriptions (
    sub_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    plan_id UUID NOT NULL REFERENCES subscription_plans(plan_id),
    status VARCHAR(20) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'cancelled', 'expired', 'trial')),
    trial_end TIMESTAMPTZ,
    current_period_start TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    current_period_end TIMESTAMPTZ NOT NULL,
    cancelled_at TIMESTAMPTZ,
    payment_method JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

DROP TRIGGER IF EXISTS trg_user_subscriptions_updated_at ON user_subscriptions;
CREATE TRIGGER trg_user_subscriptions_updated_at
BEFORE UPDATE ON user_subscriptions
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- =============================================================
-- Default Admin User & Plan Insertion
-- =============================================================
INSERT INTO subscription_plans (plan_id, name, description, price_usd, billing_cycle, features, api_rate_limit)
VALUES
    (uuid_generate_v4(), 'Free', 'Basic access with limited features', 0.00, 'monthly',
     '["view_portfolio", "basic_charts", "read_notifications"]'::jsonb, 100),
    (uuid_generate_v4(), 'Pro', 'Full platform access with advanced analytics', 29.99, 'monthly',
     '["view_portfolio", "basic_charts", "read_notifications", "advanced_charts", "trade", "api_access", "priority_support"]'::jsonb, 10000),
    (uuid_generate_v4(), 'Enterprise', 'Unlimited access with dedicated support and custom integrations', 99.99, 'monthly',
     '["view_portfolio", "basic_charts", "read_notifications", "advanced_charts", "trade", "api_access", "priority_support", "custom_integrations", "dedicated_support", "sso", "audit_logs"]'::jsonb, 100000)
ON CONFLICT DO NOTHING;
