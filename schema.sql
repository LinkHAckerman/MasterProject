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
CREATE INDEX IF NOT EXISTS idx_transactions_chain ON transactions(chain_id);

-- DeFi Contract Interaction Logs
CREATE TABLE IF NOT EXISTS contract_interactions (
    interaction_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    wallet_id UUID NOT NULL REFERENCES wallets(wallet_id) ON DELETE CASCADE,
    contract_address VARCHAR(42) NOT NULL,
    function_name VARCHAR(100) NOT NULL,
    input_data TEXT,
    output_data TEXT,
    gas_used BIGINT,
    gas_price NUMERIC(38,18),
    status VARCHAR(20) NOT NULL DEFAULT 'pending',
    chain_id INTEGER,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (wallet_id, contract_address, function_name)
);

-- Price Feed Integration
CREATE TABLE IF NOT EXISTS price_feed (
    token_id UUID NOT NULL REFERENCES assets(asset_id) ON DELETE CASCADE,
    price_usd NUMERIC(38,8) NOT NULL,
    last_updated TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    source VARCHAR(50),
    PRIMARY KEY (token_id)
);

-- DeFi Pool and Liquidity Tracking
CREATE TABLE IF NOT EXISTS liquidity_pools (
    pool_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(100) NOT NULL,
    description TEXT,
    token_a_id UUID NOT NULL REFERENCES assets(asset_id),
    token_b_id UUID NOT NULL REFERENCES assets(asset_id),
    total_liquidity NUMERIC(38,18) NOT NULL DEFAULT 0,
    reserve_a NUMERIC(38,18) NOT NULL DEFAULT 0,
    reserve_b NUMERIC(38,18) NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (token_a_id, token_b_id)
);

-- User Portfolio Aggregation View
CREATE OR REPLACE VIEW user_portfolio AS
SELECT
    u.id AS user_id,
    u.email,
    u.full_name,
    w.wallet_id,
    w.address,
    w.network,
    a.symbol,
    a.name,
    a.token_type,
    b.balance,
    a.decimals,
    (b.balance * COALESCE(p.price_usd,0)) AS value_usd,
    (b.balance * COALESCE(p.price_usd,0)) * 10^(-a.decimals) AS value_usd_raw,
    n.name AS collection_name,
    n.image_url AS collection_image,
    CASE WHEN a.is_nft THEN n.token_id ELSE NULL END AS token_id,
    CASE WHEN a.is_nft THEN n.collection_id ELSE NULL END AS collection_id
FROM users u
JOIN wallets w ON w.user_id = u.id
LEFT JOIN balances b ON b.wallet_id = w.wallet_id
LEFT JOIN assets a ON b.asset_id = a.asset_id
LEFT JOIN nft_collections n ON n.asset_id = a.asset_id AND a.is_nft
LEFT JOIN price_feed p ON p.token_id = a.asset_id
LEFT JOIN nft_tokens nt ON nt.owner_address = w.address AND nt.token_id = a.contract_address AND a.is_nft
WHERE w.is_active = TRUE
ORDER BY value_usd DESC;

-- Function to insert a new transaction safely
CREATE OR REPLACE FUNCTION insert_transaction(
    p_wallet_id UUID,
    p_asset_id UUID,
    p_tx_hash VARCHAR,
    p_block_number BIGINT,
    p_from VARCHAR,
    p_to VARCHAR,
    p_amount NUMERIC,
    p_fee NUMERIC,
    p_gas_price NUMERIC,
    p_gas_used BIGINT,
    p_status tx_status,
    p_transaction_type VARCHAR(50),
    p_chain_id INTEGER,
    p_metadata JSONB
) RETURNS SETOF transactions AS $$ 
LANGUAGE plpgsql
AS $$ 
BEGIN 
    RETURN QUERY 
    INSERT INTO transactions (
        tx_id,
        wallet_id,
        asset_id,
        tx_hash,
        block_number,
        from_address,
        to_address,
        amount,
        fee,
        gas_price,
        gas_used,
        status,
        transaction_type,
        chain_id,
        metadata
    )
    VALUES (
        uuid_generate_v4(),
        p_wallet_id,
        p_asset_id,
        p_tx_hash,
        p_block_number,
        p_from,
        p_to,
        p_amount,
        p_fee,
        p_gas_price,
        p_gas_used,
        p_status,
        p_transaction_type,
        p_chain_id,
        p_metadata
    )
    RETURNING *;
END;
$$;

