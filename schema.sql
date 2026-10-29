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
    total_supply NUMERIC(38, 18) DEFAULT 0,
    price_usd NUMERIC(24, 8) DEFAULT 0,
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

-- Balances (current snapshot)
CREATE TABLE IF NOT EXISTS balances (
    wallet_id UUID NOT NULL REFERENCES wallets(wallet_id) ON DELETE CASCADE,
    asset_id UUID NOT NULL REFERENCES assets(asset_id) ON DELETE RESTRICT,
    balance NUMERIC(38, 18) NOT NULL DEFAULT 0 CHECK (balance >= 0),
    last_updated TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_locked BOOLEAN NOT NULL DEFAULT FALSE,
    lock_reason TEXT,
    PRIMARY KEY (wallet_id, asset_id)
);

-- Transactions with Enhanced Metadata
CREATE TABLE IF NOT EXISTS transactions (
    tx_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    wallet_id UUID NOT NULL REFERENCES wallets(wallet_id) ON DELETE CASCADE,
    asset_id UUID NOT NULL REFERENCES assets(asset_id) ON DELETE RESTRICT,
    tx_hash VARCHAR(66) NOT NULL UNIQUE,
    block_number BIGINT,
    type tx_type NOT NULL DEFAULT 'transfer',
    status tx_status NOT NULL DEFAULT 'pending',
    from_address VARCHAR(66) NOT NULL,
    to_address VARCHAR(66) NOT NULL,
    amount NUMERIC(38, 18) NOT NULL DEFAULT 0,
    gas_fee NUMERIC(38, 18) DEFAULT 0,
    gas_used BIGINT DEFAULT 0,
    nonce BIGINT DEFAULT 0,
    metadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_transactions_updated_at
BEFORE UPDATE ON transactions
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- DEX Pools (Automated Market Maker Pools)
CREATE TABLE IF NOT EXISTS dex_pools (
    pool_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    token0_id UUID NOT NULL REFERENCES assets(asset_id) ON DELETE RESTRICT,
    token1_id UUID NOT NULL REFERENCES assets(asset_id) ON DELETE RESTRICT,
    reserve0 NUMERIC(38, 18) NOT NULL DEFAULT 0,
    reserve1 NUMERIC(38, 18) NOT NULL DEFAULT 0,
    fee_bps INT NOT NULL DEFAULT 30 CHECK (fee_bps BETWEEN 0 AND 1000),
    total_liquidity NUMERIC(38, 18) NOT NULL DEFAULT 0,
    lp_asset_id UUID REFERENCES assets(asset_id) ON DELETE SET NULL,
    network VARCHAR(30) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (token0_id, token1_id, network)
);

CREATE TRIGGER trg_dex_pools_updated_at
BEFORE UPDATE ON dex_pools
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- Liquidity Positions in DEX Pools
CREATE TABLE IF NOT EXISTS liquidity_positions (
    position_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    wallet_id UUID NOT NULL REFERENCES wallets(wallet_id) ON DELETE CASCADE,
    pool_id UUID NOT NULL REFERENCES dex_pools(pool_id) ON DELETE CASCADE,
    lp_tokens NUMERIC(38, 18) NOT NULL DEFAULT 0,
    staked_amount0 NUMERIC(38, 18) NOT NULL DEFAULT 0,
    staked_amount1 NUMERIC(38, 18) NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (wallet_id, pool_id)
);

CREATE TRIGGER trg_liquidity_positions_updated_at
BEFORE UPDATE ON liquidity_positions
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- Staking Pools (Yield Farming / Staking)
CREATE TABLE IF NOT EXISTS staking_pools (
    staking_pool_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    staked_asset_id UUID NOT NULL REFERENCES assets(asset_id) ON DELETE CASCADE,
    reward_asset_id UUID NOT NULL REFERENCES assets(asset_id) ON DELETE CASCADE,
    apr_bps INT NOT NULL DEFAULT 1200 CHECK (apr_bps >= 0),
    total_staked NUMERIC(38, 18) NOT NULL DEFAULT 0,
    min_lock_seconds INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_staking_pools_updated_at
BEFORE UPDATE ON staking_pools
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- Staking Positions
CREATE TABLE IF NOT EXISTS staking_positions (
    position_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    wallet_id UUID NOT NULL REFERENCES wallets(wallet_id) ON DELETE CASCADE,
    staking_pool_id UUID NOT NULL REFERENCES staking_pools(staking_pool_id) ON DELETE CASCADE,
    amount_staked NUMERIC(38, 18) NOT NULL DEFAULT 0,
    unclaimed_rewards NUMERIC(38, 18) NOT NULL DEFAULT 0,
    staked_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    unlock_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_staking_positions_updated_at
BEFORE UPDATE ON staking_positions
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- Lending Markets
CREATE TABLE IF NOT EXISTS lending_markets (
    market_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    asset_id UUID NOT NULL REFERENCES assets(asset_id) ON DELETE CASCADE,
    total_supplied NUMERIC(38, 18) NOT NULL DEFAULT 0,
    total_borrowed NUMERIC(38, 18) NOT NULL DEFAULT 0,
    supply_rate_bps INT NOT NULL DEFAULT 450,
    borrow_rate_bps INT NOT NULL DEFAULT 750,
    collateral_factor_bps INT NOT NULL DEFAULT 7500 CHECK (collateral_factor_bps BETWEEN 0 AND 10000),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (asset_id)
);

CREATE TRIGGER trg_lending_markets_updated_at
BEFORE UPDATE ON lending_markets
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- Orderbook Engine Orders
CREATE TABLE IF NOT EXISTS orders (
    order_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    wallet_id UUID NOT NULL REFERENCES wallets(wallet_id) ON DELETE CASCADE,
    base_asset_id UUID NOT NULL REFERENCES assets(asset_id) ON DELETE CASCADE,
    quote_asset_id UUID NOT NULL REFERENCES assets(asset_id) ON DELETE CASCADE,
    side order_side NOT NULL,
    type order_type NOT NULL DEFAULT 'limit',
    status order_status NOT NULL DEFAULT 'open',
    price NUMERIC(38, 18) NOT NULL DEFAULT 0,
    amount NUMERIC(38, 18) NOT NULL DEFAULT 0,
    filled_amount NUMERIC(38, 18) NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_orders_updated_at
BEFORE UPDATE ON orders
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- Executed Trades
CREATE TABLE IF NOT EXISTS trades (
    trade_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    buy_order_id UUID REFERENCES orders(order_id) ON DELETE SET NULL,
    sell_order_id UUID REFERENCES orders(order_id) ON DELETE SET NULL,
    base_asset_id UUID NOT NULL REFERENCES assets(asset_id) ON DELETE CASCADE,
    quote_asset_id UUID NOT NULL REFERENCES assets(asset_id) ON DELETE CASCADE,
    price NUMERIC(38, 18) NOT NULL,
    amount NUMERIC(38, 18) NOT NULL,
    tx_hash VARCHAR(66),
    executed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Oracle Price Feeds
CREATE TABLE IF NOT EXISTS oracle_feeds (
    feed_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    asset_id UUID NOT NULL REFERENCES assets(asset_id) ON DELETE CASCADE,
    symbol VARCHAR(20) NOT NULL,
    price_usd NUMERIC(24, 8) NOT NULL,
    decimals SMALLINT NOT NULL DEFAULT 8,
    provider VARCHAR(50) NOT NULL DEFAULT 'Chainlink',
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (asset_id, provider)
);

CREATE TRIGGER trg_oracle_feeds_updated_at
BEFORE UPDATE ON oracle_feeds
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- Price History Series
CREATE TABLE IF NOT EXISTS price_history (
    id BIGSERIAL PRIMARY KEY,
    asset_id UUID NOT NULL REFERENCES assets(asset_id) ON DELETE CASCADE,
    price_usd NUMERIC(24, 8) NOT NULL,
    volume_24h NUMERIC(38, 18) DEFAULT 0,
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Blockchain Node Management & Sync Status
CREATE TABLE IF NOT EXISTS blockchain_nodes (
    node_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    network VARCHAR(30) NOT NULL UNIQUE,
    rpc_url VARCHAR(255) NOT NULL,
    ws_url VARCHAR(255),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    latest_block_number BIGINT DEFAULT 0,
    sync_lag_ms INT DEFAULT 0,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_blockchain_nodes_updated_at
BEFORE UPDATE ON blockchain_nodes
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- System Audit Logs
CREATE TABLE IF NOT EXISTS audit_logs (
    log_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    action VARCHAR(100) NOT NULL,
    entity_type VARCHAR(50) NOT NULL,
    entity_id VARCHAR(100),
    payload JSONB DEFAULT '{}'::jsonb,
    ip_address VARCHAR(45),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes for Query Performance
CREATE INDEX IF NOT EXISTS idx_wallets_user_id ON wallets(user_id);
CREATE INDEX IF NOT EXISTS idx_wallets_address ON wallets(address);
CREATE INDEX IF NOT EXISTS idx_transactions_wallet ON transactions(wallet_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_transactions_hash ON transactions(tx_hash);
CREATE INDEX IF NOT EXISTS idx_transactions_addresses ON transactions(from_address, to_address);
CREATE INDEX IF NOT EXISTS idx_balances_wallet_asset ON balances(wallet_id, asset_id);
CREATE INDEX IF NOT EXISTS idx_nft_tokens_owner ON nft_tokens(owner_address);
CREATE INDEX IF NOT EXISTS idx_orders_wallet_status ON orders(wallet_id, status);
CREATE INDEX IF NOT EXISTS idx_orders_pair ON orders(base_asset_id, quote_asset_id, status);
CREATE INDEX IF NOT EXISTS idx_price_history_asset ON price_history(asset_id, recorded_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_logs_user ON audit_logs(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_users_metadata_gin ON users USING GIN (metadata);
CREATE INDEX IF NOT EXISTS idx_transactions_metadata_gin ON transactions USING GIN (metadata);

-- Useful Analytical Views
CREATE OR REPLACE VIEW vw_user_portfolio AS
SELECT 
    w.user_id,
    w.wallet_id,
    w.address AS wallet_address,
    w.network,
    a.asset_id,
    a.symbol,
    a.name AS asset_name,
    b.balance,
    a.price_usd,
    (b.balance * a.price_usd) AS usd_value,
    b.is_locked,
    b.last_updated
FROM balances b
JOIN wallets w ON b.wallet_id = w.wallet_id
JOIN assets a ON b.asset_id = a.asset_id
WHERE w.is_active = TRUE;

CREATE OR REPLACE VIEW vw_dex_pool_overview AS
SELECT 
    p.pool_id,
    p.network,
    a0.symbol AS token0_symbol,
    a1.symbol AS token1_symbol,
    p.reserve0,
    p.reserve1,
    p.fee_bps,
    p.total_liquidity,
    ((p.reserve0 * a0.price_usd) + (p.reserve1 * a1.price_usd)) AS tvl_usd,
    p.updated_at
FROM dex_pools p
JOIN assets a0 ON p.token0_id = a0.asset_id
JOIN assets a1 ON p.token1_id = a1.asset_id;

-- Initial Seed Data Insertion
INSERT INTO users (id, email, password_hash, full_name, is_verified, status)
VALUES 
    ('00000000-0000-0000-0000-000000000001', 'admin@magnumopus.io', '$2a$12$eImiTXuWVxfM37uY4JANjO2B.8.sU3.1zUfN.e7g8mN9k.q.R.s.y', 'Magnum Architect', TRUE, 'verified')
ON CONFLICT (email) DO NOTHING;

INSERT INTO assets (asset_id, symbol, name, decimals, contract_address, network, is_nft, is_token, token_type, price_usd)
VALUES 
    ('11111111-1111-1111-1111-111111111111', 'ETH', 'Ethereum Native', 18, '0x0000000000000000000000000000000000000000', 'Ethereum', FALSE, TRUE, 'WrappedToken', 3500.00),
    ('22222222-2222-2222-2222-222222222222', 'USDT', 'Tether USD', 6, '0xdAC17F958D2ee523a2206206994597C13D831ec7', 'Ethereum', FALSE, TRUE, 'ERC20', 1.00),
    ('33333333-3333-3333-3333-333333333333', 'OPUS', 'Magnum Opus Token', 18, '0x8888888888888888888888888888888888888888', 'Ethereum', FALSE, TRUE, 'ERC20', 42.50),
    ('44444444-4444-4444-4444-444444444444', 'SOL', 'Solana Native', 9, '11111111111111111111111111111111', 'Solana', FALSE, TRUE, 'SolanaSPL', 145.00)
ON CONFLICT (symbol, network) DO NOTHING;
