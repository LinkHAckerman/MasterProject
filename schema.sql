-- ============================================================================
-- MAGNUM OPUS // Multi-Chain DeFi, NFT & Web3 Nexus Platform
-- PostgreSQL Production Schema Definition
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================================
-- 1. Enumerations & Custom Domain Types
-- ============================================================================

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'tx_status') THEN
        CREATE TYPE tx_status AS ENUM ('pending', 'submitted', 'confirmed', 'failed', 'reverted', 'dropped');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'tx_type') THEN
        CREATE TYPE tx_type AS ENUM (
            'transfer', 'swap', 'stake', 'unstake', 'deposit', 'withdraw',
            'mint', 'burn', 'liquidation', 'bridge', 'borrow', 'repay', 'claim_rewards'
        );
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
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'chain_family') THEN
        CREATE TYPE chain_family AS ENUM ('evm', 'solana', 'bitcoin', 'substrate', 'cosmos');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'auction_type') THEN
        CREATE TYPE auction_type AS ENUM ('fixed_price', 'english_auction', 'dutch_auction');
    END IF;
END $$;

-- ============================================================================
-- 2. Core Stored Procedures & Trigger Functions
-- ============================================================================

CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION generate_tx_id()
RETURNS VARCHAR AS $$
BEGIN
    RETURN 'TX-' || UPPER(SUBSTRING(MD5(CAST(NOW() AS TEXT) || CAST(RANDOM() AS TEXT)) FROM 1 FOR 16));
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION generate_wallet_id()
RETURNS VARCHAR AS $$
BEGIN
    RETURN 'WALLET-' || UPPER(SUBSTRING(MD5(CAST(NOW() AS TEXT) || CAST(RANDOM() AS TEXT)) FROM 1 FOR 16));
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION generate_nft_id()
RETURNS VARCHAR AS $$
BEGIN
    RETURN 'NFT-' || UPPER(SUBSTRING(MD5(CAST(NOW() AS TEXT) || CAST(RANDOM() AS TEXT)) FROM 1 FOR 16));
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- 3. Core Users, Authentication & Sessions
-- ============================================================================

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
    ip_address VARCHAR(45),
    user_agent TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    metadata JSONB DEFAULT '{}'::jsonb
);

-- ============================================================================
-- 4. Wallets & Transactions
-- ============================================================================

CREATE TABLE IF NOT EXISTS wallets (
    id VARCHAR(255) PRIMARY KEY DEFAULT generate_wallet_id(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    chain_family chain_family NOT NULL,
    address VARCHAR(255) NOT NULL,
    public_key TEXT,
    private_key_encrypted TEXT,
    is_default BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'::jsonb,
    CONSTRAINT unique_wallet_address UNIQUE (chain_family, address)
);

DROP TRIGGER IF EXISTS trg_wallets_updated_at ON wallets;
CREATE TRIGGER trg_wallets_updated_at
BEFORE UPDATE ON wallets
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

CREATE TABLE IF NOT EXISTS transactions (
    id VARCHAR(255) PRIMARY KEY DEFAULT generate_tx_id(),
    wallet_id VARCHAR(255) NOT NULL REFERENCES wallets(id) ON DELETE CASCADE,
    tx_hash VARCHAR(255),
    tx_type tx_type NOT NULL,
    status tx_status NOT NULL DEFAULT 'pending',
    from_address VARCHAR(255),
    to_address VARCHAR(255),
    amount DECIMAL(38, 18),
    fee DECIMAL(38, 18),
    nonce BIGINT,
    gas_limit BIGINT,
    gas_price DECIMAL(38, 18),
    data BYTEA,
    block_number BIGINT,
    block_hash VARCHAR(255),
    transaction_index BIGINT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'::jsonb
);

DROP TRIGGER IF EXISTS trg_transactions_updated_at ON transactions;
CREATE TRIGGER trg_transactions_updated_at
BEFORE UPDATE ON transactions
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- ============================================================================
-- 5. NFTs & Collections
-- ============================================================================

CREATE TABLE IF NOT EXISTS nft_collections (
    id VARCHAR(255) PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    symbol VARCHAR(20) NOT NULL,
    description TEXT,
    image_url VARCHAR(255),
    external_link VARCHAR(255),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'::jsonb
);

DROP TRIGGER IF EXISTS trg_nft_collections_updated_at ON nft_collections;
CREATE TRIGGER trg_nft_collections_updated_at
BEFORE UPDATE ON nft_collections
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

CREATE TABLE IF NOT EXISTS nfts (
    id VARCHAR(255) PRIMARY KEY DEFAULT generate_nft_id(),
    collection_id VARCHAR(255) REFERENCES nft_collections(id) ON DELETE CASCADE,
    token_id VARCHAR(255) NOT NULL,
    owner_id UUID REFERENCES users(id) ON DELETE SET NULL,
    rarity nft_rarity,
    name VARCHAR(255),
    description TEXT,
    image_url VARCHAR(255),
    external_url VARCHAR(255),
    attributes JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'::jsonb,
    CONSTRAINT unique_nft_token UNIQUE (collection_id, token_id)
);

DROP TRIGGER IF EXISTS trg_nfts_updated_at ON nfts;
CREATE TRIGGER trg_nfts_updated_at
BEFORE UPDATE ON nfts
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- ============================================================================
-- 6. DeFi & Trading
-- ============================================================================

CREATE TABLE IF NOT EXISTS tokens (
    id VARCHAR(255) PRIMARY KEY,
    chain_family chain_family NOT NULL,
    address VARCHAR(255) NOT NULL,
    name VARCHAR(255) NOT NULL,
    symbol VARCHAR(20) NOT NULL,
    decimals INTEGER NOT NULL,
    logo_url VARCHAR(255),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'::jsonb,
    CONSTRAINT unique_token_address UNIQUE (chain_family, address)
);

DROP TRIGGER IF EXISTS trg_tokens_updated_at ON tokens;
CREATE TRIGGER trg_tokens_updated_at
BEFORE UPDATE ON tokens
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

CREATE TABLE IF NOT EXISTS token_balances (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    wallet_id VARCHAR(255) NOT NULL REFERENCES wallets(id) ON DELETE CASCADE,
    token_id VARCHAR(255) NOT NULL REFERENCES tokens(id) ON DELETE CASCADE,
    balance DECIMAL(38, 18) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'::jsonb,
    CONSTRAINT unique_token_balance UNIQUE (wallet_id, token_id)
);

DROP TRIGGER IF EXISTS trg_token_balances_updated_at ON token_balances;
CREATE TRIGGER trg_token_balances_updated_at
BEFORE UPDATE ON token_balances
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

CREATE TABLE IF NOT EXISTS orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    wallet_id VARCHAR(255) NOT NULL REFERENCES wallets(id) ON DELETE CASCADE,
    order_type order_type NOT NULL,
    order_side order_side NOT NULL,
    status order_status NOT NULL DEFAULT 'open',
    base_token_id VARCHAR(255) NOT NULL REFERENCES tokens(id) ON DELETE CASCADE,
    quote_token_id VARCHAR(255) NOT NULL REFERENCES tokens(id) ON DELETE CASCADE,
    amount DECIMAL(38, 18) NOT NULL,
    price DECIMAL(38, 18),
    filled_amount DECIMAL(38, 18) NOT NULL DEFAULT 0,
    average_price DECIMAL(38, 18),
    stop_price DECIMAL(38, 18),
    expiration TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'::jsonb
);

