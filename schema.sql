-- Magnum Opus: Unified Blockchain Data Layer Schema
-- Purpose: Core data layer for user wallets, transactions, NFTs, DeFi positions, and audit logging.
-- Compatible with EVM chains, Solana adapters, and multi-chain wallet tracking.
-- Integrates with front-end state (app.js), C++ crypto engine (CryptoEngine.cpp), and microservices (server.go).

-- ============================================
-- EXTENSIONS & UTILITIES
-- ============================================

-- Enable UUID generation (PostgreSQL)
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================
-- USERS & AUTHENTICATION
-- ============================================

CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    wallet_address BYTEA NOT NULL UNIQUE,
    email VARCHAR(255) UNIQUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    last_login TIMESTAMPTZ,
    is_active BOOLEAN DEFAULT TRUE,
    metadata JSONB DEFAULT '{"locale":"en","notifications":true}'
);

-- ============================================
-- MULTI-CHAIN WALLETS
-- ============================================

CREATE TABLE wallets (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    chain_id INTEGER NOT NULL, -- 1=Ethereum Mainnet, 56=BSC, 137=Polygon, 2=Mumbai, 101=Solana devnet, etc.
    address BYTEA NOT NULL,
    label VARCHAR(100), -- e.g., "Trading Wallet","Cold Storage","Margin Account"
    is_primary BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, chain_id, address)
);

-- ============================================
-- BALANCES (DENORMALIZED FOR READ PERFORMANCE)
-- ============================================

CREATE TABLE balances (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    wallet_id UUID REFERENCES wallets(id) ON DELETE CASCADE,
    symbol VARCHAR(10) NOT NULL, -- 'ETH','USDT','BTC','SOL','USDC', etc.
    amount NUMERIC(78, 18) NOT NULL DEFAULT 0,
    usd_value NUMERIC(30, 2) DEFAULT 0,
    last_updated TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(wallet_id, symbol)
);

-- ============================================
-- TRANSACTION HISTORY (ON-CHAIN + INTERNAL)
-- ============================================

CREATE TABLE transactions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    wallet_id UUID REFERENCES wallets(id) ON DELETE CASCADE,
    tx_hash BYTEA NOT NULL UNIQUE,
    chain_id INTEGER NOT NULL,
    from_address BYTEA,
    to_address BYTEA,
    value NUMERIC(78, 18) NOT NULL DEFAULT 0,
    gas_used INTEGER,
    gas_price NUMERIC(78, 18),
    fee_usd NUMERIC(30, 2) DEFAULT 0,
    status VARCHAR(50) DEFAULT 'pending', -- pending, confirmed, failed, reverted
    block_number BIGINT,
    timestamp TIMESTAMPTZ DEFAULT NOW(),
    type VARCHAR(20) NOT NULL, -- 'transfer','swap','mint','burn','staking','claim','deposit','withdraw'
    metadata JSONB DEFAULT '{"direction":"out","symbol":"ETH"}'
);

-- Core indexes for dashboard queries
CREATE INDEX idx_transactions_wallet_chain ON transactions(wallet_id, chain_id DESC);
CREATE INDEX idx_transactions_hash ON transactions USING hash (tx_hash);
CREATE INDEX idx_transactions_timestamp ON transactions(timestamp DESC);
CREATE INDEX idx_transactions_type ON transactions(type);
CREATE INDEX idx_balances_wallet ON balances(wallet_id);

-- ============================================
-- NFTs & COLLECTIONS
-- ============================================

CREATE TABLE nfts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    wallet_id UUID REFERENCES wallets(id) ON DELETE CASCADE,
    token_id VARCHAR(100) NOT NULL,
    contract_address BYTEA NOT NULL,
    name VARCHAR(255),
    symbol VARCHAR(20),
    image_url TEXT,
    metadata JSONB DEFAULT '{}',
    rarity_tier VARCHAR(20), -- Common, Rare, Epic, Legendary
    UNIQUE(wallet_id, token_id, contract_address)
);

CREATE INDEX idx_nfts_wallet ON nfts(wallet_id);
CREATE INDEX idx_nfts_contract ON nfts(contract_address);

-- ============================================
-- DeFi POSITIONS & LIQUIDITY
-- ============================================

CREATE TABLE positions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    wallet_id UUID REFERENCES wallets(id) ON DELETE CASCADE,
    protocol VARCHAR(100) NOT NULL, -- 'UniswapV3','Aave','Compound','Raydium','Orca','Curve'
    pool_id VARCHAR(100), -- protocol-specific pool identifier
    chain_id INTEGER NOT NULL,
    token_in VARCHAR(10), -- e.g., 'ETH','USDC','SOL'
    token_out VARCHAR(10),
    amount_in NUMERIC(78, 18) DEFAULT 0,
    amount_out NUMERIC(78, 18) DEFAULT 0,
    apy NUMERIC(10, 4) DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(wallet_id, protocol, pool_id)
);

CREATE INDEX idx_positions_wallet ON positions(wallet_id);
CREATE INDEX idx_positions_protocol ON positions(protocol);

-- ============================================
-- AUDIT LOG (SECURITY / COMPLIANCE)
-- ============================================

CREATE TABLE audit_log (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    action VARCHAR(100) NOT NULL, -- 'WALLET_CONNECT','SWAP_EXECUTED','WITHDRAWAL_INITIATED','POSITION_OPEN','POSITION_CLOSED'
    details JSONB DEFAULT '{}',
    ip_inet INET,
    user_agent TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_audit_user_time ON audit_log(user_id, created_at DESC);
CREATE INDEX idx_audit_action ON audit_log(action);

-- ============================================
-- VIEWS FOR DASHBOARD QUERIES
-- ============================================

-- Recent activity per user
CREATE OR REPLACE VIEW user_activity AS
SELECT
    u.id AS user_id,
    u.wallet_address,
    t.timestamp,
    t.type,
    t.value,
    t.status,
    b.symbol,
    b.usd_value
FROM users u
JOIN wallets w ON u.id = w.user_id
JOIN transactions t ON w.id = t.wallet_id
JOIN balances b ON w.id = b.wallet_id AND t.symbol = b.symbol
WHERE t.status = 'confirmed'
ORDER BY t.timestamp DESC;

-- Portfolio summary per wallet
CREATE OR REPLACE VIEW wallet_portfolio AS
SELECT
    w.id AS wallet_id,
    w.chain_id,
    b.symbol,
    b.amount,
    b.usd_value,
    COALESCE(SUM(t.fee_usd) FILTER (WHERE t.type = 'swap'), 0) AS total_fees_usd,
    COUNT(t.id) AS tx_count
FROM wallets w
JOIN balances b ON w.id = b.wallet_id
LEFT JOIN transactions t ON w.id = t.wallet_id AND t.status = 'confirmed'
GROUP BY w.id, w.chain_id, b.symbol, b.amount, b.usd_value;

-- ============================================
-- GRANT BASE PERMISSIONS (ADJUST FOR YOUR ENVIRONMENT)
-- ============================================

GRANT ALL ON ALL TABLES TO magnopus_app;
GRANT USAGE, SELECT ON ALL SEQUENCES TO magnopus_app;
