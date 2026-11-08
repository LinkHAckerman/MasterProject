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
END $$;

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
    is_token BOOLEAN NOT NULL DEFAULT TRUE,
    token_type VARCHAR(50) CHECK (token_type IN ('ERC20', 'ERC721', 'ERC1155', 'BEP20', 'BEP2', 'BSCToken', 'SolanaSPL', 'AVAXToken', 'PolygonToken', 'WrappedToken')),
    total_supply NUMERIC(38,18) DEFAULT 0,
    price_usd NUMERIC(24,8) DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (symbol, network),
    CONSTRAINT chk_token_network CHECK (network IN ('Ethereum', 'Polygon', 'BinanceSmartChain', 'Solana', 'Avalanche', 'PolygonZK', 'Arbitrum', 'Optimism', 'Base', 'Mantle'))
);

DROP TRIGGER IF EXISTS trg_assets_updated_at ON assets;
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
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (wallet_id, asset_id)
);

DROP TRIGGER IF EXISTS trg_balances_updated_at ON balances;
CREATE TRIGGER trg_balances_updated_at
BEFORE UPDATE ON balances
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- =============================================================
-- Transactions Ledger
-- =============================================================
CREATE TABLE IF NOT EXISTS transactions (
    transaction_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tx_hash VARCHAR(80) NOT NULL UNIQUE,
    wallet_id UUID NOT NULL REFERENCES wallets(wallet_id) ON DELETE CASCADE,
    asset_id UUID REFERENCES assets(asset_id),
    type tx_type NOT NULL,
    status tx_status NOT NULL DEFAULT 'pending',
    from_address VARCHAR(66) NOT NULL,
    to_address VARCHAR(66) NOT NULL,
    amount NUMERIC(38,18) NOT NULL DEFAULT 0,
    gas_fee NUMERIC(38,18) DEFAULT 0,
    block_number BIGINT,
    network VARCHAR(30) NOT NULL,
    payload JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    confirmed_at TIMESTAMPTZ
);

