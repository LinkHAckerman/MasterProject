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

-- Partition transactions by month for performance
CREATE TABLE IF NOT EXISTS transactions_2024_01 PARTITION OF transactions FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');
CREATE TABLE IF NOT EXISTS transactions_2024_02 PARTITION OF transactions FOR VALUES FROM ('2024-02-01') TO ('2024-03-01');
-- Additional partitions can be created automatically via a scheduled job.

-- Indexes for fast lookup
CREATE INDEX IF NOT EXISTS idx_transactions_wallet_id ON transactions(wallet_id);
CREATE INDEX IF NOT EXISTS idx_transactions_tx_hash ON transactions(tx_hash);
CREATE INDEX IF NOT EXISTS idx_transactions_status ON transactions(status);

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
    metadata JSONB DEFAULT '{}'::jsonb
);

DROP TRIGGER IF EXISTS trg_nfts_updated_at ON nfts;
CREATE TRIGGER trg_nfts_updated_at
BEFORE UPDATE ON nfts
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

CREATE INDEX IF NOT EXISTS idx_nfts_collection_id ON nfts(collection_id);
CREATE INDEX IF NOT EXISTS idx_nfts_owner_id ON nfts(owner_id);
CREATE INDEX IF NOT EXISTS idx_nfts_rarity ON nfts(rarity);

-- ============================================================================
-- 6. Order Book & Trading Engine
-- ============================================================================

CREATE TABLE IF NOT EXISTS orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    wallet_id VARCHAR(255) NOT NULL REFERENCES wallets(id) ON DELETE CASCADE,
    side order_side NOT NULL,
    type order_type NOT NULL,
    status order_status NOT NULL DEFAULT 'open',
    base_asset VARCHAR(20) NOT NULL,
    quote_asset VARCHAR(20) NOT NULL,
    price NUMERIC(38,18),
    amount NUMERIC(38,18) NOT NULL,
    filled_amount NUMERIC(38,18) NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'::jsonb
);

DROP TRIGGER IF EXISTS trg_orders_updated_at ON orders;
CREATE TRIGGER trg_orders_updated_at
BEFORE UPDATE ON orders
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

CREATE INDEX IF NOT EXISTS idx_orders_user_id ON orders(user_id);
CREATE INDEX IF NOT EXISTS idx_orders_wallet_id ON orders(wallet_id);
CREATE INDEX IF NOT EXISTS idx_orders_status ON orders(status);

