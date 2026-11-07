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
    amount NUMERIC(38,18) NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (wallet_id, asset_id)
);

CREATE TRIGGER trg_balances_updated_at
BEFORE UPDATE ON balances
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- =============================================================
-- Transaction History
-- =============================================================
CREATE TABLE IF NOT EXISTS transactions (
    tx_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    wallet_id UUID NOT NULL REFERENCES wallets(wallet_id) ON DELETE CASCADE,
    asset_id UUID NOT NULL REFERENCES assets(asset_id) ON DELETE CASCADE,
    amount NUMERIC(38,18) NOT NULL,
    fee NUMERIC(38,18) NOT NULL DEFAULT 0,
    status tx_status NOT NULL DEFAULT 'pending',
    tx_type tx_type NOT NULL,
    tx_hash VARCHAR(66),
    from_address VARCHAR(66),
    to_address VARCHAR(66),
    block_number BIGINT,
    block_timestamp TIMESTAMPTZ,
    nonce BIGINT,
    gas_price NUMERIC(38,18),
    gas_limit BIGINT,
    gas_used BIGINT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'::jsonb
);

CREATE TRIGGER trg_transactions_updated_at
BEFORE UPDATE ON transactions
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- =============================================================
-- Order Book for DEX
-- =============================================================
CREATE TABLE IF NOT EXISTS orders (
    order_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    wallet_id UUID NOT NULL REFERENCES wallets(wallet_id) ON DELETE CASCADE,
    base_asset_id UUID NOT NULL REFERENCES assets(asset_id) ON DELETE CASCADE,
    quote_asset_id UUID NOT NULL REFERENCES assets(asset_id) ON DELETE CASCADE,
    side order_side NOT NULL,
    order_type order_type NOT NULL,
    price NUMERIC(38,18),
    amount NUMERIC(38,18) NOT NULL,
    filled_amount NUMERIC(38,18) NOT NULL DEFAULT 0,
    status order_status NOT NULL DEFAULT 'open',
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'::jsonb
);

CREATE TRIGGER trg_orders_updated_at
BEFORE UPDATE ON orders
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- =============================================================
-- Trade History for DEX
-- =============================================================
CREATE TABLE IF NOT EXISTS trades (
    trade_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id UUID NOT NULL REFERENCES orders(order_id) ON DELETE CASCADE,
    base_asset_id UUID NOT NULL REFERENCES assets(asset_id) ON DELETE CASCADE,
    quote_asset_id UUID NOT NULL REFERENCES assets(asset_id) ON DELETE CASCADE,
    price NUMERIC(38,18) NOT NULL,
    amount NUMERIC(38,18) NOT NULL,
    side order_side NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'::jsonb
);

CREATE TRIGGER trg_trades_updated_at
BEFORE UPDATE ON trades
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- =============================================================
-- Lending Protocol
-- =============================================================
CREATE TABLE IF NOT EXISTS lending_protocol (
    lending_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    wallet_id UUID NOT NULL REFERENCES wallets(wallet_id) ON DELETE CASCADE,
    asset_id UUID NOT NULL REFERENCES assets(asset_id) ON DELETE CASCADE,
    action lending_action NOT NULL,
    amount NUMERIC(38,18) NOT NULL,
    interest_rate NUMERIC(10,8) NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'::jsonb
);

CREATE TRIGGER trg_lending_protocol_updated_at
BEFORE UPDATE ON lending_protocol
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- =============================================================
-- DAO Proposals
-- =============================================================
CREATE TABLE IF NOT EXISTS dao_proposals (
    proposal_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    wallet_id UUID NOT NULL REFERENCES wallets(wallet_id) ON DELETE CASCADE,
    title VARCHAR(255) NOT NULL,
    description TEXT,
    status proposal_status NOT NULL DEFAULT 'draft',
    start_time TIMESTAMPTZ NOT NULL,
    end_time TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'::jsonb
);

