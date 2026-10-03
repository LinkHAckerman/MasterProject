-- Magnum Opus Database Schema
-- PostgreSQL

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Users
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email VARCHAR(255) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    full_name VARCHAR(255),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    status VARCHAR(20) NOT NULL DEFAULT 'active'
);

-- Wallets
CREATE TABLE wallets (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    address VARCHAR(42) NOT NULL UNIQUE,
    network VARCHAR(32) NOT NULL,
    label VARCHAR(64),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Tokens (ERC20, BEP20, etc.)
CREATE TABLE tokens (
    id SERIAL PRIMARY KEY,
    symbol VARCHAR(10) NOT NULL,
    name VARCHAR(64) NOT NULL,
    decimals SMALLINT NOT NULL,
    contract_address VARCHAR(42) NOT NULL,
    network VARCHAR(32) NOT NULL,
    UNIQUE (contract_address, network)
);

-- Wallet token balances
CREATE TABLE wallet_balances (
    wallet_id UUID NOT NULL REFERENCES wallets(id) ON DELETE CASCADE,
    token_id INT NOT NULL REFERENCES tokens(id) ON DELETE CASCADE,
    balance NUMERIC(78,0) NOT NULL DEFAULT 0,
    PRIMARY KEY (wallet_id, token_id)
);

-- Transactions (on‑chain and internal)
CREATE TABLE transactions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    wallet_id UUID NOT NULL REFERENCES wallets(id) ON DELETE CASCADE,
    tx_hash VARCHAR(66) NOT NULL UNIQUE,
    block_number BIGINT,
    from_address VARCHAR(42) NOT NULL,
    to_address VARCHAR(42) NOT NULL,
    token_id INT REFERENCES tokens(id),
    amount NUMERIC(78,0) NOT NULL,
    gas_used BIGINT,
    gas_price NUMERIC(78,0),
    status VARCHAR(20) NOT NULL DEFAULT 'pending',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    confirmed_at TIMESTAMPTZ
);

-- NFT metadata
CREATE TABLE nfts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    contract_address VARCHAR(42) NOT NULL,
    token_id NUMERIC(78,0) NOT NULL,
    owner_wallet_id UUID NOT NULL REFERENCES wallets(id) ON DELETE CASCADE,
    metadata_uri TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (contract_address, token_id)
);

-- Indexes for fast look‑ups
CREATE INDEX idx_wallet_balances_wallet ON wallet_balances(wallet_id);
CREATE INDEX idx_wallet_balances_token ON wallet_balances(token_id);
CREATE INDEX idx_transactions_wallet ON transactions(wallet_id);
CREATE INDEX idx_transactions_status ON transactions(status);
CREATE INDEX idx_nfts_owner ON nfts(owner_wallet_id);

-- Trigger to keep wallet_balances in sync with confirmed transactions
CREATE OR REPLACE FUNCTION update_wallet_balance() RETURNS TRIGGER AS $$
DECLARE
    delta NUMERIC(78,0);
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.status = 'confirmed' THEN
            delta := NEW.amount;
            IF NEW.from_address = (SELECT address FROM wallets WHERE id = NEW.wallet_id) THEN
                delta := -delta;
            END IF;
            INSERT INTO wallet_balances (wallet_id, token_id, balance)
            VALUES (NEW.wallet_id, NEW.token_id, GREATEST(delta,0))
            ON CONFLICT (wallet_id, token_id) DO UPDATE
            SET balance = GREATEST(wallet_balances.balance + delta, 0);
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_update_balance
AFTER INSERT ON transactions
FOR EACH ROW EXECUTE FUNCTION update_wallet_balance();

-- Auditing table for changes (optional)
CREATE TABLE audit_log (
    id BIGSERIAL PRIMARY KEY,
    table_name VARCHAR(64) NOT NULL,
    operation VARCHAR(10) NOT NULL,
    record_id UUID NOT NULL,
    changed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    changed_by UUID REFERENCES users(id),
    details JSONB
);

-- Function to log audit entries
CREATE OR REPLACE FUNCTION log_audit() RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO audit_log (table_name, operation, record_id, changed_by, details)
    VALUES (TG_TABLE_NAME, TG_OP, NEW.id, current_setting('app.current_user')::UUID, row_to_json(NEW));
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Example: attach audit to users table
CREATE TRIGGER trg_audit_users
AFTER INSERT OR UPDATE OR DELETE ON users
FOR EACH ROW EXECUTE FUNCTION log_audit();

-- End of schema