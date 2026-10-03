CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TYPE chain_name AS ENUM ('ethereum', 'polygon', 'avalanche', 'solana', 'binance-smart-chain', 'arbitrum', 'optimism', 'base');
CREATE TYPE tx_type AS ENUM ('transfer', 'swap', 'mint', 'burn', 'stake', 'unstake', 'claim', 'deploy');
CREATE TYPE tx_status AS ENUM ('pending', 'confirmed', 'failed', 'replaced');

CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) UNIQUE NOT NULL,
    username VARCHAR(100) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    preferences JSONB DEFAULT '{"theme":"dark","currency":"USD","language":"en"}'::jsonb,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE chains (
    id SERIAL PRIMARY KEY,
    name chain_name UNIQUE NOT NULL,
    symbol VARCHAR(10) NOT NULL,
    rpc_url TEXT NOT NULL,
    explorer_url TEXT,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE wallets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    chain_id INTEGER REFERENCES chains(id) ON DELETE SET NULL,
    address VARCHAR(255) NOT NULL,
    label VARCHAR(100),
    is_primary BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, chain_id, address)
);

CREATE TABLE tokens (
    id SERIAL PRIMARY KEY,
    chain_id INTEGER REFERENCES chains(id) ON DELETE CASCADE,
    contract_address VARCHAR(255),
    symbol VARCHAR(20) NOT NULL,
    name VARCHAR(100) NOT NULL,
    decimals INTEGER DEFAULT 18,
    is_native BOOLEAN DEFAULT FALSE,
    logo_url TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(chain_id, contract_address)
);

CREATE TABLE portfolio_snapshots (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    wallet_id UUID REFERENCES wallets(id) ON DELETE CASCADE,
    token_id INTEGER REFERENCES tokens(id) ON DELETE SET NULL,
    balance BIGINT NOT NULL DEFAULT 0,
    usd_value NUMERIC(30,2) DEFAULT 0,
    snapshot_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    wallet_id UUID REFERENCES wallets(id) ON DELETE SET NULL,
    token_id INTEGER REFERENCES tokens(id) ON DELETE SET NULL,
    chain_id INTEGER REFERENCES chains(id) ON DELETE SET NULL,
    tx_hash VARCHAR(66) UNIQUE NOT NULL,
    from_address VARCHAR(255),
    to_address VARCHAR(255),
    value BIGINT NOT NULL DEFAULT 0,
    gas_used INTEGER,
    gas_price BIGINT,
    gas_fee_usd NUMERIC(30,2) DEFAULT 0,
    tx_type tx_type NOT NULL,
    tx_status tx_status DEFAULT 'pending',
    block_number BIGINT,
    log_index INTEGER,
    timestamp TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT chk_tx_hash CHECK (tx_hash ~ '^0x[a-fA-F0-9]{64}$')
);

CREATE TABLE nfts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    wallet_id UUID REFERENCES wallets(id) ON DELETE CASCADE,
    chain_id INTEGER REFERENCES chains(id) ON DELETE SET NULL,
    contract_address VARCHAR(255) NOT NULL,
    token_id VARCHAR(255) NOT NULL,
    standard VARCHAR(20) DEFAULT 'erc721',
    metadata_url TEXT,
    rarity_tier VARCHAR(50),
    acquired_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(wallet_id, contract_address, token_id)
);

CREATE TABLE defi_positions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    wallet_id UUID REFERENCES wallets(id) ON DELETE CASCADE,
    protocol_name VARCHAR(100) NOT NULL,
    pool_id VARCHAR(255),
    token_id INTEGER REFERENCES tokens(id) ON DELETE SET NULL,
    amount BIGINT NOT NULL DEFAULT 0,
    usd_value NUMERIC(30,2) DEFAULT 0,
    apr NUMERIC(5,2),
    last_updated TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(wallet_id, protocol_name, pool_id)
);

CREATE INDEX idx_transactions_wallet_ts ON transactions(wallet_id, timestamp DESC);
CREATE INDEX idx_transactions_token_status ON transactions(token_id, tx_status);
CREATE INDEX idx_transactions_txhash ON transactions(tx_hash);
CREATE INDEX idx_portfolio_wallet ON portfolio_snapshots(wallet_id);
CREATE INDEX idx_nfts_wallet ON nfts(wallet_id);
CREATE INDEX idx_defi_wallet ON defi_positions(wallet_id);

CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_users_updated BEFORE UPDATE ON users FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER trg_chains_updated BEFORE UPDATE ON chains FOR EACH ROW EXECUTE FUNCTION update_updated_at();