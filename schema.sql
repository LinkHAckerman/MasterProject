-- schema.sql — Data Layer for Magnum Opus: All-in-One Crypto, NFTs, Web3 & DeFi Platform
-- Designed for PostgreSQL 15+ with extensibility for multi-ecosystem support (Ethereum, Solana, BNB Chain, etc.)

-- ============================================================
-- EXTENSIONS & SETTINGS
-- ============================================================
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
SET timezone = 'UTC';

-- ============================================================
-- CORE ENTITIES
-- ============================================================

CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    wallet_address BYTEA NOT NULL UNIQUE,
    username VARCHAR(64) UNIQUE,
    email VARCHAR(128) UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_login TIMESTAMPTZ,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    metadata JSONB DEFAULT '{}'::jsonb
);

CREATE TABLE IF NOT EXISTS wallets (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    chain_id INTEGER NOT NULL,
    network_name VARCHAR(32) NOT NULL,
    address BYTEA NOT NULL,
    derivation_path VARCHAR(128),
    label VARCHAR(32),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(user_id, chain_id, address)
);

-- ============================================================
-- BALANCES & ASSET POSITIONS
-- ============================================================

CREATE TABLE IF NOT EXISTS balances (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    wallet_id UUID REFERENCES wallets(id) ON DELETE CASCADE,
    symbol VARCHAR(16) NOT NULL,
    raw_amount NUMERIC(78, 0) NOT NULL,
    display_amount NUMERIC(30, 18) NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(wallet_id, symbol)
);

-- ============================================================
-- TRANSACTION HISTORY
-- ============================================================

CREATE TABLE IF NOT EXISTS transactions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    wallet_id UUID REFERENCES wallets(id) ON DELETE SET NULL,
    tx_hash BYTEA UNIQUE NOT NULL,
    from_address BYTEA,
    to_address BYTEA,
    value NUMERIC(78, 0) NOT NULL DEFAULT 0,
    gas_used INTEGER,
    gas_price_gwei NUMERIC(18, 8),
    status VARCHAR(16) NOT NULL CHECK (status IN ('pending', 'confirmed', 'failed', 'replaced')),
    block_number BIGINT,
    timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    type VARCHAR(32) NOT NULL CHECK (type IN ('transfer', 'swap', 'stake', 'unstake', 'mint', 'burn', 'governance')),
    extra_data JSONB DEFAULT '{}'::jsonb,
    INDEX idx_transactions_wallet (wallet_id, timestamp DESC),
    INDEX idx_transactions_status (status),
    INDEX idx_transactions_type (type)
);

-- ============================================================
-- NFTs & COLLECTIBLES
-- ============================================================

CREATE TABLE IF NOT EXISTS nfts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    wallet_id UUID REFERENCES wallets(id) ON DELETE CASCADE,
    contract_address BYTEA NOT NULL,
    token_id VARCHAR(128) NOT NULL,
    name VARCHAR(128),
    symbol VARCHAR(16),
    token_uri TEXT,
    metadata_cid CIDR,
    rarity_tier VARCHAR(16),
    chain_id INTEGER NOT NULL,
    acquired_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(wallet_id, contract_address, token_id)
);

CREATE INDEX IF NOT EXISTS idx_nfts_contract ON nfts (contract_address, chain_id);
CREATE INDEX IF NOT EXISTS idx_nfts_wallet ON nfts (wallet_id);

-- ============================================================
-- STAKING & YIELD POSITIONS
-- ============================================================

CREATE TABLE IF NOT EXISTS staking_positions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    wallet_id UUID REFERENCES wallets(id) ON DELETE CASCADE,
    contract_address BYTEA NOT NULL,
    token_symbol VARCHAR(16) NOT NULL,
    amount NUMERIC(78, 0) NOT NULL,
    staked_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    rewards_earned NUMERIC(78, 0) NOT NULL DEFAULT 0,
    unlocked_at TIMESTAMPTZ,
    status VARCHAR(16) NOT NULL CHECK (status IN ('active', 'unbonding', 'withdrawn')),
    UNIQUE(wallet_id, contract_address)
);

CREATE INDEX IF NOT EXISTS idx_staking_positions_wallet ON staking_positions (wallet_id);