DROP TRIGGER IF EXISTS trg_orders_updated_at ON orders;
CREATE TRIGGER trg_orders_updated_at
BEFORE UPDATE ON orders
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

CREATE TABLE IF NOT EXISTS order_fills (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    tx_id VARCHAR(255) REFERENCES transactions(id) ON DELETE SET NULL,
    filled_amount DECIMAL(38, 18) NOT NULL,
    filled_price DECIMAL(38, 18) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'::jsonb
);

-- ============================================================================
-- 7. Lending & Borrowing
-- ============================================================================

CREATE TABLE IF NOT EXISTS lending_pools (
    id VARCHAR(255) PRIMARY KEY,
    token_id VARCHAR(255) NOT NULL REFERENCES tokens(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    status pool_status NOT NULL DEFAULT 'active',
    total_supply DECIMAL(38, 18) NOT NULL DEFAULT 0,
    total_borrow DECIMAL(38, 18) NOT NULL DEFAULT 0,
    supply_apr DECIMAL(38, 18) NOT NULL,
    borrow_apr DECIMAL(38, 18) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'::jsonb
);

DROP TRIGGER IF EXISTS trg_lending_pools_updated_at ON lending_pools;
CREATE TRIGGER trg_lending_pools_updated_at
BEFORE UPDATE ON lending_pools
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

CREATE TABLE IF NOT EXISTS lending_positions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    wallet_id VARCHAR(255) NOT NULL REFERENCES wallets(id) ON DELETE CASCADE,
    pool_id VARCHAR(255) NOT NULL REFERENCES lending_pools(id) ON DELETE CASCADE,
    status position_status NOT NULL DEFAULT 'active',
    supplied_amount DECIMAL(38, 18) NOT NULL DEFAULT 0,
    borrowed_amount DECIMAL(38, 18) NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'::jsonb
);

DROP TRIGGER IF EXISTS trg_lending_positions_updated_at ON lending_positions;
CREATE TRIGGER trg_lending_positions_updated_at
BEFORE UPDATE ON lending_positions
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

CREATE TABLE IF NOT EXISTS lending_actions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    position_id UUID NOT NULL REFERENCES lending_positions(id) ON DELETE CASCADE,
    tx_id VARCHAR(255) REFERENCES transactions(id) ON DELETE SET NULL,
    action lending_action NOT NULL,
    amount DECIMAL(38, 18) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'::jsonb
);

-- ============================================================================
-- 8. Governance & Proposals
-- ============================================================================