CREATE TRIGGER trg_dao_proposals_updated_at
BEFORE UPDATE ON dao_proposals
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- =============================================================
-- DAO Votes
-- =============================================================
CREATE TABLE IF NOT EXISTS dao_votes (
    vote_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    proposal_id UUID NOT NULL REFERENCES dao_proposals(proposal_id) ON DELETE CASCADE,
    wallet_id UUID NOT NULL REFERENCES wallets(wallet_id) ON DELETE CASCADE,
    vote BOOLEAN NOT NULL,
    weight NUMERIC(38,18) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'::jsonb
);

CREATE TRIGGER trg_dao_votes_updated_at
BEFORE UPDATE ON dao_votes
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- =============================================================
-- Bridge Transactions
-- =============================================================
CREATE TABLE IF NOT EXISTS bridge_transactions (
    bridge_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    wallet_id UUID NOT NULL REFERENCES wallets(wallet_id) ON DELETE CASCADE,
    asset_id UUID NOT NULL REFERENCES assets(asset_id) ON DELETE CASCADE,
    amount NUMERIC(38,18) NOT NULL,
    fee NUMERIC(38,18) NOT NULL DEFAULT 0,
    status bridge_status NOT NULL DEFAULT 'initiated',
    from_network VARCHAR(30) NOT NULL,
    to_network VARCHAR(30) NOT NULL,
    from_tx_hash VARCHAR(66),
    to_tx_hash VARCHAR(66),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'::jsonb,
    CONSTRAINT chk_bridge_networks CHECK (from_network IN ('Ethereum', 'Polygon', 'BinanceSmartChain', 'Solana', 'Avalanche', 'PolygonZK', 'Arbitrum', 'Optimism', 'Base', 'Mantle') AND to_network IN ('Ethereum', 'Polygon', 'BinanceSmartChain', 'Solana', 'Avalanche', 'PolygonZK', 'Arbitrum', 'Optimism', 'Base', 'Mantle'))
);

CREATE TRIGGER trg_bridge_transactions_updated_at
BEFORE UPDATE ON bridge_transactions
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- =============================================================
-- NFT Metadata
-- =============================================================
CREATE TABLE IF NOT EXISTS nft_metadata (
    metadata_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    asset_id UUID NOT NULL REFERENCES assets(asset_id) ON DELETE CASCADE,
    token_id VARCHAR(66) NOT NULL,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    image_url VARCHAR(255),
    external_url VARCHAR(255),
    attributes JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (asset_id, token_id)
);

CREATE TRIGGER trg_nft_metadata_updated_at
BEFORE UPDATE ON nft_metadata
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- =============================================================
-- NFT Ownership
-- =============================================================
CREATE TABLE IF NOT EXISTS nft_ownership (
    ownership_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    wallet_id UUID NOT NULL REFERENCES wallets(wallet_id) ON DELETE CASCADE,
    asset_id UUID NOT NULL REFERENCES assets(asset_id) ON DELETE CASCADE,
    token_id VARCHAR(66) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (wallet_id, asset_id, token_id)
);

CREATE TRIGGER trg_nft_ownership_updated_at
BEFORE UPDATE ON nft_ownership
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- =============================================================
-- NFT Transactions
-- =============================================================
CREATE TABLE IF NOT EXISTS nft_transactions (
    nft_tx_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    wallet_id UUID NOT NULL REFERENCES wallets(wallet_id) ON DELETE CASCADE,
    asset_id UUID NOT NULL REFERENCES assets(asset_id) ON DELETE CASCADE,
    token_id VARCHAR(66) NOT NULL,
    amount NUMERIC(38,18) NOT NULL,
    fee NUMERIC(38,18) NOT NULL DEFAULT 0,
    status tx_status NOT NULL DEFAULT 'pending',
    tx_type tx_type NOT NULL,
    tx_hash VARCHAR(66),
    from_address VARCHAR(66),
    to_address VARCHAR(66),
    block_number BIGINT,
    block_timestamp TIMESTAMPTZ,
    nonce BIGINT,
    gas_price NUMERIC(38,18),
    gas_limit BIGINT,
    gas_used BIGINT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'::jsonb
);

