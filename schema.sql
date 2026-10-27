-- PostgreSQL schema for Magnum Opus: Enhanced with support for NFTs, DeFi contracts, and multi-chain asset tracking
-- Updated for full-stack Web3 ecosystem integration

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Enum for transaction status
CREATE TYPE tx_status AS ENUM ('pending','confirmed','failed','reverted');

-- Helper trigger function to auto‑update the updated_at timestamp
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
    CONSTRAINT chk_user_status CHECK (status IN ('active','suspended','deleted','verified'))
);

CREATE TRIGGER trg_users_updated_at
BEFORE UPDATE ON users
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- Wallet Hierarchy and Network Support
CREATE TABLE IF NOT EXISTS wallets (
    wallet_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    address VARCHAR(42) NOT NULL UNIQUE,
    network VARCHAR(30) NOT NULL,
    label VARCHAR(100),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB,
    CONSTRAINT chk_network CHECK (network IN ('Ethereum','Polygon','BinanceSmartChain','Solana','Avalanche','PolygonZK','Arbitrum','Optimism','Base','Mantle'))
);

CREATE TRIGGER trg_wallets_updated_at
BEFORE UPDATE ON wallets
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- Token and NFT Classification
CREATE TABLE IF NOT EXISTS assets (
    asset_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    symbol VARCHAR(10) NOT NULL,
    name VARCHAR(100) NOT NULL,
    decimals SMALLINT NOT NULL CHECK (decimals BETWEEN 0 AND 30),
    contract_address VARCHAR(42),
    network VARCHAR(30) NOT NULL,
    is_nft BOOLEAN NOT NULL DEFAULT FALSE,
    is_token BOOLEAN NOT NULL DEFAULT TRUE,
    token_type VARCHAR(50) CHECK (token_type IN ('ERC20','ERC721','ERC1155','BEP20','BEP2','BSCToken','SolanaSPL','AVAXToken','PolygonToken','WrappedToken')),
    total_supply NUMERIC(38,18),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (symbol, network),
    CONSTRAINT chk_token_network CHECK (network IN ('Ethereum','Polygon','BinanceSmartChain','Solana','Avalanche','PolygonZK','Arbitrum','Optimism','Base','Mantle'))
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
    image_url VARCHAR(255),
    attributes JSONB,
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
    owner_address VARCHAR(42) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (token_id, owner_address)
);

CREATE TRIGGER trg_nft_tokens_updated_at
BEFORE UPDATE ON nft_tokens
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- Balances (current snapshot)
CREATE TABLE IF NOT EXISTS balances (
    wallet_id UUID NOT NULL REFERENCES wallets(wallet_id) ON DELETE CASCADE,
    asset_id UUID NOT NULL REFERENCES assets(asset_id) ON DELETE RESTRICT,
    balance NUMERIC(38,18) NOT NULL DEFAULT 0,
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
    from_address VARCHAR(42),
    to_address VARCHAR(42),
    amount NUMERIC(38,18) NOT NULL,
    fee NUMERIC(38,18) DEFAULT 0,
    status tx_status NOT NULL DEFAULT 'pending',
    gas_price NUMERIC(38,18),
    gas_used BIGINT,
    nonce BIGINT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB
);

CREATE TRIGGER trg_transactions_updated_at
BEFORE UPDATE ON transactions
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- Indexes for fast lookup
CREATE INDEX idx_transactions_wallet_id ON transactions(wallet_id);
CREATE INDEX idx_transactions_asset_id ON transactions(asset_id);
CREATE INDEX idx_transactions_status ON transactions(status);
CREATE INDEX idx_balances_wallet_id ON balances(wallet_id);
CREATE INDEX idx_balances_asset_id ON balances(asset_id);

-- Historical transaction archive (partitioned by month)
CREATE TABLE IF NOT EXISTS transaction_history (
    tx_id UUID NOT NULL,
    wallet_id UUID NOT NULL,
    asset_id UUID NOT NULL,
    tx_hash VARCHAR(66) NOT NULL,
    block_number BIGINT,
    from_address VARCHAR(42),
    to_address VARCHAR(42),
    amount NUMERIC(38,18) NOT NULL,
    fee NUMERIC(38,18) DEFAULT 0,
    status tx_status NOT NULL,
    gas_price NUMERIC(38,18),
    gas_used BIGINT,
    nonce BIGINT,
    created_at TIMESTAMPTZ NOT NULL,
    metadata JSONB,
    PRIMARY KEY (tx_id, created_at)
) PARTITION BY RANGE (created_at);

-- Example partition for current month (to be refreshed via a scheduled job)
DO $$
DECLARE
    start_date DATE := date_trunc('month', now());
    end_date DATE := (date_trunc('month', now()) + interval '1 month')::date;
    part_name TEXT := 'transaction_history_' || to_char(start_date, 'YYYYMM');
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_class WHERE relname = part_name) THEN
        EXECUTE format('CREATE TABLE IF NOT EXISTS %I PARTITION OF transaction_history FOR VALUES FROM (%L) TO (%L);',
            part_name, start_date, end_date);
    END IF;
END $$;

-- Auditing table for critical changes
CREATE TABLE IF NOT EXISTS audit_log (
    audit_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    table_name VARCHAR(50) NOT NULL,
    record_id UUID NOT NULL,
    operation VARCHAR(10) NOT NULL CHECK (operation IN ('INSERT','UPDATE','DELETE')),
    changed_by UUID REFERENCES users(id),
    changed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    old_data JSONB,
    new_data JSONB
);

-- Function to log changes (generic trigger)
CREATE OR REPLACE FUNCTION log_audit()
RETURNS TRIGGER AS $$
DECLARE
    rec_id UUID;
BEGIN
    IF TG_OP = 'INSERT' THEN
        rec_id := NEW.id;
        INSERT INTO audit_log(table_name, record_id, operation, changed_by, new_data)
        VALUES (TG_TABLE_NAME, rec_id, TG_OP, current_setting('app.current_user')::uuid, to_jsonb(NEW));
        RETURN NEW;
    ELSIF TG_OP = 'UPDATE' THEN
        rec_id := NEW.id;
        INSERT INTO audit_log(table_name, record_id, operation, changed_by, old_data, new_data)
        VALUES (TG_TABLE_NAME, rec_id, TG_OP, current_setting('app.current_user')::uuid, to_jsonb(OLD), to_jsonb(NEW));
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        rec_id := OLD.id;
        INSERT INTO audit_log(table_name, record_id, operation, changed_by, old_data)
        VALUES (TG_TABLE_NAME, rec_id, TG_OP, current_setting('app.current_user')::uuid, to_jsonb(OLD));
        RETURN OLD;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Attach audit trigger to critical tables
DO $$
DECLARE
    tbl TEXT;
BEGIN
    FOR tbl IN SELECT tablename FROM pg_tables WHERE schemaname = 'public' AND tablename IN ('users','wallets','assets','transactions') LOOP
        EXECUTE format('CREATE TRIGGER trg_audit_%I AFTER INSERT OR UPDATE OR DELETE ON %I FOR EACH ROW EXECUTE FUNCTION log_audit();', tbl, tbl);
    END LOOP;
END $$;
