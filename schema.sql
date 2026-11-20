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

CREATE OR REPLACE FUNCTION generate_pool_id()
RETURNS VARCHAR AS $$
BEGIN
    RETURN 'POOL-' || UPPER(SUBSTRING(MD5(CAST(NOW() AS TEXT) || CAST(RANDOM() AS TEXT)) FROM 1 FOR 16));
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
-- 5. NFTs & Marketplace
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

CREATE TABLE IF NOT EXISTS nft_listings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    nft_id VARCHAR(255) NOT NULL REFERENCES nfts(id) ON DELETE CASCADE,
    seller_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    auction_type auction_type NOT NULL DEFAULT 'fixed_price',
    price DECIMAL(38, 18) NOT NULL,
    ending_price DECIMAL(38, 18),
    currency VARCHAR(20) NOT NULL DEFAULT 'ETH',
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    starts_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
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
    status VARCHAR(20) NOT NULL DEFAULT 'active',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================================
-- 6. DeFi & Liquidity Pools / Orderbook
-- ============================================================================

CREATE TABLE IF NOT EXISTS tokens (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    chain_family chain_family NOT NULL,
    contract_address VARCHAR(255) NOT NULL,
    symbol VARCHAR(20) NOT NULL,
    name VARCHAR(255) NOT NULL,
    decimals INT NOT NULL DEFAULT 18,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT unique_token_address UNIQUE (chain_family, contract_address)
);

