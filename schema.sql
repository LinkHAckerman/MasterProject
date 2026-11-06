-- PostgreSQL schema for Magnum Opus: Enhanced with support for NFTs, DeFi contracts, and multi-chain asset tracking
-- Updated for full-stack Web3 ecosystem integration

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Enum for transaction status
CREATE TYPE tx_status AS ENUM ('pending', 'confirmed', 'failed', 'reverted');

-- Enum for transaction types
CREATE TYPE tx_type AS ENUM ('transfer', 'swap', 'stake', 'unstake', 'deposit', 'withdraw', 'mint', 'burn', 'liquidation', 'bridge');

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

-- Enum for DAO proposal status
CREATE TYPE proposal_status AS ENUM ('draft', 'active', 'succeeded', 'defeated', 'executed', 'cancelled');

-- Enum for bridge transaction status
CREATE TYPE bridge_status AS ENUM ('initiated', 'pending_lock', 'verified', 'completed', 'failed', 'refunded');

-- Helper trigger function to auto-update the updated_at timestamp
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
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
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'::jsonb,
    CONSTRAINT chk_user_status CHECK (status IN ('active', 'suspended', 'deleted', 'verified'))
);

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

-- =============================================================
-- User Asset Balances
-- =============================================================
CREATE TABLE IF NOT EXISTS balances (
    balance_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    wallet_id UUID NOT NULL REFERENCES wallets(wallet_id) ON DELETE CASCADE,
    asset_id UUID NOT NULL REFERENCES assets(asset_id) ON DELETE CASCADE,
    amount NUMERIC(38,18) NOT NULL DEFAULT 0 CHECK (amount >= 0),
    locked_amount NUMERIC(38,18) NOT NULL DEFAULT 0 CHECK (locked_amount >= 0),
    staked_amount NUMERIC(38,18) NOT NULL DEFAULT 0 CHECK (staked_amount >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (wallet_id, asset_id)
);

CREATE TRIGGER trg_balances_updated_at
BEFORE UPDATE ON balances
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- =============================================================
-- NFT Collection and Token Metadata
-- =============================================================
CREATE TABLE IF NOT EXISTS nft_collections (
    collection_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    asset_id UUID NOT NULL UNIQUE REFERENCES assets(asset_id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    image_url VARCHAR(512),
    metadata_uri VARCHAR(512),
    royalty_fee_bps INT DEFAULT 250 CHECK (royalty_fee_bps BETWEEN 0 AND 10000),
    attributes JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_nft_collections_updated_at
BEFORE UPDATE ON nft_collections
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

CREATE TABLE IF NOT EXISTS nft_tokens (
    token_item_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    collection_id UUID NOT NULL REFERENCES nft_collections(collection_id) ON DELETE CASCADE,
    token_id VARCHAR(78) NOT NULL,
    owner_wallet_id UUID NOT NULL REFERENCES wallets(wallet_id),
    metadata_uri VARCHAR(512),
    attributes JSONB DEFAULT '{}'::jsonb,
    is_listed BOOLEAN DEFAULT FALSE,
    listing_price_usd NUMERIC(24,8) DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (collection_id, token_id)
);

CREATE TRIGGER trg_nft_tokens_updated_at
BEFORE UPDATE ON nft_tokens
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- =============================================================
-- Blockchain Transactions
-- =============================================================
CREATE TABLE IF NOT EXISTS transactions (
    tx_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tx_hash VARCHAR(66) UNIQUE,
    from_wallet_id UUID REFERENCES wallets(wallet_id),
    to_address VARCHAR(66) NOT NULL,
    asset_id UUID REFERENCES assets(asset_id),
    amount NUMERIC(38,18) NOT NULL DEFAULT 0,
    gas_fee NUMERIC(38,18) DEFAULT 0,
    gas_price_gwei NUMERIC(18,8) DEFAULT 0,
    block_number BIGINT,
    network VARCHAR(30) NOT NULL,
    type tx_type NOT NULL,
    status tx_status NOT NULL DEFAULT 'pending',
    raw_payload JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_transactions_updated_at
BEFORE UPDATE ON transactions
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- =============================================================
-- DEX Orderbook Engine & Trade History
-- =============================================================
CREATE TABLE IF NOT EXISTS orderbook_pairs (
    pair_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    base_asset_id UUID NOT NULL REFERENCES assets(asset_id),
    quote_asset_id UUID NOT NULL REFERENCES assets(asset_id),
    pair_symbol VARCHAR(30) NOT NULL UNIQUE,
    min_order_size NUMERIC(38,18) DEFAULT 0.0001,
    tick_size NUMERIC(24,8) DEFAULT 0.00000001,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (base_asset_id, quote_asset_id)
);

CREATE TABLE IF NOT EXISTS orders (
    order_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    pair_id UUID NOT NULL REFERENCES orderbook_pairs(pair_id),
    side order_side NOT NULL,
    type order_type NOT NULL,
    price NUMERIC(24,8) NOT NULL CHECK (price >= 0),
    quantity NUMERIC(38,18) NOT NULL CHECK (quantity > 0),
    filled_quantity NUMERIC(38,18) DEFAULT 0 CHECK (filled_quantity >= 0),
    status order_status NOT NULL DEFAULT 'open',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_orders_updated_at
BEFORE UPDATE ON orders
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

CREATE TABLE IF NOT EXISTS trades (
    trade_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    pair_id UUID NOT NULL REFERENCES orderbook_pairs(pair_id),
    buy_order_id UUID NOT NULL REFERENCES orders(order_id),
    sell_order_id UUID NOT NULL REFERENCES orders(order_id),
    price NUMERIC(24,8) NOT NULL,
    quantity NUMERIC(38,18) NOT NULL,
    maker_fee NUMERIC(24,8) DEFAULT 0,
    taker_fee NUMERIC(24,8) DEFAULT 0,
    tx_hash VARCHAR(66),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =============================================================
-- Perpetual Leverage & Margin Positions
-- =============================================================
CREATE TABLE IF NOT EXISTS perpetual_positions (
    position_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    pair_id UUID NOT NULL REFERENCES orderbook_pairs(pair_id),
    side order_side NOT NULL,
    leverage INT NOT NULL DEFAULT 1 CHECK (leverage BETWEEN 1 AND 125),
    entry_price NUMERIC(24,8) NOT NULL,
    liquidation_price NUMERIC(24,8) NOT NULL,
    collateral_amount NUMERIC(38,18) NOT NULL,
    position_size NUMERIC(38,18) NOT NULL,
    unrealized_pnl NUMERIC(24,8) DEFAULT 0,
    status position_status NOT NULL DEFAULT 'active',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_perpetual_positions_updated_at
BEFORE UPDATE ON perpetual_positions
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- =============================================================
-- Staking & Yield Farming Pools
-- =============================================================
CREATE TABLE IF NOT EXISTS staking_pools (
    pool_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    asset_id UUID NOT NULL REFERENCES assets(asset_id),
    reward_asset_id UUID NOT NULL REFERENCES assets(asset_id),
    pool_name VARCHAR(100) NOT NULL,
    apy_percentage NUMERIC(8,4) NOT NULL DEFAULT 0,
    min_stake NUMERIC(38,18) DEFAULT 0,
    lockup_period_days INT DEFAULT 0,
    total_staked NUMERIC(38,18) DEFAULT 0,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS user_stakes (
    stake_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    pool_id UUID NOT NULL REFERENCES staking_pools(pool_id),
    amount NUMERIC(38,18) NOT NULL CHECK (amount > 0),
    staked_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    unlocks_at TIMESTAMPTZ,
    accumulated_rewards NUMERIC(38,18) DEFAULT 0,
    is_active BOOLEAN DEFAULT TRUE
);

-- =============================================================
-- Money Market & Lending Protocol
-- =============================================================
CREATE TABLE IF NOT EXISTS lending_markets (
    market_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    asset_id UUID NOT NULL UNIQUE REFERENCES assets(asset_id),
    total_supplied NUMERIC(38,18) DEFAULT 0,
    total_borrowed NUMERIC(38,18) DEFAULT 0,
    supply_rate_apy NUMERIC(8,4) DEFAULT 0,
    borrow_rate_apy NUMERIC(8,4) DEFAULT 0,
    collateral_factor NUMERIC(5,4) DEFAULT 0.75 CHECK (collateral_factor BETWEEN 0 AND 1),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS lending_positions (
    position_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    market_id UUID NOT NULL REFERENCES lending_markets(market_id),
    supplied_amount NUMERIC(38,18) DEFAULT 0 CHECK (supplied_amount >= 0),
    borrowed_amount NUMERIC(38,18) DEFAULT 0 CHECK (borrowed_amount >= 0),
    health_factor NUMERIC(10,4) DEFAULT 1.0,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =============================================================
-- Cross-Chain Bridge Infrastructure
-- =============================================================
CREATE TABLE IF NOT EXISTS cross_chain_bridges (
    bridge_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    source_network VARCHAR(30) NOT NULL,
    destination_network VARCHAR(30) NOT NULL,
    source_tx_hash VARCHAR(66),
    destination_tx_hash VARCHAR(66),
    asset_id UUID NOT NULL REFERENCES assets(asset_id),
    amount NUMERIC(38,18) NOT NULL,
    relayer_fee NUMERIC(38,18) DEFAULT 0,
    status bridge_status NOT NULL DEFAULT 'initiated',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_cross_chain_bridges_updated_at
BEFORE UPDATE ON cross_chain_bridges
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- =============================================================
-- DAO Governance Protocols
-- =============================================================
CREATE TABLE IF NOT EXISTS governance_proposals (
    proposal_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    proposer_wallet_id UUID NOT NULL REFERENCES wallets(wallet_id),
    title VARCHAR(255) NOT NULL,
    description TEXT NOT NULL,
    target_contract VARCHAR(66),
    execution_payload TEXT,
    votes_for NUMERIC(38,18) DEFAULT 0,
    votes_against NUMERIC(38,18) DEFAULT 0,
    quorum_required NUMERIC(38,18) NOT NULL,
    status proposal_status NOT NULL DEFAULT 'draft',
    start_time TIMESTAMPTZ NOT NULL,
    end_time TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS governance_votes (
    vote_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    proposal_id UUID NOT NULL REFERENCES governance_proposals(proposal_id) ON DELETE CASCADE,
    voter_wallet_id UUID NOT NULL REFERENCES wallets(wallet_id),
    support BOOLEAN NOT NULL,
    voting_power NUMERIC(38,18) NOT NULL,
    voted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (proposal_id, voter_wallet_id)
);

-- =============================================================
-- Oracle Price Logs & System Audit Logging
-- =============================================================
CREATE TABLE IF NOT EXISTS oracle_price_logs (
    log_id BIGSERIAL PRIMARY KEY,
    asset_id UUID NOT NULL REFERENCES assets(asset_id),
    oracle_source VARCHAR(100) NOT NULL,
    price_usd NUMERIC(24,8) NOT NULL,
    timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS audit_logs (
    log_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    action VARCHAR(100) NOT NULL,
    ip_address VARCHAR(45),
    user_agent TEXT,
    details JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =============================================================
-- Performance Indexes
-- =============================================================
CREATE INDEX IF NOT EXISTS idx_wallets_user ON wallets(user_id);
CREATE INDEX IF NOT EXISTS idx_wallets_address ON wallets(address);
CREATE INDEX IF NOT EXISTS idx_assets_symbol_net ON assets(symbol, network);
CREATE INDEX IF NOT EXISTS idx_balances_wallet ON balances(wallet_id);
CREATE INDEX IF NOT EXISTS idx_balances_asset ON balances(asset_id);
CREATE INDEX IF NOT EXISTS idx_transactions_hash ON transactions(tx_hash);
CREATE INDEX IF NOT EXISTS idx_transactions_from_wallet ON transactions(from_wallet_id);
CREATE INDEX IF NOT EXISTS idx_transactions_status ON transactions(status);
CREATE INDEX IF NOT EXISTS idx_orders_pair_status ON orders(pair_id, status);
CREATE INDEX IF NOT EXISTS idx_orders_user ON orders(user_id);
CREATE INDEX IF NOT EXISTS idx_trades_pair ON trades(pair_id);
CREATE INDEX IF NOT EXISTS idx_perpetuals_user ON perpetual_positions(user_id);
CREATE INDEX IF NOT EXISTS idx_perpetuals_status ON perpetual_positions(status);
CREATE INDEX IF NOT EXISTS idx_oracle_logs_asset_time ON oracle_price_logs(asset_id, timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_audit_logs_user_time ON audit_logs(user_id, created_at DESC);

-- =============================================================
-- Analytical Portfolio Views
-- =============================================================
CREATE OR REPLACE VIEW v_user_portfolio AS
SELECT 
    u.id AS user_id,
    u.email,
    w.wallet_id,
    w.address,
    w.network,
    a.symbol AS asset_symbol,
    a.name AS asset_name,
    b.amount AS total_balance,
    b.locked_amount,
    b.staked_amount,
    a.price_usd,
    ((b.amount + b.staked_amount) * a.price_usd) AS estimated_value_usd
FROM users u
JOIN wallets w ON u.id = w.user_id
JOIN balances b ON w.wallet_id = b.wallet_id
JOIN assets a ON b.asset_id = a.asset_id
WHERE w.is_active = TRUE;

CREATE OR REPLACE VIEW v_market_ticker_24h AS
SELECT 
    p.pair_id,
    p.pair_symbol,
    COALESCE(last_t.price, 0) AS last_price,
    COALESCE(SUM(t.quantity), 0) AS volume_24h,
    COALESCE(MAX(t.price), 0) AS high_24h,
    COALESCE(MIN(t.price), 0) AS low_24h
FROM orderbook_pairs p
LEFT JOIN trades t ON p.pair_id = t.pair_id AND t.created_at >= (NOW() - INTERVAL '24 hours')
LEFT JOIN LATERAL (
    SELECT price FROM trades WHERE pair_id = p.pair_id ORDER BY created_at DESC LIMIT 1
) last_t ON TRUE
WHERE p.is_active = TRUE
GROUP BY p.pair_id, p.pair_symbol, last_t.price;
