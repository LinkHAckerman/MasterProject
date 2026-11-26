-- ============================================================================
-- MAGNUM OPUS // Multi-Chain DeFi, NFT & Web3 Nexus Platform
-- PostgreSQL Production Schema Definition
-- ============================================================================

-- -----------------------------------------------------------------------------
-- 0. Extensions & Settings
-- -----------------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- -----------------------------------------------------------------------------
-- 1. Enumerations & Custom Domain Types
-- -----------------------------------------------------------------------------
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

-- -----------------------------------------------------------------------------
-- 2. Core Helper Functions
-- -----------------------------------------------------------------------------
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

-- Function to create a new monthly partition for the transactions table.
CREATE OR REPLACE FUNCTION create_monthly_tx_partition(p_year INT, p_month INT)
RETURNS VOID AS $$
DECLARE
    start_date DATE := make_date(p_year, p_month, 1);
    end_date   DATE := (start_date + INTERVAL '1 month')::DATE;
    part_name  TEXT := format('transactions_%s_%02s', p_year, p_month);
    sql        TEXT;
BEGIN
    sql := format(
        'CREATE TABLE IF NOT EXISTS %I PARTITION OF transactions FOR VALUES FROM (%L) TO (%L);',
        part_name,
        start_date,
        end_date
    );
    EXECUTE sql;
END;
$$ LANGUAGE plpgsql;

-- -----------------------------------------------------------------------------
-- 3. Core Users, Authentication & Sessions
-- -----------------------------------------------------------------------------
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

-- -----------------------------------------------------------------------------
-- 4. Wallets & Transactions
-- -----------------------------------------------------------------------------
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
    amount DECIMAL(38,18),
    fee DECIMAL(38,18),
    nonce BIGINT,
    gas_limit BIGINT,
    gas_price DECIMAL(38,18),
    data BYTEA,
    block_number BIGINT,
    block_hash VARCHAR(255),
    transaction_index BIGINT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'::jsonb
) PARTITION BY RANGE (created_at);

DROP TRIGGER IF EXISTS trg_transactions_updated_at ON transactions;
CREATE TRIGGER trg_transactions_updated_at
BEFORE UPDATE ON transactions
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- Example static partitions for the current year (auto‑generated via cron or pgAgent)
CREATE TABLE IF NOT EXISTS transactions_2024_01 PARTITION OF transactions FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');
CREATE TABLE IF NOT EXISTS transactions_2024_02 PARTITION OF transactions FOR VALUES FROM ('2024-02-01') TO ('2024-03-01');
-- Additional partitions will be created by the create_monthly_tx_partition function.

-- Indexes for fast lookup
CREATE INDEX IF NOT EXISTS idx_transactions_wallet_id ON transactions(wallet_id);
CREATE INDEX IF NOT EXISTS idx_transactions_tx_hash ON transactions(tx_hash);
CREATE INDEX IF NOT EXISTS idx_transactions_status ON transactions(status);
CREATE INDEX IF NOT EXISTS idx_transactions_created_at ON transactions(created_at);

-- -----------------------------------------------------------------------------
-- 5. NFTs & Marketplace
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS nft_collections (
    id VARCHAR(255) PRIMARY KEY DEFAULT generate_nft_id(),
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

CREATE TABLE IF NOT EXISTS nft_items (
    id VARCHAR(255) PRIMARY KEY DEFAULT generate_nft_id(),
    collection_id VARCHAR(255) NOT NULL REFERENCES nft_collections(id) ON DELETE CASCADE,
    token_id VARCHAR(255) NOT NULL,
    owner_wallet_id VARCHAR(255) REFERENCES wallets(id) ON DELETE SET NULL,
    rarity nft_rarity NOT NULL DEFAULT 'common',
    metadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

DROP TRIGGER IF EXISTS trg_nft_items_updated_at ON nft_items;
CREATE TRIGGER trg_nft_items_updated_at
BEFORE UPDATE ON nft_items
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

CREATE TABLE IF NOT EXISTS marketplace_listings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    nft_id VARCHAR(255) NOT NULL REFERENCES nft_items(id) ON DELETE CASCADE,
    seller_wallet_id VARCHAR(255) NOT NULL REFERENCES wallets(id) ON DELETE RESTRICT,
    price DECIMAL(38,18) NOT NULL,
    auction_type auction_type NOT NULL DEFAULT 'fixed_price',
    start_time TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    end_time TIMESTAMPTZ,
    status VARCHAR(20) NOT NULL DEFAULT 'active',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'::jsonb,
    CONSTRAINT chk_listing_status CHECK (status IN ('active','filled','cancelled','expired'))
);

DROP TRIGGER IF EXISTS trg_marketplace_listings_updated_at ON marketplace_listings;
CREATE TRIGGER trg_marketplace_listings_updated_at
BEFORE UPDATE ON marketplace_listings
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- -----------------------------------------------------------------------------
-- 6. Order Book (DEX) & Positions
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    wallet_id VARCHAR(255) NOT NULL REFERENCES wallets(id) ON DELETE CASCADE,
    side order_side NOT NULL,
    type order_type NOT NULL,
    amount DECIMAL(38,18) NOT NULL,
    price DECIMAL(38,18),
    status order_status NOT NULL DEFAULT 'open',
    filled_amount DECIMAL(38,18) NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'::jsonb
);

DROP TRIGGER IF EXISTS trg_orders_updated_at ON orders;
CREATE TRIGGER trg_orders_updated_at
BEFORE UPDATE ON orders
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

CREATE INDEX IF NOT EXISTS idx_orders_wallet_id ON orders(wallet_id);
CREATE INDEX IF NOT EXISTS idx_orders_status ON orders(status);