-- =============================================================
-- NFT Collections and Tokens
-- =============================================================
CREATE TABLE IF NOT EXISTS nft_collections (
    collection_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    contract_address VARCHAR(66) NOT NULL UNIQUE,
    network VARCHAR(30) NOT NULL,
    name VARCHAR(255) NOT NULL,
    symbol VARCHAR(50) NOT NULL,
    standard VARCHAR(20) NOT NULL DEFAULT 'ERC721',
    royalty_fee_bps INT DEFAULT 250 CHECK (royalty_fee_bps BETWEEN 0 AND 10000),
    royalty_recipient VARCHAR(66),
    floor_price_usd NUMERIC(24,8) DEFAULT 0,
    total_items INT DEFAULT 0,
    metadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS nft_tokens (
    token_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    collection_id UUID NOT NULL REFERENCES nft_collections(collection_id) ON DELETE CASCADE,
    token_identifier VARCHAR(100) NOT NULL,
    owner_wallet_id UUID REFERENCES wallets(wallet_id) ON DELETE SET NULL,
    token_uri TEXT,
    rarity nft_rarity DEFAULT 'common',
    attributes JSONB DEFAULT '[]'::jsonb,
    minted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(collection_id, token_identifier)
);

-- =============================================================
-- Decentralized Exchange (DEX) Orders
-- =============================================================
CREATE TABLE IF NOT EXISTS dex_orders (
    order_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    wallet_id UUID NOT NULL REFERENCES wallets(wallet_id) ON DELETE CASCADE,
    base_asset_id UUID NOT NULL REFERENCES assets(asset_id),
    quote_asset_id UUID NOT NULL REFERENCES assets(asset_id),
    side order_side NOT NULL,
    type order_type NOT NULL,
    price NUMERIC(38,18) NOT NULL,
    amount NUMERIC(38,18) NOT NULL,
    filled_amount NUMERIC(38,18) NOT NULL DEFAULT 0,
    status order_status NOT NULL DEFAULT 'open',
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =============================================================
-- Perpetual Futures Positions
-- =============================================================
CREATE TABLE IF NOT EXISTS perpetual_positions (
    position_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    wallet_id UUID NOT NULL REFERENCES wallets(wallet_id) ON DELETE CASCADE,
    asset_id UUID NOT NULL REFERENCES assets(asset_id),
    side order_side NOT NULL,
    leverage NUMERIC(5,2) NOT NULL DEFAULT 1.00 CHECK (leverage >= 1.00 AND leverage <= 125.00),
    entry_price NUMERIC(38,18) NOT NULL,
    mark_price NUMERIC(38,18) NOT NULL,
    liquidation_price NUMERIC(38,18) NOT NULL,
    margin_amount NUMERIC(38,18) NOT NULL,
    unrealized_pnl NUMERIC(38,18) DEFAULT 0,
    status position_status NOT NULL DEFAULT 'active',
    opened_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    closed_at TIMESTAMPTZ
);

-- =============================================================
-- DeFi Lending and Borrowing
-- =============================================================
CREATE TABLE IF NOT EXISTS lending_positions (
    lending_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    wallet_id UUID NOT NULL REFERENCES wallets(wallet_id) ON DELETE CASCADE,
    asset_id UUID NOT NULL REFERENCES assets(asset_id),
    action lending_action NOT NULL,
    principal_amount NUMERIC(38,18) NOT NULL DEFAULT 0,
    interest_rate_apy NUMERIC(8,4) NOT NULL DEFAULT 0,
    collateral_factor NUMERIC(5,4) NOT NULL DEFAULT 0.7500,
    health_factor NUMERIC(8,4) DEFAULT 1.0000,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =============================================================
-- Staking Pools & Deposits
-- =============================================================
CREATE TABLE IF NOT EXISTS staking_pools (
    pool_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(100) NOT NULL,
    staked_asset_id UUID NOT NULL REFERENCES assets(asset_id),
    reward_asset_id UUID NOT NULL REFERENCES assets(asset_id),
    apy_percentage NUMERIC(8,4) NOT NULL DEFAULT 0,
    lockup_days INT DEFAULT 0,
    total_staked NUMERIC(38,18) DEFAULT 0,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS staking_deposits (
    deposit_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    pool_id UUID NOT NULL REFERENCES staking_pools(pool_id) ON DELETE CASCADE,
    wallet_id UUID NOT NULL REFERENCES wallets(wallet_id) ON DELETE CASCADE,
    staked_amount NUMERIC(38,18) NOT NULL DEFAULT 0,
    rewards_claimed NUMERIC(38,18) NOT NULL DEFAULT 0,
    unclaimed_rewards NUMERIC(38,18) NOT NULL DEFAULT 0,
    locked_until TIMESTAMPTZ,
    staked_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =============================================================
-- Cross-Chain Bridge Transfers
-- =============================================================
CREATE TABLE IF NOT EXISTS bridge_transactions (
    bridge_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    sender_wallet_id UUID NOT NULL REFERENCES wallets(wallet_id),
    source_network VARCHAR(30) NOT NULL,
    target_network VARCHAR(30) NOT NULL,
    source_tx_hash VARCHAR(80) NOT NULL UNIQUE,
    target_tx_hash VARCHAR(80),
    asset_id UUID NOT NULL REFERENCES assets(asset_id),
    amount NUMERIC(38,18) NOT NULL,
    bridge_fee NUMERIC(38,18) DEFAULT 0,
    status bridge_status NOT NULL DEFAULT 'initiated',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at TIMESTAMPTZ
);

-- =============================================================
-- Governance DAO Proposals & Votes
-- =============================================================
CREATE TABLE IF NOT EXISTS dao_proposals (
    proposal_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    proposer_wallet_id UUID NOT NULL REFERENCES wallets(wallet_id),
    title VARCHAR(255) NOT NULL,
    description TEXT NOT NULL,
    target_contract VARCHAR(66),
    calldata TEXT,
    for_votes NUMERIC(38,18) DEFAULT 0,
    against_votes NUMERIC(38,18) DEFAULT 0,
    abstain_votes NUMERIC(38,18) DEFAULT 0,
    status proposal_status NOT NULL DEFAULT 'draft',
    start_time TIMESTAMPTZ NOT NULL,
    end_time TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    executed_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS dao_votes (
    vote_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    proposal_id UUID NOT NULL REFERENCES dao_proposals(proposal_id) ON DELETE CASCADE,
    voter_wallet_id UUID NOT NULL REFERENCES wallets(wallet_id),
    support_type SMALLINT NOT NULL CHECK (support_type IN (0, 1, 2)),
    voting_power NUMERIC(38,18) NOT NULL DEFAULT 0,
    reason TEXT,
    voted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(proposal_id, voter_wallet_id)
);

-- =============================================================
-- System Audit Logs
-- =============================================================
CREATE TABLE IF NOT EXISTS audit_logs (
    log_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    action VARCHAR(100) NOT NULL,
    resource_type VARCHAR(50) NOT NULL,
    resource_id VARCHAR(100),
    ip_address VARCHAR(45),
    user_agent TEXT,
    details JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =============================================================
-- High-Performance Indexes
-- =============================================================
CREATE INDEX IF NOT EXISTS idx_wallets_user ON wallets(user_id);
CREATE INDEX IF NOT EXISTS idx_wallets_address ON wallets(address);
CREATE INDEX IF NOT EXISTS idx_assets_symbol_network ON assets(symbol, network);
CREATE INDEX IF NOT EXISTS idx_balances_wallet ON balances(wallet_id);
CREATE INDEX IF NOT EXISTS idx_tx_wallet_status ON transactions(wallet_id, status);
CREATE INDEX IF NOT EXISTS idx_tx_hash ON transactions(tx_hash);
CREATE INDEX IF NOT EXISTS idx_tx_created ON transactions(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_nft_tokens_owner ON nft_tokens(owner_wallet_id);
CREATE INDEX IF NOT EXISTS idx_dex_orders_wallet ON dex_orders(wallet_id, status);
CREATE INDEX IF NOT EXISTS idx_perp_positions_wallet ON perpetual_positions(wallet_id, status);
CREATE INDEX IF NOT EXISTS idx_lending_wallet ON lending_positions(wallet_id);
CREATE INDEX IF NOT EXISTS idx_bridge_tx_status ON bridge_transactions(status);
CREATE INDEX IF NOT EXISTS idx_dao_votes_proposal ON dao_votes(proposal_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_user ON audit_logs(user_id, created_at DESC);
