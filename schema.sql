-- PostgreSQL schema for Magnum Opus: Enhanced with support for NFTs, DeFi contracts, and multi-chain asset tracking
-- Updated for full-stack Web3 ecosystem integration

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

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
    UNIQUE (symbol, network),
    CONSTRAINT chk_token_network CHECK (network IN ('Ethereum','Polygon','BinanceSmartChain','Solana','Avalanche','PolygonZK','Arbitrum','Optimism','Base','Mantle'))
);

-- NFT Collection and Token Metadata
CREATE TABLE IF NOT EXISTS nft_collections (
    collection_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    asset_id UUID NOT NULL REFERENCES assets(asset_id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    image_url VARCHAR(255),
    attributes JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (asset_id)
);

-- NFT Token IDs and Ownership
CREATE TABLE IF NOT EXISTS nft_tokens (
    token_id VARCHAR(66) PRIMARY KEY,
    collection_id UUID NOT NULL REFERENCES nft_collections(collection_id) ON DELETE CASCADE,
    token_index BIGINT NOT NULL,
    owner_address VARCHAR(42) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (token_id, owner_address)
);

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
    fee NUMERIC(38,18) NOT NULL DEFAULT 0,
    gas_price NUMERIC(38,18),
    gas_used BIGINT,
    status tx_status NOT NULL DEFAULT 'pending',
    transaction_type VARCHAR(50) CHECK (transaction_type IN ('transfer','mint','burn','swap','stake','unstake','deposit','withdraw','approve','revoke','swap','liquidity_add','liquidity_remove','swap_exact_in','swap_exact_out','approve_for_delegate','delegate')),
    chain_id INTEGER,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    confirmed_at TIMESTAMPTZ,
    metadata JSONB,
    CONSTRAINT chk_amount_positive CHECK (amount >= 0),
    CONSTRAINT chk_fee_nonnegative CHECK (fee >= 0)
);

-- Indexes for fast lookup
CREATE INDEX IF NOT EXISTS idx_transactions_wallet ON transactions(wallet_id);
CREATE INDEX IF NOT EXISTS idx_transactions_asset ON transactions(asset_id);
CREATE INDEX IF NOT EXISTS idx_transactions_block ON transactions(block_number);
CREATE INDEX IF NOT EXISTS idx_transactions_created ON transactions(created_at);
CREATE INDEX IF NOT EXISTS idx_transactions_status ON transactions(status);

-- Smart Contract Interactions
CREATE TABLE IF NOT EXISTS smart_contract_interactions (
    interaction_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tx_id UUID NOT NULL REFERENCES transactions(tx_id) ON DELETE CASCADE,
    contract_address VARCHAR(42) NOT NULL,
    function_name VARCHAR(100) NOT NULL,
    function_signature VARCHAR(255),
    input_parameters JSONB,
    output_parameters JSONB,
    event_logs JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (tx_id, contract_address, function_name)
);

-- DeFi Protocol Interactions
CREATE TABLE IF NOT EXISTS defi_interactions (
    interaction_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tx_id UUID NOT NULL REFERENCES transactions(tx_id) ON DELETE CASCADE,
    protocol VARCHAR(50) NOT NULL,
    interaction_type VARCHAR(50) NOT NULL,
    pool_address VARCHAR(42),
    token_in UUID REFERENCES assets(asset_id),
    token_out UUID REFERENCES assets(asset_id),
    amount_in NUMERIC(38,18),
    amount_out NUMERIC(38,18),
    slippage NUMERIC(5,2),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (tx_id, protocol, interaction_type)
);

-- Staking and Yield Farming
CREATE TABLE IF NOT EXISTS staking_positions (
    position_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    wallet_id UUID NOT NULL REFERENCES wallets(wallet_id) ON DELETE CASCADE,
    asset_id UUID NOT NULL REFERENCES assets(asset_id) ON DELETE RESTRICT,
    amount NUMERIC(38,18) NOT NULL,
    start_date TIMESTAMPTZ NOT NULL,
    end_date TIMESTAMPTZ,
    apr NUMERIC(10,2),
    status VARCHAR(20) NOT NULL DEFAULT 'active',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_staking_status CHECK (status IN ('active','completed','withdrawn','failed'))
);

-- Liquidity Pools
CREATE TABLE IF NOT EXISTS liquidity_pools (
    pool_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    protocol VARCHAR(50) NOT NULL,
    pool_address VARCHAR(42) NOT NULL UNIQUE,
    token0 UUID NOT NULL REFERENCES assets(asset_id),
    token1 UUID NOT NULL REFERENCES assets(asset_id),
    fee_tier VARCHAR(10),
    liquidity NUMERIC(38,18),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (protocol, pool_address)
);

-- User Preferences
CREATE TABLE IF NOT EXISTS user_preferences (
    preference_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    preference_key VARCHAR(100) NOT NULL,
    preference_value JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, preference_key)
);

-- Audit Logs
CREATE TABLE IF NOT EXISTS audit_logs (
    log_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    action VARCHAR(100) NOT NULL,
    entity_type VARCHAR(50),
    entity_id VARCHAR(255),
    old_values JSONB,
    new_values JSONB,
    ip_address VARCHAR(45),
    user_agent TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_entity_type CHECK (entity_type IN ('user','wallet','transaction','asset','nft','staking','liquidity_pool','preference'))
);

-- Indexes for audit logs
CREATE INDEX IF NOT EXISTS idx_audit_logs_user ON audit_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_action ON audit_logs(action);
CREATE INDEX IF NOT EXISTS idx_audit_logs_entity ON audit_logs(entity_type, entity_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_created ON audit_logs(created_at);