CREATE TABLE IF NOT EXISTS liquidity_pools (
    id VARCHAR(255) PRIMARY KEY DEFAULT generate_pool_id(),
    name VARCHAR(255) NOT NULL,
    token_a_id UUID NOT NULL REFERENCES tokens(id),
    token_b_id UUID NOT NULL REFERENCES tokens(id),
    reserve_a DECIMAL(38, 18) NOT NULL DEFAULT 0,
    reserve_b DECIMAL(38, 18) NOT NULL DEFAULT 0,
    total_lp_tokens DECIMAL(38, 18) NOT NULL DEFAULT 0,
    fee_bps INT NOT NULL DEFAULT 30,
    status pool_status NOT NULL DEFAULT 'active',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

DROP TRIGGER IF EXISTS trg_liquidity_pools_updated_at ON liquidity_pools;
CREATE TRIGGER trg_liquidity_pools_updated_at
BEFORE UPDATE ON liquidity_pools
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

CREATE TABLE IF NOT EXISTS orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    pool_id VARCHAR(255) REFERENCES liquidity_pools(id),
    side order_side NOT NULL,
    type order_type NOT NULL,
    status order_status NOT NULL DEFAULT 'open',
    price DECIMAL(38, 18) NOT NULL,
    amount DECIMAL(38, 18) NOT NULL,
    filled_amount DECIMAL(38, 18) NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

DROP TRIGGER IF EXISTS trg_orders_updated_at ON orders;
CREATE TRIGGER trg_orders_updated_at
BEFORE UPDATE ON orders
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- ============================================================================
-- 7. Lending & Borrowing Protocols
-- ============================================================================

CREATE TABLE IF NOT EXISTS lending_markets (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    token_id UUID NOT NULL REFERENCES tokens(id),
    total_supplied DECIMAL(38, 18) NOT NULL DEFAULT 0,
    total_borrowed DECIMAL(38, 18) NOT NULL DEFAULT 0,
    supply_rate_bps INT NOT NULL DEFAULT 500,
    borrow_rate_bps INT NOT NULL DEFAULT 800,
    collateral_factor DECIMAL(5, 4) NOT NULL DEFAULT 0.75,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS lending_positions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    market_id UUID NOT NULL REFERENCES lending_markets(id),
    supplied_amount DECIMAL(38, 18) NOT NULL DEFAULT 0,
    borrowed_amount DECIMAL(38, 18) NOT NULL DEFAULT 0,
    health_factor DECIMAL(10, 4) NOT NULL DEFAULT 1.0,
    status position_status NOT NULL DEFAULT 'active',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================================
-- 8. Cross-Chain Bridge System
-- ============================================================================

CREATE TABLE IF NOT EXISTS bridge_transfers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    sender_wallet_id VARCHAR(255) NOT NULL REFERENCES wallets(id),
    source_chain chain_family NOT NULL,
    target_chain chain_family NOT NULL,
    recipient_address VARCHAR(255) NOT NULL,
    amount DECIMAL(38, 18) NOT NULL,
    token_symbol VARCHAR(20) NOT NULL,
    status bridge_status NOT NULL DEFAULT 'initiated',
    deposit_tx_hash VARCHAR(255),
    release_tx_hash VARCHAR(255),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================================
-- 9. Governance & DAO System
-- ============================================================================

CREATE TABLE IF NOT EXISTS proposals (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    creator_id UUID NOT NULL REFERENCES users(id),
    title VARCHAR(255) NOT NULL,
    description TEXT NOT NULL,
    status proposal_status NOT NULL DEFAULT 'draft',
    votes_for DECIMAL(38, 18) NOT NULL DEFAULT 0,
    votes_against DECIMAL(38, 18) NOT NULL DEFAULT 0,
    votes_abstain DECIMAL(38, 18) NOT NULL DEFAULT 0,
    start_time TIMESTAMPTZ NOT NULL,
    end_time TIMESTAMPTZ NOT NULL,
    execution_hash VARCHAR(255),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS proposal_votes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    proposal_id UUID NOT NULL REFERENCES proposals(id) ON DELETE CASCADE,
    voter_id UUID NOT NULL REFERENCES users(id),
    vote vote_power NOT NULL,
    weight DECIMAL(38, 18) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT unique_voter_proposal UNIQUE (proposal_id, voter_id)
);

-- ============================================================================
-- 10. Oracle & Audit Logging
-- ============================================================================

CREATE TABLE IF NOT EXISTS oracle_prices (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    symbol VARCHAR(20) NOT NULL,
    price_usd DECIMAL(38, 18) NOT NULL,
    source VARCHAR(100) NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS audit_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    action VARCHAR(255) NOT NULL,
    ip_address VARCHAR(45),
    details JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================================
-- 11. Performance Indexes
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
CREATE INDEX IF NOT EXISTS idx_users_status ON users(status);
CREATE INDEX IF NOT EXISTS idx_wallets_user ON wallets(user_id);
CREATE INDEX IF NOT EXISTS idx_wallets_address ON wallets(address);
CREATE INDEX IF NOT EXISTS idx_tx_wallet ON transactions(wallet_id);
CREATE INDEX IF NOT EXISTS idx_tx_hash ON transactions(tx_hash);
CREATE INDEX IF NOT EXISTS idx_tx_status ON transactions(status);
CREATE INDEX IF NOT EXISTS idx_nfts_owner ON nfts(owner_id);
CREATE INDEX IF NOT EXISTS idx_nfts_collection ON nfts(collection_id);
CREATE INDEX IF NOT EXISTS idx_orders_user ON orders(user_id);
CREATE INDEX IF NOT EXISTS idx_orders_status ON orders(status);
CREATE INDEX IF NOT EXISTS idx_bridge_status ON bridge_transfers(status);
CREATE INDEX IF NOT EXISTS idx_oracle_symbol ON oracle_prices(symbol, updated_at DESC);

-- ============================================================================
-- 12. Analytical Views
-- ============================================================================

CREATE OR REPLACE VIEW view_user_portfolio AS
SELECT 
    u.id AS user_id,
    u.email,
    COUNT(DISTINCT w.id) AS total_wallets,
    COUNT(DISTINCT t.id) AS total_transactions,
    COUNT(DISTINCT n.id) AS total_nfts
FROM users u
LEFT JOIN wallets w ON u.id = w.user_id
LEFT JOIN transactions t ON w.id = t.wallet_id
LEFT JOIN nfts n ON u.id = n.owner_id
GROUP BY u.id, u.email;
