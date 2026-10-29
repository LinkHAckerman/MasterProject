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
    last_updated TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_wallet_asset UNIQUE (wallet_id, asset_id)
);

CREATE INDEX idx_balances_wallet ON balances(wallet_id);
CREATE INDEX idx_balances_asset ON balances(asset_id);

-- Transaction History
CREATE TABLE IF NOT EXISTS transactions (
    tx_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    wallet_id UUID NOT NULL REFERENCES wallets(wallet_id) ON DELETE CASCADE,
    asset_id UUID NOT NULL REFERENCES assets(asset_id) ON DELETE CASCADE,
    tx_type tx_type NOT NULL,
    status tx_status NOT NULL DEFAULT 'pending',
    amount NUMERIC(38,18) NOT NULL,
    tx_hash VARCHAR(66) UNIQUE,
    block_number BIGINT,
    nonce BIGINT,
    gas_price NUMERIC(38,0),
    gas_used NUMERIC(38,0),
    fee NUMERIC(38,18) GENERATED ALWAYS AS (gas_price * gas_used) STORED,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'::jsonb
);

CREATE INDEX idx_transactions_wallet ON transactions(wallet_id);
CREATE INDEX idx_transactions_asset ON transactions(asset_id);
CREATE INDEX idx_transactions_status ON transactions(status);
CREATE INDEX idx_transactions_type ON transactions(tx_type);

-- Order Book for DEX
CREATE TABLE IF NOT EXISTS orders (
    order_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    base_asset_id UUID NOT NULL REFERENCES assets(asset_id) ON DELETE CASCADE,
    quote_asset_id UUID NOT NULL REFERENCES assets(asset_id) ON DELETE CASCADE,
    side order_side NOT NULL,
    type order_type NOT NULL,
    status order_status NOT NULL DEFAULT 'open',
    price NUMERIC(38,18) NOT NULL,
    amount NUMERIC(38,18) NOT NULL,
    filled_amount NUMERIC(38,18) NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_order_price CHECK (price > 0),
    CONSTRAINT chk_order_amount CHECK (amount > 0)
);

CREATE TRIGGER trg_orders_updated_at
BEFORE UPDATE ON orders
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

CREATE INDEX idx_orders_user ON orders(user_id);
CREATE INDEX idx_orders_pair ON orders(base_asset_id, quote_asset_id);
CREATE INDEX idx_orders_status ON orders(status);

-- Price Feed Table (oracle snapshots)
CREATE TABLE IF NOT EXISTS price_feeds (
    feed_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    asset_id UUID NOT NULL REFERENCES assets(asset_id) ON DELETE CASCADE,
    price_usd NUMERIC(24,8) NOT NULL,
    source VARCHAR(100) NOT NULL,
    fetched_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_asset_source UNIQUE (asset_id, source)
);

CREATE INDEX idx_price_feeds_asset ON price_feeds(asset_id);
CREATE INDEX idx_price_feeds_fetched_at ON price_feeds(fetched_at);

-- Audit Log for critical actions
CREATE TABLE IF NOT EXISTS audit_logs (
    audit_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    action VARCHAR(255) NOT NULL,
    entity VARCHAR(100),
    entity_id UUID,
    ip_address INET,
    user_agent TEXT,
    performed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    details JSONB DEFAULT '{}'::jsonb
);

CREATE INDEX idx_audit_user ON audit_logs(user_id);
CREATE INDEX idx_audit_action ON audit_logs(action);
CREATE INDEX idx_audit_performed_at ON audit_logs(performed_at);

-- View: wallet_balances (convenient denormalized view)
CREATE OR REPLACE VIEW wallet_balances AS
SELECT
    w.wallet_id,
    w.address,
    w.network,
    a.asset_id,
    a.symbol,
    a.name,
    b.amount,
    a.price_usd,
    (b.amount * a.price_usd) AS value_usd,
    b.last_updated
FROM balances b
JOIN wallets w ON b.wallet_id = w.wallet_id
JOIN assets a ON b.asset_id = a.asset_id;

-- Ensure all tables have appropriate row-level security (optional)
-- ALTER TABLE users ENABLE ROW LEVEL SECURITY;
-- ALTER TABLE wallets ENABLE ROW LEVEL SECURITY;
-- ... (additional RLS policies can be added per project requirements)