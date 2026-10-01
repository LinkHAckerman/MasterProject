-- Magnum Opus // Web3 & DeFi Nexus Engine - Data Layer Schema
-- PostgreSQL 15+ compatible (adapt syntax for other RDBMS as needed)

-- =============================================
-- Core Identity & Authentication
-- =============================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TYPE user_role AS ENUM ('user', 'admin', 'validator');
CREATE TYPE wallet_type AS ENUM ('EOA', 'MPC', 'SmartContract');
CREATE TYPE transaction_type AS ENUM ('transfer', 'swap', 'mint', 'burn', 'staking', 'unstaking', 'nft_transfer');
CREATE TYPE token_standard AS ENUM ('ERC20', 'ERC721', 'ERC1155', 'BEP20', 'SPL', 'Native');

CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    wallet_address VARCHAR(42) UNIQUE NOT NULL,
    email VARCHAR(255),
    role user_role DEFAULT 'user',
    is_verified BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    last_login TIMESTAMPTZ,
    metadata JSONB DEFAULT '{}'
);

-- =============================================
-- Wallet Management (supports EOA, MPC, SmartContract)
-- =============================================

CREATE TABLE wallets (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    address VARCHAR(42) NOT NULL,
    type wallet_type DEFAULT 'EOA',
    chain_id VARCHAR(20) NOT NULL,
    is_primary BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    last_sync TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, address)
);

-- =============================================
-- Transaction History & Blockchain Events
-- =============================================

CREATE TABLE transactions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    wallet_id UUID REFERENCES wallets(id) ON DELETE SET NULL,
    hash VARCHAR(66) UNIQUE NOT NULL,
    type transaction_type NOT NULL,
    status VARCHAR(50) DEFAULT 'finalized',
    from_address VARCHAR(42),
    to_address VARCHAR(42),
    amount DECIMAL(78, 18) DEFAULT 0,
    gas_used BIGINT DEFAULT 0,
    gas_price BIGINT DEFAULT 0,
    fee DECIMAL(78, 18) DEFAULT 0,
    block_number BIGINT,
    chain_id VARCHAR(20) NOT NULL,
    timestamp TIMESTAMPTZ DEFAULT NOW(),
    decoded_data JSONB DEFAULT '{}',
    log_index INTEGER DEFAULT 0
);

CREATE INDEX idx_transactions_wallet_id ON transactions(wallet_id);
CREATE INDEX idx_transactions_hash ON transactions(hash);
CREATE INDEX idx_transactions_timestamp ON transactions(timestamp);
CREATE INDEX idx_transactions_from_to ON transactions(from_address, to_address);
CREATE INDEX idx_transactions_chain ON transactions(chain_id);

-- =============================================
-- Token & Asset Registry
-- =============================================

CREATE TABLE tokens (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    symbol VARCHAR(20) NOT NULL,
    name VARCHAR(100) NOT NULL,
    decimals INTEGER DEFAULT 18,
    contract_address VARCHAR(42),
    chain_id VARCHAR(20) NOT NULL,
    standard token_standard DEFAULT 'ERC20',
    is_native BOOLEAN DEFAULT FALSE,
    is_verified BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'
);

-- =============================================
-- NFT Collection & Ownership Tracker
-- =============================================

CREATE TABLE nfts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    token_id VARCHAR(100) NOT NULL,
    contract_address VARCHAR(42) NOT NULL,
    owner_address VARCHAR(42) NOT NULL,
    chain_id VARCHAR(20) NOT NULL,
    token_type VARCHAR(50) DEFAULT 'standard', -- 'ERC721', 'ERC1155', 'Dynamic', 'Fractionalized'
    metadata_json JSONB DEFAULT '{}',
    rarity_tier VARCHAR(50),
    last_seen_block BIGINT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_nfts_owner ON nfts(owner_address);
CREATE INDEX idx_nfts_contract ON nfts(contract_address);
CREATE INDEX idx_nfts_token_id ON nfts(token_id);

-- =============================================
-- DeFi Positions & Lifecycle Tracking
-- =============================================

CREATE TABLE defi_positions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    wallet_id UUID REFERENCES wallets(id) ON DELETE CASCADE,
    token_id UUID REFERENCES tokens(id) ON DELETE SET NULL,
    protocol VARCHAR(100) NOT NULL, -- e.g., 'UniswapV3', 'Aave', 'Compound', 'Raydium'
    position_type VARCHAR(50) NOT NULL, -- 'liquidity', 'staking', 'lending', 'short', 'long'
    amount DECIMAL(78, 18) DEFAULT 0,
    entry_price DECIMAL(78, 18) DEFAULT 0,
    current_price DECIMAL(78, 18) DEFAULT 0,
    apy DECIMAL(10, 4),
    apr DECIMAL(10, 4),
    entered_at TIMESTAMPTZ DEFAULT NOW(),
    exited_at TIMESTAMPTZ,
    status VARCHAR(50) DEFAULT 'active' -- 'active', 'claimed', 'withdrawn', 'expired'
);

CREATE INDEX idx_defi_positions_wallet ON defi_positions(wallet_id);
CREATE INDEX idx_defi_positions_protocol ON defi_positions(protocol);
CREATE INDEX idx_defi_positions_status ON defi_positions(status);

-- =============================================
-- Staking & Validator Participation
-- =============================================

CREATE TABLE staking_activations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    wallet_id UUID REFERENCES wallets(id) ON DELETE CASCADE,
    validator_index INTEGER NOT NULL,
    stake_amount DECIMAL(78, 18) DEFAULT 0,
    expected_return DECIMAL(78, 18) DEFAULT 0,
    unbonding_epoch INTEGER DEFAULT 0,
    claimed_rewards DECIMAL(78, 18) DEFAULT 0,
    status VARCHAR(50) DEFAULT 'active',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_staking_wallet ON staking_activations(wallet_id);

-- =============================================
-- Audit & Compliance Log
-- =============================================

CREATE TABLE audit_log (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    action VARCHAR(100) NOT NULL, -- e.g., 'wallet_connect', 'swap_execute', 'nft_mint', 'position_claim'
    resource_type VARCHAR(50),
    resource_id UUID,
    details JSONB DEFAULT '{}',
    ip_inet INET,
    user_agent TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_audit_user ON audit_log(user_id);
CREATE INDEX idx_audit_created ON audit_log(created_at);

-- =============================================
-- Metadata & Configuration Cache
-- =============================================

CREATE TABLE platform_config (
    key VARCHAR(100) PRIMARY KEY,
    value JSONB NOT NULL,
    updated_by UUID REFERENCES users(id),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- =============================================
-- End of Schema
-- =============================================
--
-- Indexes, triggers, and constraints can be added per-environment.
-- Ensure proper backups and migration strategy (e.g., using Flyway or pgMigrate).
--
-- Recommended additions per ecosystem:
-- - EVM: token_approvals table, event_logs partitioning by block_number
-- - Solana: program_id indexes, slot-based partitioning
-- - Cosmos: denom tracking, fee-grant records
-- - Bitcoin: txid/wout tracking via OP_RETURN metadata
