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
    CONSTRAINT uq_nft_token UNIQUE (collection_id, token_index)
);

CREATE TRIGGER trg_nft_tokens_updated_at
BEFORE UPDATE ON nft_tokens
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- Core Transaction Table (captures on‑chain and off‑chain events)
CREATE TABLE IF NOT EXISTS transactions (
    tx_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    wallet_id UUID NOT NULL REFERENCES wallets(wallet_id) ON DELETE CASCADE,
    asset_id UUID NOT NULL REFERENCES assets(asset_id) ON DELETE RESTRICT,
    tx_type tx_type NOT NULL,
    status tx_status NOT NULL DEFAULT 'pending',
    amount NUMERIC(38,18) NOT NULL CHECK (amount >= 0),
    fee NUMERIC(38,18) NOT NULL DEFAULT 0,
    tx_hash VARCHAR(66) UNIQUE,
    block_number BIGINT,
    timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_transactions_updated_at
BEFORE UPDATE ON transactions
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- Order Book Table for DEX functionality
CREATE TABLE IF NOT EXISTS orders (
    order_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    wallet_id UUID NOT NULL REFERENCES wallets(wallet_id) ON DELETE CASCADE,
    base_asset_id UUID NOT NULL REFERENCES assets(asset_id) ON DELETE RESTRICT,
    quote_asset_id UUID NOT NULL REFERENCES assets(asset_id) ON DELETE RESTRICT,
    side order_side NOT NULL,
    order_type order_type NOT NULL,
    status order_status NOT NULL DEFAULT 'open',
    price NUMERIC(38,18) NOT NULL CHECK (price > 0),
    quantity NUMERIC(38,18) NOT NULL CHECK (quantity > 0),
    filled_quantity NUMERIC(38,18) NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ,
    metadata JSONB DEFAULT '{}'::jsonb,
    CONSTRAINT chk_order_side CHECK (side IN ('buy', 'sell')),
    CONSTRAINT chk_order_type CHECK (order_type IN ('limit', 'market', 'stop_loss', 'take_profit'))
);

CREATE TRIGGER trg_orders_updated_at
BEFORE UPDATE ON orders
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- Position Table for margin/futures trading
CREATE TABLE IF NOT EXISTS positions (
    position_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    wallet_id UUID NOT NULL REFERENCES wallets(wallet_id) ON DELETE CASCADE,
    base_asset_id UUID NOT NULL REFERENCES assets(asset_id) ON DELETE RESTRICT,
    quote_asset_id UUID NOT NULL REFERENCES assets(asset_id) ON DELETE RESTRICT,
    side order_side NOT NULL,
    size NUMERIC(38,18) NOT NULL CHECK (size > 0),
    entry_price NUMERIC(38,18) NOT NULL CHECK (entry_price > 0),
    leverage SMALLINT NOT NULL CHECK (leverage BETWEEN 1 AND 125),
    status position_status NOT NULL DEFAULT 'active',
    opened_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    closed_at TIMESTAMPTZ,
    metadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_positions_updated_at
BEFORE UPDATE ON positions
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- Lending Protocol Activity Table
CREATE TABLE IF NOT EXISTS lending_activities (
    activity_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    wallet_id UUID NOT NULL REFERENCES wallets(wallet_id) ON DELETE CASCADE,
    asset_id UUID NOT NULL REFERENCES assets(asset_id) ON DELETE RESTRICT,
    action lending_action NOT NULL,
    amount NUMERIC(38,18) NOT NULL CHECK (amount > 0),
    interest_rate NUMERIC(10,6) NOT NULL DEFAULT 0,
    accrued_interest NUMERIC(38,18) NOT NULL DEFAULT 0,
    status tx_status NOT NULL DEFAULT 'pending',
    tx_hash VARCHAR(66) UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'::jsonb
);

CREATE TRIGGER trg_lending_activities_updated_at
BEFORE UPDATE ON lending_activities
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- Price History Table (oracle snapshots)
CREATE TABLE IF NOT EXISTS price_snapshots (
    snapshot_id BIGSERIAL PRIMARY KEY,
    asset_id UUID NOT NULL REFERENCES assets(asset_id) ON DELETE CASCADE,
    price_usd NUMERIC(24,8) NOT NULL CHECK (price_usd >= 0),
    source VARCHAR(50) NOT NULL,
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes for performance
CREATE INDEX idx_wallets_user_id ON wallets(user_id);
CREATE INDEX idx_transactions_wallet_id ON transactions(wallet_id);
CREATE INDEX idx_transactions_asset_id ON transactions(asset_id);
CREATE INDEX idx_orders_wallet_id ON orders(wallet_id);
CREATE INDEX idx_orders_status ON orders(status);
CREATE INDEX idx_positions_wallet_id ON positions(wallet_id);
CREATE INDEX idx_lending_wallet_id ON lending_activities(wallet_id);
CREATE INDEX idx_price_snapshots_asset_id ON price_snapshots(asset_id);

-- Ensure referential integrity for NFT ownership transfers
ALTER TABLE nft_tokens
    ADD CONSTRAINT fk_nft_owner_wallet FOREIGN KEY (owner_address)
    REFERENCES wallets(address) ON DELETE SET NULL;