-- Function to update balance on transaction confirmation
CREATE OR REPLACE FUNCTION update_balance_on_tx() RETURNS TRIGGER AS $$
BEGIN
    IF NEW.status = 'confirmed' THEN
        IF NEW.from_address IS NOT NULL AND NEW.from_address != '' THEN
            -- Deduct from sender
            UPDATE balances
            SET balance = balance - NEW.amount - NEW.fee,
                last_updated = NOW()
            WHERE wallet_id = NEW.wallet_id AND asset_id = NEW.asset_id;
        END IF;
        
        IF NEW.to_address IS NOT NULL AND NEW.to_address != '' THEN
            -- Add to recipient
            INSERT INTO balances (wallet_id, asset_id, balance, last_updated)
            VALUES (NEW.wallet_id, NEW.asset_id, NEW.amount, NOW())
            ON CONFLICT (wallet_id, asset_id) DO UPDATE
            SET balance = balances.balance + NEW.amount,
                last_updated = NOW();
        END IF;
        
        -- Handle NFT transfers
        IF NEW.asset_id IS NOT NULL AND (SELECT a.is_nft FROM assets a WHERE a.asset_id = NEW.asset_id) THEN
            IF NEW.to_address IS NOT NULL AND NEW.to_address != '' THEN
                INSERT INTO nft_tokens (token_id, collection_id, token_index, owner_address)
                VALUES (
                    NEW.tx_hash || '-' || (SELECT COALESCE(MAX(token_index) + 1, 0) FROM nft_tokens WHERE collection_id = (SELECT nft_collections.collection_id FROM assets a JOIN nft_collections n ON a.asset_id = n.asset_id WHERE a.asset_id = NEW.asset_id)),
                    (SELECT nft_collections.collection_id FROM assets a JOIN nft_collections n ON a.asset_id = n.asset_id WHERE a.asset_id = NEW.asset_id),
                    0,
                    NEW.to_address
                )
                ON CONFLICT (token_id, owner_address) DO NOTHING;
            END IF;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_update_balance
AFTER INSERT OR UPDATE ON transactions
FOR EACH ROW EXECUTE FUNCTION update_balance_on_tx();

-- Function to add liquidity to a pool
CREATE OR REPLACE FUNCTION add_liquidity_to_pool(
    p_pool_id UUID,
    p_token_a_id UUID,
    p_token_b_id UUID,
    p_amount_a NUMERIC,
    p_amount_b NUMERIC,
    p_slip_tolerance NUMERIC DEFAULT 0.01
) RETURNS SETOF liquidity_pools AS $$ 
LANGUAGE plpgsql
AS $$ 
BEGIN 
    -- Check if pool exists
    IF NOT EXISTS (
        SELECT 1 FROM liquidity_pools WHERE pool_id = p_pool_id
    ) THEN 
        RETURN QUERY 
        INSERT INTO liquidity_pools (
            pool_id,
            name,
            description,
            token_a_id,
            token_b_id,
            total_liquidity,
            reserve_a,
            reserve_b
        )
        VALUES (
            p_pool_id,
            'Auto-generated Pool ' || p_pool_id,
            'Automatically created liquidity pool',
            p_token_a_id,
            p_token_b_id,
            p_amount_a + p_amount_b,
            p_amount_a,
            p_amount_b
        );
    END IF;
    
    -- Update pool reserves
    UPDATE liquidity_pools
    SET 
        reserve_a = reserve_a + p_amount_a,
        reserve_b = reserve_b + p_amount_b,
        total_liquidity = total_liquidity + p_amount_a + p_amount_b,
        updated_at = NOW()
    WHERE pool_id = p_pool_id;
    
    RETURN QUERY 
    SELECT * FROM liquidity_pools WHERE pool_id = p_pool_id;
END;
$$;

-- Function to remove liquidity from a pool
CREATE OR REPLACE FUNCTION remove_liquidity_from_pool(
    p_pool_id UUID,
    p_token_a_id UUID,
    p_token_b_id UUID,
    p_amount_a NUMERIC,
    p_amount_b NUMERIC,
    p_slip_tolerance NUMERIC DEFAULT 0.01
) RETURNS SETOF liquidity_pools AS $$ 
LANGUAGE plpgsql
AS $$ 
BEGIN 
    -- Check if pool exists
    IF NOT EXISTS (
        SELECT 1 FROM liquidity_pools WHERE pool_id = p_pool_id AND 
            (token_a_id = p_token_a_id AND token_b_id = p_token_b_id) OR 
            (token_a_id = p_token_b_id AND token_b_id = p_token_a_id)
    ) THEN 
        RAISE EXCEPTION 'Pool does not exist or tokens do not match';
    END IF;
    
    -- Update pool reserves
    UPDATE liquidity_pools
    SET 
        reserve_a = reserve_a - p_amount_a,
        reserve_b = reserve_b - p_amount_b,
        total_liquidity = total_liquidity - p_amount_a - p_amount_b,
        updated_at = NOW()
    WHERE pool_id = p_pool_id;
    
    RETURN QUERY 
    SELECT * FROM liquidity_pools WHERE pool_id = p_pool_id;