CREATE TABLE IF NOT EXISTS positions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    wallet_id VARCHAR(255) NOT NULL REFERENCES wallets(id) ON DELETE CASCADE,
    side order_side NOT NULL,
    amount DECIMAL(38,18) NOT NULL,
    entry_price DECIMAL(38,18) NOT NULL,
    leverage NUMERIC(5,2) DEFAULT 1,
    status position_status NOT NULL DEFAULT 'active',
    opened_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    closed_at TIMESTAMPTZ,
    metadata JSONB DEFAULT '{}'::jsonb
);

DROP TRIGGER IF EXISTS trg_positions_updated_at ON positions;
CREATE TRIGGER trg_positions_updated_at
BEFORE UPDATE ON positions
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- -----------------------------------------------------------------------------
-- 7. Lending & Borrowing
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS loans (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    borrower_wallet_id VARCHAR(255) NOT NULL REFERENCES wallets(id) ON DELETE RESTRICT,
    lender_wallet_id VARCHAR(255) NOT NULL REFERENCES wallets(id) ON DELETE RESTRICT,
    asset VARCHAR(50) NOT NULL,
    principal DECIMAL(38,18) NOT NULL,
    interest_rate NUMERIC(5,4) NOT NULL,
    accrued_interest DECIMAL(38,18) NOT NULL DEFAULT 0,
    action lending_action NOT NULL,
    status tx_status NOT NULL DEFAULT 'pending',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'::jsonb
);

DROP TRIGGER IF EXISTS trg_loans_updated_at ON loans;
CREATE TRIGGER trg_loans_updated_at
BEFORE UPDATE ON loans
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- -----------------------------------------------------------------------------
-- 8. Governance (DAO) Proposals & Votes
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS proposals (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    proposer_wallet_id VARCHAR(255) NOT NULL REFERENCES wallets(id) ON DELETE RESTRICT,
    title VARCHAR(255) NOT NULL,
    description TEXT NOT NULL,
    status proposal_status NOT NULL DEFAULT 'draft',
    start_time TIMESTAMPTZ,
    end_time TIMESTAMPTZ,
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
    voter_wallet_id VARCHAR(255) NOT NULL REFERENCES wallets(id) ON DELETE RESTRICT,
    power vote_power NOT NULL,
    weight NUMERIC(10,4) NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_votes_proposal_id ON votes(proposal_id);
CREATE INDEX IF NOT EXISTS idx_votes_voter_wallet_id ON votes(voter_wallet_id);

-- -----------------------------------------------------------------------------
-- 9. Cross‑Chain Bridge Transfers
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS bridge_transfers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    source_wallet_id VARCHAR(255) NOT NULL REFERENCES wallets(id) ON DELETE RESTRICT,
    destination_address VARCHAR(255) NOT NULL,
    source_chain chain_family NOT NULL,
    destination_chain chain_family NOT NULL,
    asset VARCHAR(50) NOT NULL,
    amount DECIMAL(38,18) NOT NULL,
    status bridge_status NOT NULL DEFAULT 'initiated',
    tx_hash VARCHAR(255),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'::jsonb
);

DROP TRIGGER IF EXISTS trg_bridge_transfers_updated_at ON bridge_transfers;
CREATE TRIGGER trg_bridge_transfers_updated_at
BEFORE UPDATE ON bridge_transfers
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- -----------------------------------------------------------------------------
-- 10. Liquidity Pools
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS pools (
    id VARCHAR(255) PRIMARY KEY DEFAULT generate_pool_id(),
    name VARCHAR(255) NOT NULL,
    chain_family chain_family NOT NULL,
    status pool_status NOT NULL DEFAULT 'active',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'::jsonb
);

DROP TRIGGER IF EXISTS trg_pools_updated_at ON pools;
CREATE TRIGGER trg_pools_updated_at
BEFORE UPDATE ON pools
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

CREATE TABLE IF NOT EXISTS pool_liquidity (
    pool_id VARCHAR(255) NOT NULL REFERENCES pools(id) ON DELETE CASCADE,
    asset VARCHAR(50) NOT NULL,
    amount DECIMAL(38,18) NOT NULL,
    PRIMARY KEY (pool_id, asset)
);

-- -----------------------------------------------------------------------------
-- 11. Views & Aggregations
-- -----------------------------------------------------------------------------
-- User portfolio view aggregates balances across all wallets (placeholder logic).
CREATE OR REPLACE VIEW user_portfolio AS
SELECT
    u.id AS user_id,
    u.email,
    w.chain_family,
    SUM(COALESCE(t.amount, 0)) FILTER (WHERE t.tx_type = 'transfer' AND t.status = 'confirmed') AS total_received,
    SUM(COALESCE(t.fee, 0)) FILTER (WHERE t.tx_type = 'transfer' AND t.status = 'confirmed') AS total_fees_paid,
    COUNT(t.id) FILTER (WHERE t.status = 'pending') AS pending_tx_count
FROM users u
LEFT JOIN wallets w ON w.user_id = u.id
LEFT JOIN transactions t ON t.wallet_id = w.id
GROUP BY u.id, u.email, w.chain_family;

-- -----------------------------------------------------------------------------
-- 12. Automated Partition Maintenance (example using pg_cron)
-- -----------------------------------------------------------------------------
-- NOTE: The following is a template; actual scheduling requires pg_cron extension.
-- SELECT cron.schedule('create_next_month_partition', '0 0 1 * *', $$
--     SELECT create_monthly_tx_partition(EXTRACT(YEAR FROM CURRENT_DATE)::INT, EXTRACT(MONTH FROM CURRENT_DATE)::INT);
-- $$);

-- End of schema.sql