CREATE TABLE IF NOT EXISTS proposals (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    title VARCHAR(255) NOT NULL,
    description TEXT NOT NULL,
    proposer_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status proposal_status NOT NULL DEFAULT 'draft',
    start_time TIMESTAMPTZ NOT NULL,
    end_time TIMESTAMPTZ NOT NULL,
    snapshot_block BIGINT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'::jsonb
);

DROP TRIGGER IF EXISTS trg_proposals_updated_at ON proposals;
CREATE TRIGGER trg_proposals_updated_at
BEFORE UPDATE ON proposals
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

CREATE TABLE IF NOT EXISTS votes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    proposal_id UUID NOT NULL REFERENCES proposals(id) ON DELETE CASCADE,
    voter_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    power vote_power NOT NULL,
    reason TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'::jsonb,
    CONSTRAINT unique_vote UNIQUE (proposal_id, voter_id)
);

-- ============================================================================
-- 9. Cross-Chain Bridging
-- ============================================================================

CREATE TABLE IF NOT EXISTS bridge_transactions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    source_tx_id VARCHAR(255) REFERENCES transactions(id) ON DELETE SET NULL,
    destination_tx_id VARCHAR(255) REFERENCES transactions(id) ON DELETE SET NULL,
    source_chain chain_family NOT NULL,
    destination_chain chain_family NOT NULL,
    token_id VARCHAR(255) NOT NULL REFERENCES tokens(id) ON DELETE CASCADE,
    amount DECIMAL(38, 18) NOT NULL,
    status bridge_status NOT NULL DEFAULT 'initiated',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'::jsonb
);

DROP TRIGGER IF EXISTS trg_bridge_transactions_updated_at ON bridge_transactions;
CREATE TRIGGER trg_bridge_transactions_updated_at
BEFORE UPDATE ON bridge_transactions
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- ============================================================================
-- 10. NFT Marketplace
-- ============================================================================

CREATE TABLE IF NOT EXISTS nft_listings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    nft_id VARCHAR(255) NOT NULL REFERENCES nfts(id) ON DELETE CASCADE,
    seller_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    price DECIMAL(38, 18) NOT NULL,
    currency_id VARCHAR(255) NOT NULL REFERENCES tokens(id) ON DELETE CASCADE,
    auction_type auction_type NOT NULL DEFAULT 'fixed_price',
    start_time TIMESTAMPTZ NOT NULL,
    end_time TIMESTAMPTZ NOT NULL,
    reserve_price DECIMAL(38, 18),
    current_bid DECIMAL(38, 18),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'::jsonb
);

DROP TRIGGER IF EXISTS trg_nft_listings_updated_at ON nft_listings;
CREATE TRIGGER trg_nft_listings_updated_at
BEFORE UPDATE ON nft_listings
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

CREATE TABLE IF NOT EXISTS nft_bids (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    listing_id UUID NOT NULL REFERENCES nft_listings(id) ON DELETE CASCADE,
    bidder_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    amount DECIMAL(38, 18) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'::jsonb
);

-- ============================================================================
-- 11. Indexes for Performance Optimization
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_transactions_wallet_id ON transactions(wallet_id);
CREATE INDEX IF NOT EXISTS idx_transactions_status ON transactions(status);
CREATE INDEX IF NOT EXISTS idx_transactions_created_at ON transactions(created_at);

CREATE INDEX IF NOT EXISTS idx_nfts_collection_id ON nfts(collection_id);
CREATE INDEX IF NOT EXISTS idx_nfts_owner_id ON nfts(owner_id);

CREATE INDEX IF NOT EXISTS idx_token_balances_wallet_id ON token_balances(wallet_id);
CREATE INDEX IF NOT EXISTS idx_token_balances_token_id ON token_balances(token_id);

CREATE INDEX IF NOT EXISTS idx_orders_user_id ON orders(user_id);
CREATE INDEX IF NOT EXISTS idx_orders_wallet_id ON orders(wallet_id);
CREATE INDEX IF NOT EXISTS idx_orders_status ON orders(status);
CREATE INDEX IF NOT EXISTS idx_orders_created_at ON orders(created_at);

CREATE INDEX IF NOT EXISTS idx_lending_positions_user_id ON lending_positions(user_id);
CREATE INDEX IF NOT EXISTS idx_lending_positions_wallet_id ON lending_positions(wallet_id);
CREATE INDEX IF NOT EXISTS idx_lending_positions_pool_id ON lending_positions(pool_id);
CREATE INDEX IF NOT EXISTS idx_lending_positions_status ON lending_positions(status);

CREATE INDEX IF NOT EXISTS idx_proposals_status ON proposals(status);
CREATE INDEX IF NOT EXISTS idx_proposals_start_time ON proposals(start_time);
CREATE INDEX IF NOT EXISTS idx_proposals_end_time ON proposals(end_time);

CREATE INDEX IF NOT EXISTS idx_nft_listings_nft_id ON nft_listings(nft_id);
CREATE INDEX IF NOT EXISTS idx_nft_listings_seller_id ON nft_listings(seller_id);
CREATE INDEX IF NOT EXISTS idx_nft_listings_start_time ON nft_listings(start_time);
CREATE INDEX IF NOT EXISTS idx_nft_listings_end_time ON nft_listings(end_time);
