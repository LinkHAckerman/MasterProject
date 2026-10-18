-- PostgreSQL schema for Magnum Opus: Enhanced with support for NFTs, DeFi contracts, and multi-chain asset tracking
-- Updated for full-stack Web3 ecosystem integration

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Enum for transaction status
CREATE TYPE tx_status AS ENUM ('pending','confirmed','failed','reverted');

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
    fee NUMERIC(38,18) NOT NULL DEFAULT 0,
    gas_price NUMERIC(38,18),
    gas_used BIGINT,
    status tx_status NOT NULL DEFAULT 'pending',
    transaction_type VARCHAR(50) CHECK (transaction_type IN ('transfer','swap','stake','unstake','mint','burn','approve','deposit','withdraw','claim','liquidate','other')),
    metadata JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_transactions_updated_at
BEFORE UPDATE ON transactions
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- Smart Contract Events
CREATE TABLE IF NOT EXISTS contract_events (
    event_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tx_id UUID NOT NULL REFERENCES transactions(tx_id) ON DELETE CASCADE,
    contract_address VARCHAR(42) NOT NULL,
    event_name VARCHAR(100) NOT NULL,
    event_data JSONB NOT NULL,
    block_number BIGINT NOT NULL,
    log_index BIGINT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (tx_id, contract_address, event_name, log_index)
);

-- DeFi Protocol Data
CREATE TABLE IF NOT EXISTS defi_protocols (
    protocol_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(100) NOT NULL,
    description TEXT,
    website_url VARCHAR(255),
    logo_url VARCHAR(255),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_defi_protocols_updated_at
BEFORE UPDATE ON defi_protocols
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- Protocol Contracts
CREATE TABLE IF NOT EXISTS protocol_contracts (
    contract_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    protocol_id UUID NOT NULL REFERENCES defi_protocols(protocol_id) ON DELETE CASCADE,
    contract_address VARCHAR(42) NOT NULL,
    network VARCHAR(30) NOT NULL,
    contract_type VARCHAR(50) NOT NULL,
    abi JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (contract_address, network),
    CONSTRAINT chk_protocol_network CHECK (network IN ('Ethereum','Polygon','BinanceSmartChain','Solana','Avalanche','PolygonZK','Arbitrum','Optimism','Base','Mantle'))
);

CREATE TRIGGER trg_protocol_contracts_updated_at
BEFORE UPDATE ON protocol_contracts
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- Protocol Transactions
CREATE TABLE IF NOT EXISTS protocol_transactions (
    protocol_tx_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tx_id UUID NOT NULL REFERENCES transactions(tx_id) ON DELETE CASCADE,
    protocol_id UUID NOT NULL REFERENCES defi_protocols(protocol_id) ON DELETE CASCADE,
    contract_id UUID NOT NULL REFERENCES protocol_contracts(contract_id) ON DELETE CASCADE,
    action VARCHAR(50) NOT NULL,
    action_data JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (tx_id, protocol_id, contract_id)
);

-- Staking Positions
CREATE TABLE IF NOT EXISTS staking_positions (
    position_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    wallet_id UUID NOT NULL REFERENCES wallets(wallet_id) ON DELETE CASCADE,
    protocol_id UUID NOT NULL REFERENCES defi_protocols(protocol_id) ON DELETE CASCADE,
    contract_id UUID NOT NULL REFERENCES protocol_contracts(contract_id) ON DELETE CASCADE,
    asset_id UUID NOT NULL REFERENCES assets(asset_id) ON DELETE RESTRICT,
    amount NUMERIC(38,18) NOT NULL,
    start_date TIMESTAMPTZ NOT NULL,
    end_date TIMESTAMPTZ,
    status VARCHAR(20) NOT NULL DEFAULT 'active',
    rewards_earned NUMERIC(38,18) NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_staking_status CHECK (status IN ('active','claimed','withdrawn','liquidated'))
);

CREATE TRIGGER trg_staking_positions_updated_at
BEFORE UPDATE ON staking_positions
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- Staking Rewards
CREATE TABLE IF NOT EXISTS staking_rewards (
    reward_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    position_id UUID NOT NULL REFERENCES staking_positions(position_id) ON DELETE CASCADE,
    asset_id UUID NOT NULL REFERENCES assets(asset_id) ON DELETE RESTRICT,
    amount NUMERIC(38,18) NOT NULL,
    reward_date TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Liquidity Pools
CREATE TABLE IF NOT EXISTS liquidity_pools (
    pool_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    protocol_id UUID NOT NULL REFERENCES defi_protocols(protocol_id) ON DELETE CASCADE,
    contract_id UUID NOT NULL REFERENCES protocol_contracts(contract_id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_liquidity_pools_updated_at
BEFORE UPDATE ON liquidity_pools
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- Pool Assets
CREATE TABLE IF NOT EXISTS pool_assets (
    pool_asset_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    pool_id UUID NOT NULL REFERENCES liquidity_pools(pool_id) ON DELETE CASCADE,
    asset_id UUID NOT NULL REFERENCES assets(asset_id) ON DELETE RESTRICT,
    weight NUMERIC(10,8) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (pool_id, asset_id)
);

CREATE TRIGGER trg_pool_assets_updated_at
BEFORE UPDATE ON pool_assets
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- Liquidity Positions
CREATE TABLE IF NOT EXISTS liquidity_positions (
    position_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    wallet_id UUID NOT NULL REFERENCES wallets(wallet_id) ON DELETE CASCADE,
    pool_id UUID NOT NULL REFERENCES liquidity_pools(pool_id) ON DELETE CASCADE,
    amount NUMERIC(38,18) NOT NULL,
    start_date TIMESTAMPTZ NOT NULL,
    end_date TIMESTAMPTZ,
    status VARCHAR(20) NOT NULL DEFAULT 'active',
    rewards_earned NUMERIC(38,18) NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_liquidity_status CHECK (status IN ('active','withdrawn','liquidated'))
);

CREATE TRIGGER trg_liquidity_positions_updated_at
BEFORE UPDATE ON liquidity_positions
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- Liquidity Rewards
CREATE TABLE IF NOT EXISTS liquidity_rewards (
    reward_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    position_id UUID NOT NULL REFERENCES liquidity_positions(position_id) ON DELETE CASCADE,
    asset_id UUID NOT NULL REFERENCES assets(asset_id) ON DELETE RESTRICT,
    amount NUMERIC(38,18) NOT NULL,
    reward_date TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Function to update the updated_at timestamp
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
