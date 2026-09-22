-- Magnum Opus Data Layer Schema
-- Purpose: Centralized relational store for users, wallets, transactions, NFTs, staking, and governance.
-- Compatible with PostgreSQL 14+.

-- Enable extensions for UUID and crypto functions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Enums for type safety and query optimization
CREATE TYPE enum_user_role AS ENUM ('standard', 'validator', 'governor', 'admin');
CREATE TYPE enum_wallet_type AS ENUM ('external', 'contract', 'multisig', 'smart_account');
CREATE TYPE enum_tx_status AS ENUM ('pending', 'confirmed', 'failed', 'reverted', 'dropped');
CREATE TYPE enum_tx_type AS ENUM ('transfer', 'swap', 'liquidity_add', 'liquidity_remove', 'stake', 'unstake', 'mint', 'burn', 'governance_vote');
CREATE TYPE enum_chain_id AS ENUM ('eip155_1', 'eip155_137', 'eip155_56', 'solana', 'eip155_42161', 'eip155_324');

-- Core entities

CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    wallet_address VARCHAR(42) NOT NULL UNIQUE,
    email VARCHAR(255),
    role enum_user_role DEFAULT 'standard',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    last_active_at TIMESTAMPTZ DEFAULT NOW(),
    is_active BOOLEAN DEFAULT TRUE
);

CREATE TABLE wallets (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    chain enum_chain_id NOT NULL,
    address VARCHAR(42) NOT NULL,
    type enum_wallet_type DEFAULT 'external',
    label VARCHAR(100),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (user_id, chain, address)
);

CREATE TABLE transactions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    block_hash VARCHAR(66),
    block_number BIGINT,
    from_address VARCHAR(42),
    to_address VARCHAR(42),
    value NUMERIC(78, 4) NOT NULL DEFAULT '0',
    gas_price NUMERIC(78, 4),
    gas_limit INTEGER,
    total_fee NUMERIC(78, 4) DEFAULT 0,
    status enum_tx_status DEFAULT 'pending',
    type enum_tx_type NOT NULL,
    raw_receipt JSONB,
    timestamp TIMESTAMPTZ DEFAULT NOW(),
    confirmed_at TIMESTAMPTZ,
    confirmations INTEGER DEFAULT 0
);

CREATE INDEX idx_tx_from ON transactions(from_address);
CREATE INDEX idx_tx_to ON transactions(to_address);
CREATE INDEX idx_tx_status ON transactions(status);
CREATE INDEX idx_tx_block ON transactions(block_number);
CREATE INDEX idx_tx_timestamp ON transactions(timestamp);

CREATE TABLE nfts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    contract_address VARCHAR(42) NOT NULL,
    token_id VARCHAR(66) NOT NULL,
    name VARCHAR(255),
    description TEXT,
    owner_address VARCHAR(42) NOT NULL,
    image_url TEXT,
    metadata_url TEXT,
    chain enum_chain_id NOT NULL,
    schema_name VARCHAR(50),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (contract_address, token_id, chain)
);

CREATE INDEX idx_nfts_owner ON nfts(owner_address);
CREATE INDEX idx_nfts_contract ON nfts(contract_address);

CREATE TABLE staking_pools (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(255) NOT NULL,
    symbol VARCHAR(20) NOT NULL,
    chain enum_chain_id NOT NULL,
    total_staked NUMERIC(78, 4) DEFAULT 0,
    reward_rate_per_sec NUMERIC(78, 8) DEFAULT 0,
    apr_percentage NUMERIC(5, 2) DEFAULT 0,
    minimum_withdrawal NUMERIC(78, 4),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE staking_participants (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    pool_id UUID REFERENCES staking_pools(id) ON DELETE CASCADE,
    amount NUMERIC(78, 4) NOT NULL,
    amount_usd NUMERIC(78, 2),
    staked_at TIMESTAMPTZ DEFAULT NOW(),
    unlocked_at TIMESTAMPTZ,
    rewards_earned NUMERIC(78, 4) DEFAULT 0,
    rewards_claimed NUMERIC(78, 4) DEFAULT 0,
    status BOOLEAN DEFAULT TRUE,
    UNIQUE (user_id, pool_id)
);

CREATE TABLE governance_proposals (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    title VARCHAR(500) NOT NULL,
    description TEXT,
    proposer_address VARCHAR(42) NOT NULL,
    status VARCHAR(50) DEFAULT 'active',
    voting_start TIMESTAMPTZ NOT NULL,
    voting_end TIMESTAMPTZ NOT NULL,
    quorum_threshold NUMERIC(78, 4) NOT NULL,
    for_votes NUMERIC(78, 4) DEFAULT 0,
    against_votes NUMERIC(78, 4) DEFAULT 0,
    yes_votes NUMERIC(78, 4) DEFAULT 0,
    no_votes NUMERIC(78, 4) DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    executed_at TIMESTAMPTZ
);

CREATE TABLE governance_votes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    proposal_id UUID REFERENCES governance_proposals(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    vote BOOLEAN NOT NULL,
    voted_at TIMESTAMPTZ DEFAULT NOW(),
    signature VARCHAR(128),
    UNIQUE (proposal_id, user_id)
);

-- Performance indexes

CREATE INDEX idx_proposals_status ON governance_proposals(status);
CREATE INDEX idx_proposals_end ON governance_proposals(voting_end);
CREATE INDEX idx_votes_proposal ON governance_votes(proposal_id);
CREATE INDEX idx_participants_pool ON staking_participants(pool_id);

-- Optimized view for dashboard portfolio summary (matches app.js state shape)

CREATE OR REPLACE VIEW user_portfolio_summary AS
SELECT
    u.id AS user_id,
    w.address AS wallet_address,
    w.chain AS wallet_chain,
    COALESCE(SUM(CASE WHEN t.type = 'transfer' AND t.from_address = w.address THEN -t.value ELSE 0 END), 0) + COALESCE(SUM(CASE WHEN t.type = 'transfer' AND t.to_address = w.address THEN t.value ELSE 0 END), 0) AS net_balance,
    COALESCE(SUM(t.value), 0) AS total_volume_transacted,
    (SELECT COUNT(*) FROM staking_participants sp WHERE sp.user_id = u.id AND sp.status) AS active_staking_positions,
    (SELECT COUNT(*) FROM nfts n WHERE n.owner_address = w.address) AS nft_holdings,
    (SELECT COALESCE(SUM(amount), 0) FROM staking_participants sp WHERE sp.user_id = u.id AND sp.status) AS total_staked
FROM users u
JOIN wallets w ON u.id = w.user_id
LEFT JOIN transactions t ON (t.from_address = w.address OR t.to_address = w.address) AND t.status = 'confirmed'
GROUP BY u.id, w.address, w.chain;

-- Security & access

GRANT ALL ON ALL TABLES IN SCHEMA public TO app_service;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO app_service;

-- Comment block for documentation
COMMENT ON TABLE users IS 'Application users, linked to primary wallet address.';
COMMENT ON TABLE transactions IS 'All on-chain and off-chain transaction records, indexed for fast lookup.';
COMMENT ON TABLE governance_proposals IS 'Magnum Opus on-chain governance proposals, tracked via MIPs.';