END;
$$;

-- Function to get pool token prices
CREATE OR REPLACE FUNCTION get_pool_token_prices(p_pool_id UUID) RETURNS TABLE (
    token_a_price NUMERIC,
    token_b_price NUMERIC,
    reserve_a NUMERIC,
    reserve_b NUMERIC,
    total_liquidity NUMERIC
) AS $$ 
LANGUAGE plpgsql
AS $$ 
BEGIN 
    RETURN QUERY 
    SELECT 
        COALESCE(p.price_usd, 0) * COALESCE(a.decimals, 1) AS token_a_price,
        COALESCE(p.price_usd, 0) * COALESCE(b.decimals, 1) AS token_b_price,
        lp.reserve_a,
        lp.reserve_b,
        lp.total_liquidity
    FROM liquidity_pools lp
    JOIN assets a ON lp.token_a_id = a.asset_id
    JOIN assets b ON lp.token_b_id = b.asset_id
    JOIN price_feed p ON (p.token_id = a.asset_id OR p.token_id = b.asset_id)
    WHERE lp.pool_id = p_pool_id;
END;
$$;

-- Indexes for DeFi operations
CREATE INDEX IF NOT EXISTS idx_pools_pool ON liquidity_pools(pool_id);
CREATE INDEX IF NOT EXISTS idx_pools_tokens ON liquidity_pools(token_a_id, token_b_id);
CREATE INDEX IF NOT EXISTS idx_pools_reserves ON liquidity_pools(reserve_a, reserve_b);

-- Audit Logs for Security and Compliance
CREATE TABLE IF NOT EXISTS audit_logs (
    log_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    action_type VARCHAR(50) NOT NULL,
    entity_type VARCHAR(50) NOT NULL,
    entity_id UUID,
    old_value JSONB,
    new_value JSONB,
    ip_address VARCHAR(45),
    user_agent TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB
);

-- Function to log an audit event
CREATE OR REPLACE FUNCTION log_audit_event(
    p_user_id UUID,
    p_action_type VARCHAR(50),
    p_entity_type VARCHAR(50),
    p_entity_id UUID,
    p_old_value JSONB,
    p_new_value JSONB,
    p_ip_address VARCHAR(45),
    p_user_agent TEXT,
    p_metadata JSONB
) RETURNS SETOF audit_logs AS $$ 
LANGUAGE plpgsql
AS $$ 
BEGIN 
    INSERT INTO audit_logs (
        user_id,
        action_type,
        entity_type,
        entity_id,
        old_value,
        new_value,
        ip_address,
        user_agent,
        metadata
    )
    VALUES (
        p_user_id,
        p_action_type,
        p_entity_type,
        p_entity_id,
        p_old_value,
        p_new_value,
        p_ip_address,
        p_user_agent,
        p_metadata
    );
    RETURN QUERY SELECT * FROM audit_logs WHERE log_id = (SELECT MAX(log_id) FROM audit_logs);
END;
$$;

-- Function to trigger audit log on sensitive operations
CREATE OR REPLACE FUNCTION trigger_audit_on_operation() RETURNS TRIGGER AS $$ 
BEGIN 
    IF NEW.status = 'confirmed' THEN 
        -- Audit wallet transactions
        IF NEW.transaction_type IN ('transfer','swap','stake','unstake') THEN 
            INSERT INTO audit_logs (
                user_id,
                action_type,
                entity_type,
                entity_id,
                old_value,
                new_value,
                ip_address,
                user_agent,
                metadata
            )
            VALUES (
                (SELECT u.id FROM wallets w JOIN users u ON w.user_id = u.id WHERE w.wallet_id = NEW.wallet_id),
                'transaction_processed',
                'wallet_transaction',
                NEW.tx_id,
                JSONB_BUILD_OBJECT('amount', NEW.amount, 'fee', NEW.fee),
                JSONB_BUILD_OBJECT('amount', NEW.amount, 'fee', NEW.fee),
                NULL,
                NULL,
                JSONB_BUILD_OBJECT('tx_hash', NEW.tx_hash, 'block_number', NEW.block_number)
            );
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_audit_transaction
AFTER INSERT OR UPDATE ON transactions
FOR EACH ROW EXECUTE FUNCTION trigger_audit_on_operation();