CREATE TRIGGER trg_nft_transactions_updated_at
BEFORE UPDATE ON nft_transactions
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- =============================================================
-- Indexes for Performance Optimization
-- =============================================================
CREATE INDEX IF NOT EXISTS idx_wallets_user_id ON wallets(user_id);
CREATE INDEX IF NOT EXISTS idx_wallets_address ON wallets(address);
CREATE INDEX IF NOT EXISTS idx_assets_symbol_network ON assets(symbol, network);
CREATE INDEX IF NOT EXISTS idx_assets_contract_address ON assets(contract_address);
CREATE INDEX IF NOT EXISTS idx_balances_wallet_id ON balances(wallet_id);
CREATE INDEX IF NOT EXISTS idx_balances_asset_id ON balances(asset_id);
CREATE INDEX IF NOT EXISTS idx_transactions_wallet_id ON transactions(wallet_id);
CREATE INDEX IF NOT EXISTS idx_transactions_asset_id ON transactions(asset_id);
CREATE INDEX IF NOT EXISTS idx_transactions_tx_hash ON transactions(tx_hash);
CREATE INDEX IF NOT EXISTS idx_orders_wallet_id ON orders(wallet_id);
CREATE INDEX IF NOT EXISTS idx_orders_base_asset_id ON orders(base_asset_id);
CREATE INDEX IF NOT EXISTS idx_orders_quote_asset_id ON orders(quote_asset_id);
CREATE INDEX IF NOT EXISTS idx_trades_order_id ON trades(order_id);
CREATE INDEX IF NOT EXISTS idx_trades_base_asset_id ON trades(base_asset_id);
CREATE INDEX IF NOT EXISTS idx_trades_quote_asset_id ON trades(quote_asset_id);
CREATE INDEX IF NOT EXISTS idx_lending_protocol_wallet_id ON lending_protocol(wallet_id);
CREATE INDEX IF NOT EXISTS idx_lending_protocol_asset_id ON lending_protocol(asset_id);
CREATE INDEX IF NOT EXISTS idx_dao_proposals_wallet_id ON dao_proposals(wallet_id);
CREATE INDEX IF NOT EXISTS idx_dao_votes_proposal_id ON dao_votes(proposal_id);
CREATE INDEX IF NOT EXISTS idx_dao_votes_wallet_id ON dao_votes(wallet_id);
CREATE INDEX IF NOT EXISTS idx_bridge_transactions_wallet_id ON bridge_transactions(wallet_id);
CREATE INDEX IF NOT EXISTS idx_bridge_transactions_asset_id ON bridge_transactions(asset_id);
CREATE INDEX IF NOT EXISTS idx_nft_metadata_asset_id ON nft_metadata(asset_id);
CREATE INDEX IF NOT EXISTS idx_nft_metadata_token_id ON nft_metadata(token_id);
CREATE INDEX IF NOT EXISTS idx_nft_ownership_wallet_id ON nft_ownership(wallet_id);
CREATE INDEX IF NOT EXISTS idx_nft_ownership_asset_id ON nft_ownership(asset_id);
CREATE INDEX IF NOT EXISTS idx_nft_ownership_token_id ON nft_ownership(token_id);
CREATE INDEX IF NOT EXISTS idx_nft_transactions_wallet_id ON nft_transactions(wallet_id);
CREATE INDEX IF NOT EXISTS idx_nft_transactions_asset_id ON nft_transactions(asset_id);
CREATE INDEX IF NOT EXISTS idx_nft_transactions_token_id ON nft_transactions(token_id);
CREATE INDEX IF NOT EXISTS idx_nft_transactions_tx_hash ON nft_transactions(tx_hash);
