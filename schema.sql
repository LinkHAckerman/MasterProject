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
-- Core Users & Authentication
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

CREATE TABLE IF NOT EXISTS user_sessions (
    session_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash VARCHAR(255) NOT NULL UNIQUE,
    ip_address INET,
    user_agent TEXT,
    is_revoked BOOLEAN NOT NULL DEFAULT FALSE,
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS api_keys (
    key_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    key_name VARCHAR(100) NOT NULL,
    api_key VARCHAR(64) NOT NULL UNIQUE,
    api_secret_hash VARCHAR(255) NOT NULL,
    permissions JSONB NOT NULL DEFAULT '["read"]'::jsonb,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ
);

-- =============================================================
-- Wallet Hierarchy and Multi-Chain Asset Tracking
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

CREATE TABLE IF NOT EXISTS tokens (
    token_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    symbol VARCHAR(20) NOT NULL,
    name VARCHAR(100) NOT NULL,
    contract_address VARCHAR(66),
    network VARCHAR(30) NOT NULL,
    decimals INT NOT NULL DEFAULT 18,
    is_native BOOLEAN NOT NULL DEFAULT FALSE,
    coingecko_id VARCHAR(100),
    icon_url TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_token_network UNIQUE(contract_address, network)
);

CREATE TABLE IF NOT EXISTS wallet_balances (
    balance_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    wallet_id UUID NOT NULL REFERENCES wallets(wallet_id) ON DELETE CASCADE,
    token_id UUID NOT NULL REFERENCES tokens(token_id) ON DELETE CASCADE,
    raw_balance NUMERIC(78, 0) NOT NULL DEFAULT 0,
    formatted_balance NUMERIC(36, 18) NOT NULL DEFAULT 0.0,
    usd_value NUMERIC(24, 6) DEFAULT 0.0,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_wallet_token UNIQUE(wallet_id, token_id)
);

DROP TRIGGER IF EXISTS trg_wallet_balances_updated_at ON wallet_balances;
CREATE TRIGGER trg_wallet_balances_updated_at
BEFORE UPDATE ON wallet_balances
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- =============================================================
-- Transactions & Mempool Processing
-- =============================================================
CREATE TABLE IF NOT EXISTS transactions (
    tx_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    internal_tx_code VARCHAR(32) DEFAULT generate_tx_id(),
    wallet_id UUID NOT NULL REFERENCES wallets(wallet_id) ON DELETE CASCADE,
    tx_hash VARCHAR(66) UNIQUE,
    network VARCHAR(30) NOT NULL,
    block_number BIGINT,
    from_address VARCHAR(66) NOT NULL,
    to_address VARCHAR(66) NOT NULL,
    amount NUMERIC(78, 0) NOT NULL DEFAULT 0,
    gas_used BIGINT,
    gas_price NUMERIC(36, 0),
    status tx_status NOT NULL DEFAULT 'pending',
    type tx_type NOT NULL DEFAULT 'transfer',
    payload JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    confirmed_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS mempool_transactions (
    mempool_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tx_hash VARCHAR(66) UNIQUE NOT NULL,
    network VARCHAR(30) NOT NULL,
    raw_hex TEXT NOT NULL,
    nonce BIGINT NOT NULL,
    gas_limit BIGINT NOT NULL,
    max_priority_fee NUMERIC(36, 0),
    max_fee NUMERIC(36, 0),
    sender VARCHAR(66) NOT NULL,
    received_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =============================================================
-- DeFi Engine: DEX Liquidity Pools & Order Book
-- =============================================================
CREATE TABLE IF NOT EXISTS liquidity_pools (
    pool_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    pool_address VARCHAR(66) NOT NULL UNIQUE,
    network VARCHAR(30) NOT NULL,
    token_a_id UUID NOT NULL REFERENCES tokens(token_id),
    token_b_id UUID NOT NULL REFERENCES tokens(token_id),
    fee_tier_bps INT NOT NULL DEFAULT 30,
    reserve_a NUMERIC(78, 0) NOT NULL DEFAULT 0,
    reserve_b NUMERIC(78, 0) NOT NULL DEFAULT 0,
    total_liquidity NUMERIC(78, 0) NOT NULL DEFAULT 0,
    status pool_status NOT NULL DEFAULT 'active',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS liquidity_positions (
    position_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    pool_id UUID NOT NULL REFERENCES liquidity_pools(pool_id) ON DELETE CASCADE,
    wallet_id UUID NOT NULL REFERENCES wallets(wallet_id) ON DELETE CASCADE,
    liquidity_shares NUMERIC(78, 0) NOT NULL DEFAULT 0,
    lower_tick INT DEFAULT -887272,
    upper_tick INT DEFAULT 887272,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS dex_orders (
    order_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    wallet_id UUID NOT NULL REFERENCES wallets(wallet_id) ON DELETE CASCADE,
    base_token_id UUID NOT NULL REFERENCES tokens(token_id),
    quote_token_id UUID NOT NULL REFERENCES tokens(token_id),
    side order_side NOT NULL,
    type order_type NOT NULL DEFAULT 'limit',
    price NUMERIC(36, 18) NOT NULL,
    amount NUMERIC(36, 18) NOT NULL,
    filled_amount NUMERIC(36, 18) NOT NULL DEFAULT 0.0,
    status order_status NOT NULL DEFAULT 'open',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS dex_trades (
    trade_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    buy_order_id UUID REFERENCES dex_orders(order_id),
    sell_order_id UUID REFERENCES dex_orders(order_id),
    pool_id UUID REFERENCES liquidity_pools(pool_id),
    price NUMERIC(36, 18) NOT NULL,
    amount NUMERIC(36, 18) NOT NULL,
    tx_hash VARCHAR(66),
    executed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =============================================================
-- DeFi Engine: Lending & Borrowing System
-- =============================================================
CREATE TABLE IF NOT EXISTS lending_markets (
    market_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    token_id UUID NOT NULL REFERENCES tokens(token_id) UNIQUE,
    total_supplied NUMERIC(78, 0) NOT NULL DEFAULT 0,
    total_borrowed NUMERIC(78, 0) NOT NULL DEFAULT 0,
    supply_rate_bps INT NOT NULL DEFAULT 0,
    borrow_rate_bps INT NOT NULL DEFAULT 0,
    collateral_factor_bps INT NOT NULL DEFAULT 7500,
    liquidation_threshold_bps INT NOT NULL DEFAULT 8000,
    liquidation_penalty_bps INT NOT NULL DEFAULT 500,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS lending_positions (
    position_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    wallet_id UUID NOT NULL REFERENCES wallets(wallet_id) ON DELETE CASCADE,
    market_id UUID NOT NULL REFERENCES lending_markets(market_id) ON DELETE CASCADE,
    supplied_amount NUMERIC(78, 0) NOT NULL DEFAULT 0,
    borrowed_amount NUMERIC(78, 0) NOT NULL DEFAULT 0,
    health_factor NUMERIC(10, 4) NOT NULL DEFAULT 1.0000,
    status position_status NOT NULL DEFAULT 'active',
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_wallet_lending_market UNIQUE(wallet_id, market_id)
);

CREATE TABLE IF NOT EXISTS liquidation_events (
    liquidation_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    position_id UUID NOT NULL REFERENCES lending_positions(position_id),
    liquidator_wallet_id UUID NOT NULL REFERENCES wallets(wallet_id),
    repaid_amount NUMERIC(78, 0) NOT NULL,
    seized_collateral NUMERIC(78, 0) NOT NULL,
    tx_hash VARCHAR(66) NOT NULL,
    executed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =============================================================
-- NFT Suite & Marketplace Data Models
-- =============================================================
CREATE TABLE IF NOT EXISTS nft_collections (
    collection_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    contract_address VARCHAR(66) NOT NULL UNIQUE,
    network VARCHAR(30) NOT NULL,
    name VARCHAR(100) NOT NULL,
    symbol VARCHAR(20) NOT NULL,
    creator_wallet_id UUID REFERENCES wallets(wallet_id),
    royalty_fee_bps INT NOT NULL DEFAULT 250,
    total_supply BIGINT NOT NULL DEFAULT 0,
    base_uri TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS nft_tokens (
    nft_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    collection_id UUID NOT NULL REFERENCES nft_collections(collection_id) ON DELETE CASCADE,
    token_index BIGINT NOT NULL,
    owner_wallet_id UUID NOT NULL REFERENCES wallets(wallet_id),
    metadata_uri TEXT NOT NULL,
    rarity nft_rarity NOT NULL DEFAULT 'common',
    attributes JSONB DEFAULT '{}'::jsonb,
    minted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_nft_collection_token UNIQUE(collection_id, token_index)
);

CREATE TABLE IF NOT EXISTS nft_listings (
    listing_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    nft_id UUID NOT NULL REFERENCES nft_tokens(nft_id) ON DELETE CASCADE,
    seller_wallet_id UUID NOT NULL REFERENCES wallets(wallet_id),
    price NUMERIC(36, 18) NOT NULL,
    payment_token_id UUID NOT NULL REFERENCES tokens(token_id),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS nft_bids (
    bid_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    listing_id UUID NOT NULL REFERENCES nft_listings(listing_id) ON DELETE CASCADE,
    bidder_wallet_id UUID NOT NULL REFERENCES wallets(wallet_id),
    bid_price NUMERIC(36, 18) NOT NULL,
    is_accepted BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =============================================================
-- Cross-Chain Bridge & Oracle Data Layer
-- =============================================================
CREATE TABLE IF NOT EXISTS bridge_transactions (
    bridge_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    source_network VARCHAR(30) NOT NULL,
    target_network VARCHAR(30) NOT NULL,
    sender_wallet_id UUID NOT NULL REFERENCES wallets(wallet_id),
    recipient_address VARCHAR(66) NOT NULL,
    token_id UUID NOT NULL REFERENCES tokens(token_id),
    amount NUMERIC(78, 0) NOT NULL,
    source_tx_hash VARCHAR(66) UNIQUE NOT NULL,
    target_tx_hash VARCHAR(66) UNIQUE,
    status bridge_status NOT NULL DEFAULT 'initiated',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS price_feeds (
    feed_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    pair_symbol VARCHAR(20) NOT NULL UNIQUE,
    oracle_source VARCHAR(50) NOT NULL DEFAULT 'Chainlink',
    price NUMERIC(36, 18) NOT NULL,
    decimals INT NOT NULL DEFAULT 8,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS oracle_price_ticks (
    tick_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    feed_id UUID NOT NULL REFERENCES price_feeds(feed_id) ON DELETE CASCADE,
    price NUMERIC(36, 18) NOT NULL,
    timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =============================================================
-- Governance & DAO System
-- =============================================================
CREATE TABLE IF NOT EXISTS governance_proposals (
    proposal_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    proposer_wallet_id UUID NOT NULL REFERENCES wallets(wallet_id),
    title VARCHAR(255) NOT NULL,
    description TEXT NOT NULL,
    status proposal_status NOT NULL DEFAULT 'draft',
    for_votes NUMERIC(78, 0) NOT NULL DEFAULT 0,
    against_votes NUMERIC(78, 0) NOT NULL DEFAULT 0,
    abstain_votes NUMERIC(78, 0) NOT NULL DEFAULT 0,
    start_time TIMESTAMPTZ NOT NULL,
    end_time TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS governance_votes (
    vote_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    proposal_id UUID NOT NULL REFERENCES governance_proposals(proposal_id) ON DELETE CASCADE,
    voter_wallet_id UUID NOT NULL REFERENCES wallets(wallet_id),
    vote_power_type vote_power NOT NULL,
    weight NUMERIC(78, 0) NOT NULL,
    voted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_voter_proposal UNIQUE(proposal_id, voter_wallet_id)
);

-- =============================================================
-- System Audit Logs & Analytics
-- =============================================================
CREATE TABLE IF NOT EXISTS audit_logs (
    log_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    action VARCHAR(100) NOT NULL,
    entity_type VARCHAR(50) NOT NULL,
    entity_id UUID,
    ip_address INET,
    details JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =============================================================
-- Optimized Database Indexes
-- =============================================================
CREATE INDEX IF NOT EXISTS idx_wallets_user ON wallets(user_id);
CREATE INDEX IF NOT EXISTS idx_wallets_address ON wallets(address);
CREATE INDEX IF NOT EXISTS idx_wallet_balances_wallet ON wallet_balances(wallet_id);
CREATE INDEX IF NOT EXISTS idx_tx_wallet ON transactions(wallet_id);
CREATE INDEX IF NOT EXISTS idx_tx_hash ON transactions(tx_hash);
CREATE INDEX IF NOT EXISTS idx_tx_status_net ON transactions(status, network);
CREATE INDEX IF NOT EXISTS idx_dex_orders_pair ON dex_orders(base_token_id, quote_token_id, status);
CREATE INDEX IF NOT EXISTS idx_nft_owner ON nft_tokens(owner_wallet_id);
CREATE INDEX IF NOT EXISTS idx_bridge_sender ON bridge_transactions(sender_wallet_id);
CREATE INDEX IF NOT EXISTS idx_oracle_ticks ON oracle_price_ticks(feed_id, timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_audit_user ON audit_logs(user_id, created_at DESC);

-- =============================================================
-- Analytical Views
-- =============================================================
CREATE OR REPLACE VIEW v_user_portfolio_summary AS
SELECT 
    u.id AS user_id,
    u.email,
    COUNT(DISTINCT w.wallet_id) AS total_wallets,
    COALESCE(SUM(wb.usd_value), 0.0) AS total_portfolio_usd_value
FROM users u
LEFT JOIN wallets w ON u.id = w.user_id AND w.is_active = TRUE
LEFT JOIN wallet_balances wb ON w.wallet_id = wb.wallet_id
GROUP BY u.id, u.email;

CREATE OR REPLACE VIEW v_active_dex_markets AS
SELECT 
    p.pool_id,
    p.network,
    ta.symbol AS token_a,
    tb.symbol AS token_b,
    p.fee_tier_bps,
    p.reserve_a,
    p.reserve_b,
    p.total_liquidity
FROM liquidity_pools p
JOIN tokens ta ON p.token_a_id = ta.token_id
JOIN tokens tb ON p.token_b_id = tb.token_id
WHERE p.status = 'active';