CREATE TABLE IF NOT EXISTS order_fills (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    fill_price NUMERIC(38,18) NOT NULL,
    fill_amount NUMERIC(38,18) NOT NULL,
    fee NUMERIC(38,18) NOT NULL DEFAULT 0,
    filled_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS idx_order_fills_order_id ON order_fills(order_id);

-- ============================================================================
-- 7. Lending & Positions
-- ============================================================================

CREATE TABLE IF NOT EXISTS positions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    wallet_id VARCHAR(255) NOT NULL REFERENCES wallets(id) ON DELETE CASCADE,
    asset VARCHAR(20) NOT NULL,
    amount NUMERIC(38,18) NOT NULL,
    collateral NUMERIC(38,18) NOT NULL,
    status position_status NOT NULL DEFAULT 'active',
    opened_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    closed_at TIMESTAMPTZ,
    metadata JSONB DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS idx_positions_user_id ON positions(user_id);
CREATE INDEX IF NOT EXISTS idx_positions_status ON positions(status);

-- ============================================================================
-- 8. Liquidity Pools
-- ============================================================================

CREATE TABLE IF NOT EXISTS liquidity_pools (
    id VARCHAR(255) PRIMARY KEY DEFAULT generate_pool_id(),
    name VARCHAR(255) NOT NULL,
    status pool_status NOT NULL DEFAULT 'active',
    chain_family chain_family NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'::jsonb
);

DROP TRIGGER IF EXISTS trg_liquidity_pools_updated_at ON liquidity_pools;
CREATE TRIGGER trg_liquidity_pools_updated_at
BEFORE UPDATE ON liquidity_pools
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

CREATE TABLE IF NOT EXISTS pool_reserves (
    pool_id VARCHAR(255) NOT NULL REFERENCES liquidity_pools(id) ON DELETE CASCADE,
    asset VARCHAR(20) NOT NULL,
    reserve_amount NUMERIC(38,18) NOT NULL,
    PRIMARY KEY (pool_id, asset)
);

CREATE INDEX IF NOT EXISTS idx_pool_reserves_asset ON pool_reserves(asset);

-- ============================================================================
-- 9. Governance Proposals
-- ============================================================================

CREATE TABLE IF NOT EXISTS proposals (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    creator_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title VARCHAR(255) NOT NULL,
    description TEXT,
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

CREATE TABLE IF NOT EXISTS proposal_votes (
    proposal_id UUID NOT NULL REFERENCES proposals(id) ON DELETE CASCADE,
    voter_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    vote_power vote_power NOT NULL,
    voted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (proposal_id, voter_user_id)
);

-- ============================================================================
-- 10. Cross‑Chain Bridge Transfers
-- ============================================================================

CREATE TABLE IF NOT EXISTS bridge_transfers (
    id VARCHAR(255) PRIMARY KEY DEFAULT generate_tx_id(),
    source_chain chain_family NOT NULL,
    destination_chain chain_family NOT NULL,
    asset VARCHAR(20) NOT NULL,
    amount NUMERIC(38,18) NOT NULL,
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

CREATE INDEX IF NOT EXISTS idx_bridge_transfers_status ON bridge_transfers(status);

-- ============================================================================
-- 11. Audit Log (append‑only)
-- ============================================================================

CREATE TABLE IF NOT EXISTS audit_log (
    id BIGSERIAL PRIMARY KEY,
    table_name VARCHAR(255) NOT NULL,
    operation VARCHAR(10) NOT NULL CHECK (operation IN ('INSERT','UPDATE','DELETE')),
    changed_data JSONB NOT NULL,
    performed_by UUID REFERENCES users(id),
    performed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Generic trigger to capture changes for any table that opts‑in via the
-- "audit_enabled" comment. Example usage:
-- COMMENT ON TABLE users IS 'audit_enabled';

CREATE OR REPLACE FUNCTION audit_trigger_func()
RETURNS TRIGGER AS $$
DECLARE
    changed JSONB;
BEGIN
    IF TG_OP = 'INSERT' THEN
        changed := to_jsonb(NEW);
    ELSIF TG_OP = 'UPDATE' THEN
        changed := jsonb_build_object('old', to_jsonb(OLD), 'new', to_jsonb(NEW));
    ELSIF TG_OP = 'DELETE' THEN
        changed := to_jsonb(OLD);
    END IF;
    INSERT INTO audit_log(table_name, operation, changed_data, performed_by)
    VALUES (TG_TABLE_NAME, TG_OP, changed, current_setting('app.current_user_id', true)::uuid);
    RETURN NULL; -- AFTER trigger, result ignored
END;
$$ LANGUAGE plpgsql;

-- Enable auditing on core tables
COMMENT ON TABLE users IS 'audit_enabled';
COMMENT ON TABLE wallets IS 'audit_enabled';
COMMENT ON TABLE transactions IS 'audit_enabled';
COMMENT ON TABLE nfts IS 'audit_enabled';
COMMENT ON TABLE orders IS 'audit_enabled';
COMMENT ON TABLE proposals IS 'audit_enabled';

-- Attach audit triggers (AFTER) to tables with the comment
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN SELECT c.oid, c.relname FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE c.relkind = 'r' AND obj_description(c.oid, 'pg_class') = 'audit_enabled'
    LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS audit_trigger ON %I', r.relname);
        EXECUTE format('CREATE TRIGGER audit_trigger AFTER INSERT OR UPDATE OR DELETE ON %I FOR EACH ROW EXECUTE FUNCTION audit_trigger_func()', r.relname);
    END LOOP;
END $$;

-- ============================================================================
-- 12. Views & Helper Functions
-- ============================================================================

-- View: aggregate wallet balances per user (assumes balance stored in metadata JSONB as {"balance": "123.45"})
CREATE OR REPLACE VIEW user_wallet_balances AS
SELECT
    u.id AS user_id,
    u.email,
    SUM((w.metadata->>'balance')::numeric) AS total_balance
FROM users u
JOIN wallets w ON w.user_id = u.id
GROUP BY u.id, u.email;

-- Materialized view: top 10 NFTs by number of transfers (requires a transfer log table – placeholder for future implementation)
-- CREATE MATERIALIZED VIEW top_nfts_by_volume AS
-- SELECT n.id, n.name, COUNT(t.id) AS transfer_count
-- FROM nfts n
-- JOIN nft_transfers t ON t.nft_id = n.id
-- GROUP BY n.id, n.name
-- ORDER BY transfer_count DESC
-- LIMIT 10;

-- Helper function to calculate a user's total on‑chain asset value across all wallets.
CREATE OR REPLACE FUNCTION calculate_user_total_value(p_user_id UUID)
RETURNS NUMERIC AS $$
DECLARE
    total NUMERIC := 0;
    rec RECORD;
BEGIN
    FOR rec IN SELECT (metadata->>'balance')::numeric AS bal FROM wallets WHERE user_id = p_user_id LOOP
        total := total + COALESCE(rec.bal, 0);
    END LOOP;
    RETURN total;
END;
$$ LANGUAGE plpgsql STABLE;

-- ============================================================================
-- 13. Sample Data (development only)
-- ============================================================================

INSERT INTO users (email, password_hash, full_name, is_verified)
VALUES ('alice@example.com', crypt('password123', gen_salt('bf')), 'Alice Wonderland', TRUE)
ON CONFLICT DO NOTHING;

INSERT INTO users (email, password_hash, full_name, is_verified)
VALUES ('bob@example.com', crypt('securepass', gen_salt('bf')), 'Bob Builder', TRUE)
ON CONFLICT DO NOTHING;

INSERT INTO wallets (user_id, chain_family, address, is_default, metadata)
SELECT id, 'evm', '0x' || substr(md5(random()::text), 1, 40), TRUE, jsonb_build_object('balance', '1000')
FROM users WHERE email = 'alice@example.com'
ON CONFLICT DO NOTHING;

INSERT INTO nft_collections (id, name, symbol)
VALUES ('COLL-001', 'Magnum Opus Art', 'MOA')
ON CONFLICT DO NOTHING;

INSERT INTO nfts (collection_id, token_id, owner_id, rarity, name, metadata)
SELECT 'COLL-001', '1', id, 'legendary', 'Genesis Opus', jsonb_build_object('attributes', jsonb_build_array(jsonb_build_object('trait_type','Power','value','Infinity')))
FROM users WHERE email = 'alice@example.com'
ON CONFLICT DO NOTHING;

-- End of schema.sql