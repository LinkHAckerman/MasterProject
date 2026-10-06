-- Magnum Opus Database Schema
-- Comprehensive relational model for users, wallets, tokens, transactions, and DeFi data

-- Enable UUID generation (PostgreSQL specific)
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- =============================================================
-- USERS
-- =============================================================
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email VARCHAR(255) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- =============================================================
-- WALLETS
-- =============================================================
CREATE TABLE wallets (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    address VARCHAR(42) NOT NULL UNIQUE, -- 0x-prefixed Ethereum address
    network VARCHAR(32) NOT NULL,        -- e.g., "Ethereum", "Polygon"
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Many‑to‑many relationship between users and wallets
CREATE TABLE user_wallets (
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    wallet_id UUID NOT NULL REFERENCES wallets(id) ON DELETE CASCADE,
    PRIMARY KEY (user_id, wallet_id),
    added_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- =============================================================
-- TOKENS
-- =============================================================
CREATE TABLE tokens (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    symbol VARCHAR(10) NOT NULL,
    name VARCHAR(64) NOT NULL,
    decimals SMALLINT NOT NULL CHECK (decimals >= 0),
    contract_address VARCHAR(42) NOT NULL,
    network VARCHAR(32) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    UNIQUE (contract_address, network)
);

-- Token balances per wallet
CREATE TABLE balances (
    wallet_id UUID NOT NULL REFERENCES wallets(id) ON DELETE CASCADE,
    token_id UUID NOT NULL REFERENCES tokens(id) ON DELETE CASCADE,
    balance NUMERIC(78,0) NOT NULL DEFAULT 0,
    PRIMARY KEY (wallet_id, token_id),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- =============================================================
-- TRANSACTIONS
-- =============================================================
CREATE TABLE transactions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tx_hash VARCHAR(66) NOT NULL UNIQUE, -- 0x-prefixed hash (32 bytes)
    from_wallet UUID REFERENCES wallets(id) ON DELETE SET NULL,
    to_wallet UUID REFERENCES wallets(id) ON DELETE SET NULL,
    token_id UUID REFERENCES tokens(id) ON DELETE SET NULL,
    amount NUMERIC(78,0) NOT NULL,
    gas_price NUMERIC(78,0),
    gas_used NUMERIC(78,0),
    block_number BIGINT,
    status VARCHAR(20) NOT NULL CHECK (status IN ('pending','confirmed','failed')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    indexed_at TIMESTAMP WITH TIME ZONE
);

CREATE INDEX idx_transactions_hash ON transactions(tx_hash);
CREATE INDEX idx_transactions_created ON transactions(created_at);

-- Transaction events (e.g., logs, smart‑contract events)
CREATE TABLE transaction_events (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    transaction_id UUID NOT NULL REFERENCES transactions(id) ON DELETE CASCADE,
    event_type VARCHAR(30) NOT NULL,
    data JSONB NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- =============================================================
-- ORDER BOOK (limit order aggregation)
-- =============================================================
CREATE TABLE order_book (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    pair VARCHAR(20) NOT NULL,               -- e.g., "ETH/USDT"
    side VARCHAR(4) NOT NULL CHECK (side IN ('bid','ask')),
    price NUMERIC(38,18) NOT NULL,
    amount NUMERIC(38,18) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

CREATE INDEX idx_orderbook_pair_side_price ON order_book(pair, side, price DESC);

-- =============================================================
-- NOTIFICATIONS
-- =============================================================
CREATE TABLE notifications (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    type VARCHAR(30) NOT NULL,
    message TEXT NOT NULL,
    is_read BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

CREATE INDEX idx_notifications_user ON notifications(user_id, is_read);

-- =============================================================
-- USER SETTINGS
-- =============================================================
CREATE TABLE settings (
    user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    theme VARCHAR(10) NOT NULL DEFAULT 'dark',
    currency VARCHAR(5) NOT NULL DEFAULT 'USD',
    language VARCHAR(5) NOT NULL DEFAULT 'en',
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- =============================================================
-- TRIGGERS & FUNCTIONS (optional helpers)
-- =============================================================
-- Auto‑update `updated_at` on row modification for `users`
CREATE OR REPLACE FUNCTION trigger_set_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_users_updated
BEFORE UPDATE ON users
FOR EACH ROW EXECUTE FUNCTION trigger_set_timestamp();

-- Auto‑update `balances.updated_at` on balance change
CREATE TRIGGER trg_balances_updated
BEFORE UPDATE ON balances
FOR EACH ROW EXECUTE FUNCTION trigger_set_timestamp();

-- Auto‑update `settings.updated_at` on settings change
CREATE TRIGGER trg_settings_updated
BEFORE UPDATE ON settings
FOR EACH ROW EXECUTE FUNCTION trigger_set_timestamp();

-- =============================================================
-- VIEW: USER PORTFOLIO SUMMARY
-- =============================================================
CREATE OR REPLACE VIEW user_portfolio AS
SELECT
    u.id AS user_id,
    w.id AS wallet_id,
    t.symbol,
    t.name,
    b.balance,
    t.decimals,
    (b.balance / POWER(10, t.decimals))::NUMERIC(38,18) AS token_amount,
    -- price placeholder – to be joined with a price feed view/table
    0::NUMERIC(38,18) AS token_price_usd,
    (b.balance / POWER(10, t.decimals)) * 0::NUMERIC(38,18) AS token_value_usd
FROM users u
JOIN user_wallets uw ON uw.user_id = u.id
JOIN wallets w ON w.id = uw.wallet_id
JOIN balances b ON b.wallet_id = w.id
JOIN tokens t ON t.id = b.token_id;