-- ============================================================
-- GOVERNANCE & VOTING
-- ============================================================

CREATE TABLE IF NOT EXISTS governance_proposals (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    title VARCHAR(256) NOT NULL,
    description TEXT,
    proposer_id UUID REFERENCES users(id) ON DELETE SET NULL,
    proposal_type VARCHAR(32) NOT NULL CHECK (proposal_type IN ('parameter_change', 'treasury_allocation', 'contract_upgrade', 'network_upgrade')),
    status VARCHAR(16) NOT NULL CHECK (status IN ('active', 'passed', 'rejected', 'executed', 'cancelled')),
    voting_end TIMESTAMPTZ NOT NULL,
    for_votes NUMERIC(78, 0) NOT NULL DEFAULT 0,
    against_votes NUMERIC(78, 0) NOT NULL DEFAULT 0,
    quorum_requirement NUMERIC(78, 0) NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    executed_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_proposals_status ON governance_proposals (status);
CREATE INDEX IF NOT EXISTS idx_proposals_end ON governance_proposals (voting_end);

CREATE TABLE IF NOT EXISTS votes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    proposal_id UUID REFERENCES governance_proposals(id) ON DELETE CASCADE,
    vote_choice VARCHAR(16) NOT NULL CHECK (vote_choice IN ('for', 'against', 'abstain')),
    tx_hash BYTEA,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(user_id, proposal_id)
);

CREATE INDEX IF NOT EXISTS idx_votes_proposal ON votes (proposal_id);

-- ============================================================
-- DEPOSIT POOLS & AMM LIQUIDITY
-- ============================================================

CREATE TABLE IF NOT EXISTS deposit_pools (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    token_address BYTEA NOT NULL,
    chain_id INTEGER NOT NULL,
    pool_name VARCHAR(128) NOT NULL,
    total_supply NUMERIC(78, 0) NOT NULL DEFAULT 0,
    fee_bps INTEGER NOT NULL DEFAULT 30,
    tvl NUMERIC(78, 0) NOT NULL DEFAULT 0,
    last_tvl_update TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_pools_token ON deposit_pools (token_address, chain_id);

-- ============================================================
-- EXCHANGE RATES & ORACLE SNAPSHOTS
-- ============================================================

CREATE TABLE IF NOT EXISTS exchange_rates (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    base_symbol VARCHAR(16) NOT NULL,
    quote_symbol VARCHAR(16) NOT NULL,
    rate NUMERIC(30, 10) NOT NULL,
    source VARCHAR(32) NOT NULL CHECK (source IN ('coingecko', 'chainlink', 'api', 'internal')),
    fetched_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    valid_until TIMESTAMPTZ NOT NULL,
    UNIQUE (base_symbol, quote_symbol, source)
);

CREATE INDEX IF NOT EXISTS idx_rates_symbol ON exchange_rates (base_symbol, quote_symbol);

-- ============================================================
-- AUDIT & METADATA
-- ============================================================

CREATE TABLE IF NOT EXISTS audit_log (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    entity_type VARCHAR(32) NOT NULL,
    entity_id UUID NOT NULL,
    action VARCHAR(16) NOT NULL,
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    details JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_audit_entity ON audit_log (entity_type, entity_id);

-- ============================================================
-- SAFETY & HELPERS
-- ============================================================

CREATE OR REPLACE FUNCTION update_wallets_updated_at()
RETURNS TRIGGER AS $$ BEGIN
    NEW.updated_at = NOW(); RETURN NEW; END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_update_wallets_updated_at ON wallets;
CREATE TRIGGER trigger_update_wallets_updated_at
    BEFORE UPDATE ON wallets
    FOR EACH ROW EXECUTE FUNCTION update_wallets_updated_at();

COMMENT ON TABLE users IS 'Core user accounts linked to blockchain identities';
COMMENT ON TABLE wallets IS 'Per-chain wallet instances owned by users';
COMMENT ON TABLE transactions IS 'Immutable log of all on-chain and off-chain activity';
COMMENT ON TABLE nfts IS 'Non-fungible token holdings with metadata references';
COMMENT ON TABLE governance_proposals IS 'Decentralized voting proposals for protocol evolution';
COMMENT ON TABLE exchange_rates IS 'Oracle-backed price feeds for DeFi calculations';
