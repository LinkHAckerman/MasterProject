-- MAGNUM OPUS // Unified Data Layer Schema
-- Cross-ecosystem support: Ethereum, BNB Chain, Solana, Polygon, Arbitrum, etc.
-- Designed for high-throughput crypto, NFT, and DeFi operations.

-- Extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Core Chains Reference
CREATE TABLE IF NOT EXISTS chains (
    id SERIAL PRIMARY KEY,
    name VARCHAR(50) NOT NULL UNIQUE,
    rpc_url TEXT NOT NULL,
    native_token VARCHAR(20) NOT NULL DEFAULT 'ETH',
    explorer_url_template TEXT NOT NULL,
    is_evm BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Example inserts
-- INSERT INTO chains (name, rpc_url, native_token, explorer_url_template, is_evm) VALUES ('Ethereum Mainnet', 'https://mainnet.infura.io/v3/<PROJECT_ID>', 'ETH', 'https://etherscan.io/tx/{{tx_hash}}', TRUE);
-- INSERT INTO chains (name, rpc_url, native_token, explorer_url_template, is_evm) VALUES ('Solana', 'https://api.mainnet-beta.solana.com', 'SOL', 'https://explorer.solana.com/tx/{{tx_hash}}', FALSE);

-- Users & Authentication
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email VARCHAR(255) UNIQUE NOT NULL,
    username VARCHAR(100) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Multi-Chain Wallets
CREATE TABLE IF NOT EXISTS wallets (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    chain_id INTEGER NOT NULL REFERENCES chains(id),
    address VARCHAR(255) NOT NULL,
    label VARCHAR(100), -- e.g., "Main Wallet", "Cold Storage"
    is_connected BOOLEAN DEFAULT FALSE,
    last_connected_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(user_id, chain_id, address)
);

-- Transaction History (On-chain + Internal)
CREATE TABLE IF NOT EXISTS transactions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    wallet_id UUID REFERENCES wallets(id) ON DELETE SET NULL,
    chain_id INTEGER NOT NULL REFERENCES chains(id),
    tx_hash VARCHAR(66) UNIQUE NOT NULL,
    block_number BIGINT NOT NULL,
    from_address VARCHAR(255),
    to_address VARCHAR(255),
    value NUMERIC(78, 0) NOT NULL DEFAULT 0, -- Native token amount (wei-equivalent)
    token_address VARCHAR(66), -- ERC20/NFT contract, NULL for native transfers
    token_id VARCHAR(100), -- For NFTs, otherwise NULL
    token_amount NUMERIC(78, 0) DEFAULT 0, -- Token-specific amount
    transaction_type VARCHAR(20) NOT NULL CHECK (transaction_type IN ('transfer', 'swap', 'mint', 'burn', 'staking', 'unstaking', 'contract_call')),
    status VARCHAR(20) DEFAULT 'pending' CHECK (status IN ('pending', 'confirmed', 'failed', 'replaced')),
    gas_used NUMERIC(78, 0),
    gas_price NUMERIC(78, 0),
    gas_cost_usd NUMERIC(20, 6),
    timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    decoded_data JSONB, -- Log data, event params, swap details
    INDEX idx_tx_hash (tx_hash),
    INDEX idx_wallet_chain (wallet_id, chain_id),
    INDEX idx_block_number (block_number),
    INDEX idx_timestamp (timestamp)
);

-- NFT Collection & Ownership
CREATE TABLE IF NOT EXISTS nfts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    wallet_id UUID REFERENCES wallets(id) ON DELETE CASCADE,
    chain_id INTEGER NOT NULL REFERENCES chains(id),
    contract_address VARCHAR(66) NOT NULL,
    token_id VARCHAR(100) NOT NULL,
    name VARCHAR(255),
    symbol VARCHAR(50),
    token_uri TEXT,-- IPFS or HTTP metadata link
    metadata_uri TEXT,-- JSON-CIP metadata location
    rarity_tier VARCHAR(20),-- Common, Rare, Epic, Legendary
    acquisition_block BIGINT,
    acquisition_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    is_favorited BOOLEAN DEFAULT FALSE,
    UNIQUE(chain_id, contract_address, token_id)
);

-- Indexer for quick NFT portfolio queries
CREATE INDEX idx_nft_wallet (wallet_id, chain_id);
CREATE INDEX idx_nft_contract_token (contract_address, token_id);

-- DeFi Positions (Liquidity Mining, Staking, Vault Shares)
CREATE TABLE IF NOT EXISTS defi_positions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    wallet_id UUID REFERENCES wallets(id) ON DELETE CASCADE,
    chain_id INTEGER NOT NULL REFERENCES chains(id),
    contract_address VARCHAR(66) NOT NULL,-- Router, Pool, or Vault address
    position_type VARCHAR(30) NOT NULL CHECK (position_type IN ('liquidity_pool', 'staking', 'yield_vault', 'lending', 'borrowing', 'farm')),
    token_in_address VARCHAR(66),
    token_out_address VARCHAR(66),
    amount_in NUMERIC(78, 0) DEFAULT 0,
    amount_out NUMERIC(78, 0) DEFAULT 0,
    share_percentage NUMERIC(10, 6),
    apr NUMERIC(10, 4),
    last_reward_timestamp TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(wallet_id, chain_id, contract_address)
);

-- Cached Token Prices (USD)
CREATE TABLE IF NOT EXISTS token_prices (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    chain_id INTEGER NOT NULL REFERENCES chains(id),
    token_address VARCHAR(66) NOT NULL,
    price_usd NUMERIC(30, 8) NOT NULL,
    price_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    source VARCHAR(50) NOT NULL DEFAULT 'coingecko',
    UNIQUE(chain_id, token_address, price_timestamp)
);

-- Index for price lookups
CREATE INDEX idx_token_prices_chain_token_ts (chain_id, token_address, price_timestamp DESC);

-- Audit Log for critical actions (security/compliance)
CREATE TABLE IF NOT EXISTS audit_log (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    action VARCHAR(100) NOT NULL,-- e.g., "wallet_connect", "swap_execute", "nft_mint"
    resource_type VARCHAR(50),-- e.g., "wallet", "transaction", "nft"
    resource_id UUID,
    details JSONB,-- Flexible key-value audit details
    ip_inet INET,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Index for audit queries
CREATE INDEX idx_audit_user_time (user_id, created_at DESC);

-- Grant permissions if needed (PostgreSQL)
GRANT ALL ON ALL TABLES IN PUBLIC TO anon_role;-- Adjust per security policy
-- REVOKE ALL ON audit_log FROM PUBLIC;-- Keep audit restricted