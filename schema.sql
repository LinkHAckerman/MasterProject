-- PostgreSQL schema for Magnum Opus

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Users
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email VARCHAR(255) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    full_name VARCHAR(255),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    status VARCHAR(20) NOT NULL DEFAULT 'active',
    CONSTRAINT chk_user_status CHECK (status IN ('active','suspended','deleted'))
);

-- Wallets
CREATE TABLE IF NOT EXISTS wallets (
    wallet_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    address VARCHAR(42) NOT NULL UNIQUE,
    network VARCHAR(30) NOT NULL,
    label VARCHAR(100),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_network CHECK (network IN ('Ethereum','Polygon','BinanceSmartChain','Solana','Avalanche'))
);

-- Tokens
CREATE TABLE IF NOT EXISTS tokens (
    token_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    symbol VARCHAR(10) NOT NULL,
    name VARCHAR(100) NOT NULL,
    decimals SMALLINT NOT NULL CHECK (decimals >= 0 AND decimals <= 30),
    contract_address VARCHAR(42) NOT NULL,
    network VARCHAR(30) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (symbol, network),
    CONSTRAINT chk_token_network CHECK (network IN ('Ethereum','Polygon','BinanceSmartChain','Solana','Avalanche'))
);

-- Balances (current snapshot)
CREATE TABLE IF NOT EXISTS balances (
    wallet_id UUID NOT NULL REFERENCES wallets(wallet_id) ON DELETE CASCADE,
    token_id UUID NOT NULL REFERENCES tokens(token_id) ON DELETE CASCADE,
    balance NUMERIC(38,18) NOT NULL DEFAULT 0,
    last_updated TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (wallet_id, token_id)
);

-- Transactions
CREATE TYPE tx_status AS ENUM ('pending','confirmed','failed');

CREATE TABLE IF NOT EXISTS transactions (
    tx_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    wallet_id UUID NOT NULL REFERENCES wallets(wallet_id) ON DELETE CASCADE,
    token_id UUID NOT NULL REFERENCES tokens(token_id) ON DELETE RESTRICT,
    tx_hash VARCHAR(66) NOT NULL UNIQUE,
    block_number BIGINT,
    from_address VARCHAR(42) NOT NULL,
    to_address VARCHAR(42) NOT NULL,
    amount NUMERIC(38,18) NOT NULL,
    fee NUMERIC(38,18) NOT NULL DEFAULT 0,
    gas_price NUMERIC(38,18),
    gas_used BIGINT,
    status tx_status NOT NULL DEFAULT 'pending',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    confirmed_at TIMESTAMPTZ,
    CONSTRAINT chk_amount_positive CHECK (amount >= 0),
    CONSTRAINT chk_fee_nonnegative CHECK (fee >= 0)
);

-- Indexes for fast lookup
CREATE INDEX IF NOT EXISTS idx_transactions_wallet ON transactions(wallet_id);
CREATE INDEX IF NOT EXISTS idx_transactions_token ON transactions(token_id);
CREATE INDEX IF NOT EXISTS idx_transactions_block ON transactions(block_number);
CREATE INDEX IF NOT EXISTS idx_transactions_created ON transactions(created_at);

-- Trigger to auto-update balances on transaction confirmation
CREATE OR REPLACE FUNCTION update_balance_on_tx() RETURNS TRIGGER AS $$
BEGIN
    IF NEW.status = 'confirmed' THEN
        IF NEW.from_address = (SELECT address FROM wallets WHERE wallet_id = NEW.wallet_id) THEN
            UPDATE balances
            SET balance = balance - NEW.amount - NEW.fee,
                last_updated = NOW()
            WHERE wallet_id = NEW.wallet_id AND token_id = NEW.token_id;
        END IF;
        IF NEW.to_address = (SELECT address FROM wallets WHERE wallet_id = NEW.wallet_id) THEN
            INSERT INTO balances (wallet_id, token_id, balance, last_updated)
            VALUES (NEW.wallet_id, NEW.token_id, NEW.amount, NOW())
            ON CONFLICT (wallet_id, token_id) DO UPDATE
            SET balance = balances.balance + EXCLUDED.balance,
                last_updated = NOW();
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_update_balance
AFTER INSERT OR UPDATE ON transactions
FOR EACH ROW EXECUTE FUNCTION update_balance_on_tx();

-- View for user portfolio aggregation
CREATE OR REPLACE VIEW user_portfolio AS
SELECT
    u.id AS user_id,
    u.email,
    w.wallet_id,
    w.address,
    t.symbol,
    t.name,
    b.balance,
    t.decimals,
    (b.balance * COALESCE(p.price_usd,0)) AS value_usd
FROM users u
JOIN wallets w ON w.user_id = u.id
JOIN balances b ON b.wallet_id = w.wallet_id
JOIN tokens t ON t.token_id = b.token_id
LEFT JOIN price_feed p ON p.token_id = t.token_id; -- price_feed is external table

-- Function to insert a new transaction safely
CREATE OR REPLACE FUNCTION insert_transaction(
    p_wallet_id UUID,
    p_token_id UUID,
    p_tx_hash VARCHAR,
    p_block_number BIGINT,
    p_from VARCHAR,
    p_to VARCHAR,
    p_amount NUMERIC,
    p_fee NUMERIC,
    p_gas_price NUMERIC,
    p_gas_used BIGINT,
    p_status tx_status
) RETURNS UUID AS $$
DECLARE
    v_tx_id UUID;
BEGIN
    INSERT INTO transactions (
        wallet_id, token_id, tx_hash, block_number,
        from_address, to_address, amount, fee,
        gas_price, gas_used, status
    ) VALUES (
        p_wallet_id, p_token_id, p_tx_hash, p_block_number,
        p_from, p_to, p_amount, p_fee,
        p_gas_price, p_gas_used, p_status
    ) RETURNING tx_id INTO v_tx_id;

    RETURN v_tx_id;
END;
$$ LANGUAGE plpgsql;