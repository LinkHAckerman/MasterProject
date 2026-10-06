-- MAGNUM OPUS // Web3 & DeFi Nexus Engine - Core Database Schema
-- Optimized for high-performance blockchain data storage and retrieval

-- Users table with enhanced security and multi-chain support
CREATE TABLE users (
    user_id SERIAL PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    salt VARCHAR(255) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    is_verified BOOLEAN DEFAULT FALSE,
    verification_token VARCHAR(255),
    reset_token VARCHAR(255),
    reset_token_expires_at TIMESTAMP WITH TIME ZONE,
    profile_picture_url VARCHAR(255),
    bio TEXT,
    last_login_at TIMESTAMP WITH TIME ZONE,
    failed_login_attempts INTEGER DEFAULT 0,
    is_locked BOOLEAN DEFAULT FALSE,
    lock_until TIMESTAMP WITH TIME ZONE,
    two_factor_enabled BOOLEAN DEFAULT FALSE,
    two_factor_secret VARCHAR(255),
    recovery_codes TEXT[],
    CONSTRAINT valid_email CHECK (email ~* '^[A-Za-z0-9._%-]+@[A-Za-z0-9.-]+[.][A-Za-z]+$')
);

-- Wallets table with multi-chain and hardware wallet support
CREATE TABLE wallets (
    wallet_id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL,
    wallet_address VARCHAR(42) UNIQUE NOT NULL,
    wallet_type VARCHAR(20) NOT NULL CHECK (wallet_type IN ('software', 'hardware', 'paper')),
    chain_id VARCHAR(10) NOT NULL,
    network_name VARCHAR(50) NOT NULL,
    is_default BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
    CONSTRAINT valid_wallet_address CHECK (wallet_address ~* '^0x[a-fA-F0-9]{40}$')
);

-- Tokens table for tracking user's tokens across multiple chains
CREATE TABLE tokens (
    token_id SERIAL PRIMARY KEY,
    wallet_id INTEGER NOT NULL,
    token_address VARCHAR(42) NOT NULL,
    token_symbol VARCHAR(10) NOT NULL,
    token_name VARCHAR(50) NOT NULL,
    token_decimals INTEGER NOT NULL,
    token_balance DECIMAL(38, 18) NOT NULL DEFAULT 0,
    is_native BOOLEAN DEFAULT FALSE,
    chain_id VARCHAR(10) NOT NULL,
    network_name VARCHAR(50) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (wallet_id) REFERENCES wallets(wallet_id) ON DELETE CASCADE,
    CONSTRAINT valid_token_address CHECK (token_address ~* '^0x[a-fA-F0-9]{40}$')
);

-- Transactions table with enhanced indexing for performance
CREATE TABLE transactions (
    transaction_id SERIAL PRIMARY KEY,
    wallet_id INTEGER NOT NULL,
    transaction_hash VARCHAR(66) UNIQUE NOT NULL,
    from_address VARCHAR(42) NOT NULL,
    to_address VARCHAR(42) NOT NULL,
    value DECIMAL(38, 18) NOT NULL,
    gas_price DECIMAL(38, 18) NOT NULL,
    gas_used INTEGER NOT NULL,
    gas_limit INTEGER NOT NULL,
    nonce INTEGER NOT NULL,
    transaction_index INTEGER NOT NULL,
    block_number INTEGER NOT NULL,
    block_hash VARCHAR(66) NOT NULL,
    transaction_type VARCHAR(20) NOT NULL,
    status VARCHAR(20) NOT NULL CHECK (status IN ('pending', 'confirmed', 'failed')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (wallet_id) REFERENCES wallets(wallet_id) ON DELETE CASCADE,
    CONSTRAINT valid_transaction_hash CHECK (transaction_hash ~* '^0x[a-fA-F0-9]{64}$'),
    CONSTRAINT valid_from_address CHECK (from_address ~* '^0x[a-fA-F0-9]{40}$'),
    CONSTRAINT valid_to_address CHECK (to_address ~* '^0x[a-fA-F0-9]{40}$')
);

-- Transaction logs for detailed transaction history
CREATE TABLE transaction_logs (
    log_id SERIAL PRIMARY KEY,
    transaction_id INTEGER NOT NULL,
    log_index INTEGER NOT NULL,
    address VARCHAR(42) NOT NULL,
    topics TEXT[] NOT NULL,
    data BYTEA NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (transaction_id) REFERENCES transactions(transaction_id) ON DELETE CASCADE,
    CONSTRAINT valid_address CHECK (address ~* '^0x[a-fA-F0-9]{40}$')
);

-- Smart contracts table for tracking deployed contracts
CREATE TABLE smart_contracts (
    contract_id SERIAL PRIMARY KEY,
    wallet_id INTEGER NOT NULL,
    contract_address VARCHAR(42) UNIQUE NOT NULL,
    contract_name VARCHAR(50) NOT NULL,
    contract_abi JSONB NOT NULL,
    bytecode BYTEA NOT NULL,
    deployed_at TIMESTAMP WITH TIME ZONE NOT NULL,
    chain_id VARCHAR(10) NOT NULL,
    network_name VARCHAR(50) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (wallet_id) REFERENCES wallets(wallet_id) ON DELETE CASCADE,
    CONSTRAINT valid_contract_address CHECK (contract_address ~* '^0x[a-fA-F0-9]{40}$')
);

-- Smart contract events table for tracking contract events
CREATE TABLE smart_contract_events (
    event_id SERIAL PRIMARY KEY,
    contract_id INTEGER NOT NULL,
    transaction_id INTEGER NOT NULL,
    event_name VARCHAR(50) NOT NULL,
    event_data JSONB NOT NULL,
    block_number INTEGER NOT NULL,
    log_index INTEGER NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (contract_id) REFERENCES smart_contracts(contract_id) ON DELETE CASCADE,
    FOREIGN KEY (transaction_id) REFERENCES transactions(transaction_id) ON DELETE CASCADE
);

-- Indexes for performance optimization
CREATE INDEX idx_wallets_user_id ON wallets(user_id);
CREATE INDEX idx_tokens_wallet_id ON tokens(wallet_id);
CREATE INDEX idx_transactions_wallet_id ON transactions(wallet_id);
CREATE INDEX idx_transactions_block_number ON transactions(block_number);
CREATE INDEX idx_transaction_logs_transaction_id ON transaction_logs(transaction_id);
CREATE INDEX idx_smart_contracts_wallet_id ON smart_contracts(wallet_id);
CREATE INDEX idx_smart_contract_events_contract_id ON smart_contract_events(contract_id);
CREATE INDEX idx_smart_contract_events_transaction_id ON smart_contract_events(transaction_id);

-- Triggers for automatic timestamp updates
CREATE OR REPLACE FUNCTION update_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_user_timestamp
BEFORE UPDATE ON users
FOR EACH ROW
EXECUTE FUNCTION update_timestamp();

CREATE TRIGGER update_wallet_timestamp
BEFORE UPDATE ON wallets
FOR EACH ROW
EXECUTE FUNCTION update_timestamp();

CREATE TRIGGER update_token_timestamp
BEFORE UPDATE ON tokens
FOR EACH ROW
EXECUTE FUNCTION update_timestamp();

CREATE TRIGGER update_transaction_timestamp
BEFORE UPDATE ON transactions
FOR EACH ROW
EXECUTE FUNCTION update_timestamp();

CREATE TRIGGER update_smart_contract_timestamp
BEFORE UPDATE ON smart_contracts
FOR EACH ROW
EXECUTE FUNCTION update_timestamp();
