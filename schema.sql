-- ============================================================================
-- MAGNUM OPUS // Multi-Chain DeFi, NFT & Web3 Nexus Platform
-- PostgreSQL Production Schema Definition
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================================
-- 1. Enumerations & Custom Domain Types
-- ============================================================================

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'tx_status') THEN
        CREATE TYPE tx_status AS ENUM ('pending', 'submitted', 'confirmed', 'failed', 'reverted', 'dropped');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'tx_type') THEN
        CREATE TYPE tx_type AS ENUM (
            'transfer', 'swap', 'stake', 'unstake', 'deposit', 'withdraw',
            'mint', 'burn', 'liquidation', 'bridge', 'borrow', 'repay', 'claim_rewards'
        );
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'order_side') THEN
        CREATE TYPE order_side AS ENUM ('buy', 'sell');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'order_type') THEN
        CREATE TYPE order_type AS ENUM ('limit', 'market', 'stop_loss', 'take_profit');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'order_status') THEN
        CREATE TYPE order_status AS ENUM ('open', 'filled', 'partially_filled', 'cancelled', 'expired');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'position_status') THEN
        CREATE TYPE position_status AS ENUM ('active', 'closed', 'liquidated');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'lending_action') THEN
        CREATE TYPE lending_action AS ENUM ('supply', 'borrow', 'repay', 'withdraw', 'liquidate');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'proposal_status') THEN
        CREATE TYPE proposal_status AS ENUM ('draft', 'active', 'succeeded', 'defeated', 'executed', 'cancelled');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'bridge_status') THEN
        CREATE TYPE bridge_status AS ENUM ('initiated', 'pending_lock', 'verified', 'completed', 'failed', 'refunded');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'nft_rarity') THEN
        CREATE TYPE nft_rarity AS ENUM ('common', 'uncommon', 'rare', 'epic', 'legendary', 'mythic');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'pool_status') THEN
        CREATE TYPE pool_status AS ENUM ('active', 'paused', 'retired');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'vote_power') THEN
        CREATE TYPE vote_power AS ENUM ('yes', 'no', 'abstain');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'chain_family') THEN
        CREATE TYPE chain_family AS ENUM ('evm', 'solana', 'bitcoin', 'substrate', 'cosmos');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'auction_type') THEN
        CREATE TYPE auction_type AS ENUM ('fixed_price', 'english_auction', 'dutch_auction');
    END IF;
END $$;

-- ============================================================================
-- 2. Core Stored Procedures & Trigger Functions
-- ============================================================================

CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION generate_tx_id()
RETURNS VARCHAR AS $$
BEGIN
    RETURN 'TX-' || UPPER(SUBSTRING(MD5(CAST(NOW() AS TEXT) || CAST(RANDOM() AS TEXT)) FROM 1 FOR 16));
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- 3. Core Users, Authentication & Sessions
-- ============================================================================

CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email VARCHAR(255) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    full_name VARCHAR(255),
    status VARCHAR(20) NOT NULL DEFAULT 'active',
    is_verified BOOLEAN NOT NULL DEFAULT FALSE,
    verification_token VARCHAR(255),
    verification_expires TIMESTAMPTZ,
    two_factor_enabled BOOLEAN NOT NULL DEFAULT FALSE,
    two_factor_secret VARCHAR(255),
    backup_codes TEXT[],
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'::jsonb,
    CONSTRAINT chk_user_status CHECK (status IN ('active', 'suspended', 'deleted', 'verified'))
);

DROP TRIGGER IF EXISTS trg_users_updated_at ON users;
CREATE TRIGGER trg_users_updated_at
BEFORE UPDATE ON users
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

CREATE TABLE IF NOT EXISTS user_sessions (
    session_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash VARCHAR(255) NOT NULL UNIQUE,
    ip_address INET,
    user_agent TEXT,
    is_revoked BOOLEAN NOT NULL DEFAULT FALSE,
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_sessions_user_id ON user_sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_sessions_token_hash ON user_sessions(token_hash);

CREATE TABLE IF NOT EXISTS api_keys (
    key_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    key_name VARCHAR(100) NOT NULL,
    api_key VARCHAR(64) NOT NULL UNIQUE,
    api_secret_hash VARCHAR(255) NOT NULL,
    permissions JSONB NOT NULL DEFAULT '["read"]'::jsonb,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_api_keys_lookup ON api_keys(api_key, is_active);

-- ============================================================================
-- 4. Multi-Chain Network Registry
-- ============================================================================

CREATE TABLE IF NOT EXISTS chains (
    chain_id BIGINT PRIMARY KEY,
    chain_name VARCHAR(100) NOT NULL UNIQUE,
    network_type VARCHAR(20) NOT NULL DEFAULT 'mainnet',
    family chain_family NOT NULL DEFAULT 'evm',
    native_symbol VARCHAR(20) NOT NULL,
    rpc_endpoint_primary TEXT NOT NULL,
    rpc_endpoint_fallback TEXT,
    block_explorer_url TEXT,
    ws_endpoint TEXT,
    confirmation_blocks INT NOT NULL DEFAULT 12,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

DROP TRIGGER IF EXISTS trg_chains_updated_at ON chains;
CREATE TRIGGER trg_chains_updated_at
BEFORE UPDATE ON chains
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- ============================================================================
-- 5. Multi-Chain Wallets & Web3 SIWE (Sign-In with Ethereum/Solana)
-- ============================================================================

CREATE TABLE IF NOT EXISTS wallets (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    chain_id BIGINT NOT NULL REFERENCES chains(chain_id),
    public_address VARCHAR(128) NOT NULL,
    wallet_type VARCHAR(32) NOT NULL DEFAULT 'metamask',
    is_primary BOOLEAN NOT NULL DEFAULT FALSE,
    derivation_path VARCHAR(64),
    auth_nonce VARCHAR(64) NOT NULL DEFAULT encode(gen_random_bytes(16), 'hex'),
    nonce_expires_at TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '15 minutes'),
    last_active_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_chain_address UNIQUE (chain_id, public_address)
);
CREATE INDEX IF NOT EXISTS idx_wallets_user ON wallets(user_id);
CREATE INDEX IF NOT EXISTS idx_wallets_address ON wallets(public_address);

DROP TRIGGER IF EXISTS trg_wallets_updated_at ON wallets;
CREATE TRIGGER trg_wallets_updated_at
BEFORE UPDATE ON wallets
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- ============================================================================
-- 6. Asset & Smart Contract Registry
-- ============================================================================

CREATE TABLE IF NOT EXISTS tokens (
    token_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    chain_id BIGINT NOT NULL REFERENCES chains(chain_id),
    contract_address VARCHAR(128) NOT NULL,
    symbol VARCHAR(32) NOT NULL,
    name VARCHAR(128) NOT NULL,
    decimals INT NOT NULL DEFAULT 18,
    total_supply NUMERIC(78, 0) NOT NULL DEFAULT 0,
    is_native BOOLEAN NOT NULL DEFAULT FALSE,
    is_governance BOOLEAN NOT NULL DEFAULT FALSE,
    coingecko_id VARCHAR(100),
    logo_uri TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_chain_token UNIQUE (chain_id, contract_address)
);
CREATE INDEX IF NOT EXISTS idx_tokens_symbol ON tokens(symbol);
CREATE INDEX IF NOT EXISTS idx_tokens_chain ON tokens(chain_id);

CREATE TABLE IF NOT EXISTS wallet_balances (
    wallet_id UUID NOT NULL REFERENCES wallets(id) ON DELETE CASCADE,
    token_id UUID NOT NULL REFERENCES tokens(token_id) ON DELETE CASCADE,
    balance NUMERIC(78, 18) NOT NULL DEFAULT 0 CHECK (balance >= 0),
    locked_balance NUMERIC(78, 18) NOT NULL DEFAULT 0 CHECK (locked_balance >= 0),
    last_synced_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (wallet_id, token_id)
);
CREATE INDEX IF NOT EXISTS idx_balances_wallet ON wallet_balances(wallet_id);

-- ============================================================================
-- 7. Multi-Chain Ledger & Transaction Registry
-- ============================================================================

CREATE TABLE IF NOT EXISTS transactions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tx_identifier VARCHAR(64) NOT NULL UNIQUE DEFAULT generate_tx_id(),
    chain_id BIGINT NOT NULL REFERENCES chains(chain_id),
    tx_hash VARCHAR(128) NOT NULL,
    block_number BIGINT,
    block_hash VARCHAR(128),
    sender_address VARCHAR(128) NOT NULL,
    receiver_address VARCHAR(128) NOT NULL,
    token_id UUID REFERENCES tokens(token_id),
    amount NUMERIC(78, 18) NOT NULL DEFAULT 0,
    gas_price_gwei NUMERIC(36, 9) DEFAULT 0,
    gas_limit BIGINT,
    gas_used BIGINT,
    total_fee NUMERIC(78, 18) DEFAULT 0,
    nonce BIGINT,
    tx_type tx_type NOT NULL DEFAULT 'transfer',
    status tx_status NOT NULL DEFAULT 'pending',
    raw_input TEXT,
    logs JSONB DEFAULT '[]'::jsonb,
    submitted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    mined_at TIMESTAMPTZ,
    CONSTRAINT uq_chain_tx_hash UNIQUE (chain_id, tx_hash)
);
CREATE INDEX IF NOT EXISTS idx_transactions_sender ON transactions(sender_address);
CREATE INDEX IF NOT EXISTS idx_transactions_receiver ON transactions(receiver_address);
CREATE INDEX IF NOT EXISTS idx_transactions_status ON transactions(status);
CREATE INDEX IF NOT EXISTS idx_transactions_chain_block ON transactions(chain_id, block_number DESC);

-- ============================================================================
-- 8. High-Performance AMM & Liquidity Pools
-- ============================================================================

CREATE TABLE IF NOT EXISTS liquidity_pools (
    pool_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    chain_id BIGINT NOT NULL REFERENCES chains(chain_id),
    pool_address VARCHAR(128) NOT NULL UNIQUE,
    token0_id UUID NOT NULL REFERENCES tokens(token_id),
    token1_id UUID NOT NULL REFERENCES tokens(token_id),
    reserve0 NUMERIC(78, 18) NOT NULL DEFAULT 0 CHECK (reserve0 >= 0),
    reserve1 NUMERIC(78, 18) NOT NULL DEFAULT 0 CHECK (reserve1 >= 0),
    fee_tier_bps INT NOT NULL DEFAULT 30, -- 30 bps = 0.30%
    lp_token_id UUID REFERENCES tokens(token_id),
    total_lp_supply NUMERIC(78, 18) NOT NULL DEFAULT 0,
    volume_24h_usd NUMERIC(38, 4) DEFAULT 0,
    status pool_status NOT NULL DEFAULT 'active',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_pool_tokens_different CHECK (token0_id <> token1_id)
);
CREATE INDEX IF NOT EXISTS idx_lp_pair ON liquidity_pools(token0_id, token1_id);

CREATE TABLE IF NOT EXISTS liquidity_positions (
    position_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    pool_id UUID NOT NULL REFERENCES liquidity_pools(pool_id) ON DELETE CASCADE,
    wallet_id UUID NOT NULL REFERENCES wallets(id) ON DELETE CASCADE,
    lp_token_balance NUMERIC(78, 18) NOT NULL DEFAULT 0 CHECK (lp_token_balance >= 0),
    initial_deposit0 NUMERIC(78, 18) NOT NULL DEFAULT 0,
    initial_deposit1 NUMERIC(78, 18) NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_pool_wallet UNIQUE (pool_id, wallet_id)
);
CREATE INDEX IF NOT EXISTS idx_positions_wallet ON liquidity_positions(wallet_id);

-- ============================================================================
-- 9. Order Book DEX (Limit / Market Engine)
-- ============================================================================

CREATE TABLE IF NOT EXISTS dex_orderbook (
    order_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    chain_id BIGINT NOT NULL REFERENCES chains(chain_id),
    wallet_id UUID NOT NULL REFERENCES wallets(id) ON DELETE CASCADE,
    base_token_id UUID NOT NULL REFERENCES tokens(token_id),
    quote_token_id UUID NOT NULL REFERENCES tokens(token_id),
    side order_side NOT NULL,
    order_type order_type NOT NULL DEFAULT 'limit',
    price NUMERIC(38, 18) NOT NULL CHECK (price > 0),
    quantity NUMERIC(38, 18) NOT NULL CHECK (quantity > 0),
    filled_quantity NUMERIC(38, 18) NOT NULL DEFAULT 0 CHECK (filled_quantity >= 0),
    remaining_quantity NUMERIC(38, 18) GENERATED ALWAYS AS (quantity - filled_quantity) STORED,
    status order_status NOT NULL DEFAULT 'open',
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_order_tokens_diff CHECK (base_token_id <> quote_token_id),
    CONSTRAINT chk_order_fill_le_quantity CHECK (filled_quantity <= quantity)
);
CREATE INDEX IF NOT EXISTS idx_orderbook_match ON dex_orderbook(base_token_id, quote_token_id, side, price, created_at)
WHERE status = 'open';
CREATE INDEX IF NOT EXISTS idx_orderbook_wallet ON dex_orderbook(wallet_id);

CREATE TABLE IF NOT EXISTS dex_trades (
    trade_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    chain_id BIGINT NOT NULL REFERENCES chains(chain_id),
    maker_order_id UUID NOT NULL REFERENCES dex_orderbook(order_id),
    taker_order_id UUID NOT NULL REFERENCES dex_orderbook(order_id),
    price NUMERIC(38, 18) NOT NULL,
    amount NUMERIC(38, 18) NOT NULL,
    maker_fee NUMERIC(38, 18) DEFAULT 0,
    taker_fee NUMERIC(38, 18) DEFAULT 0,
    tx_hash VARCHAR(128),
    executed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_trades_executed_at ON dex_trades(executed_at DESC);

-- ============================================================================
-- 10. Lending & Borrowing Money Markets
-- ============================================================================

CREATE TABLE IF NOT EXISTS lending_markets (
    market_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    chain_id BIGINT NOT NULL REFERENCES chains(chain_id),
    asset_token_id UUID NOT NULL REFERENCES tokens(token_id),
    c_token_address VARCHAR(128) NOT NULL UNIQUE,
    collateral_factor NUMERIC(5, 4) NOT NULL DEFAULT 0.7500, -- e.g. 75% LTV
    liquidation_threshold NUMERIC(5, 4) NOT NULL DEFAULT 0.8000, -- 80%
    liquidation_bonus NUMERIC(5, 4) NOT NULL DEFAULT 0.0500, -- 5% penalty
    borrow_apr NUMERIC(8, 4) NOT NULL DEFAULT 0.0450,
    supply_apr NUMERIC(8, 4) NOT NULL DEFAULT 0.0250,
    total_supplied NUMERIC(78, 18) NOT NULL DEFAULT 0,
    total_borrowed NUMERIC(78, 18) NOT NULL DEFAULT 0,
    reserve_factor NUMERIC(5, 4) NOT NULL DEFAULT 0.1000,
    is_paused BOOLEAN NOT NULL DEFAULT FALSE,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS lending_positions (
    position_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    market_id UUID NOT NULL REFERENCES lending_markets(market_id) ON DELETE CASCADE,
    wallet_id UUID NOT NULL REFERENCES wallets(id) ON DELETE CASCADE,
    supplied_amount NUMERIC(78, 18) NOT NULL DEFAULT 0 CHECK (supplied_amount >= 0),
    borrowed_amount NUMERIC(78, 18) NOT NULL DEFAULT 0 CHECK (borrowed_amount >= 0),
    health_factor NUMERIC(10, 4) NOT NULL DEFAULT 999.0000,
    last_accrual_index NUMERIC(38, 18) DEFAULT 1.000000000000000000,
    status position_status NOT NULL DEFAULT 'active',
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_market_wallet UNIQUE (market_id, wallet_id)
);
CREATE INDEX IF NOT EXISTS idx_lending_health ON lending_positions(health_factor)
WHERE status = 'active' AND borrowed_amount > 0;

-- ============================================================================
-- 11. Staking & Yield Farming Vaults
-- ============================================================================

CREATE TABLE IF NOT EXISTS staking_pools (
    pool_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    chain_id BIGINT NOT NULL REFERENCES chains(chain_id),
    staking_contract_address VARCHAR(128) NOT NULL UNIQUE,
    stake_token_id UUID NOT NULL REFERENCES tokens(token_id),
    reward_token_id UUID NOT NULL REFERENCES tokens(token_id),
    reward_rate_per_sec NUMERIC(38, 18) NOT NULL DEFAULT 0,
    lock_duration_seconds BIGINT NOT NULL DEFAULT 0,
    total_staked NUMERIC(78, 18) NOT NULL DEFAULT 0,
    start_time TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    end_time TIMESTAMPTZ,
    status pool_status NOT NULL DEFAULT 'active',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS user_stakes (
    stake_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    pool_id UUID NOT NULL REFERENCES staking_pools(pool_id) ON DELETE CASCADE,
    wallet_id UUID NOT NULL REFERENCES wallets(id) ON DELETE CASCADE,
    staked_amount NUMERIC(78, 18) NOT NULL DEFAULT 0 CHECK (staked_amount >= 0),
    accumulated_rewards NUMERIC(78, 18) NOT NULL DEFAULT 0 CHECK (accumulated_rewards >= 0),
    reward_debt NUMERIC(78, 18) NOT NULL DEFAULT 0,
    locked_until TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_stake_pool_wallet UNIQUE (pool_id, wallet_id)
);

-- ============================================================================
-- 12. NFT Ecosystem & Marketplace
-- ============================================================================

CREATE TABLE IF NOT EXISTS nft_collections (
    collection_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    chain_id BIGINT NOT NULL REFERENCES chains(chain_id),
    contract_address VARCHAR(128) NOT NULL UNIQUE,
    creator_wallet_id UUID REFERENCES wallets(id),
    name VARCHAR(128) NOT NULL,
    symbol VARCHAR(32) NOT NULL,
    royalty_fee_bps INT NOT NULL DEFAULT 500, -- 500 bps = 5%
    royalty_recipient_address VARCHAR(128) NOT NULL,
    base_uri TEXT,
    total_items INT NOT NULL DEFAULT 0,
    floor_price_usd NUMERIC(24, 6) DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_nft_collections_chain ON nft_collections(chain_id);

CREATE TABLE IF NOT EXISTS nft_items (
    item_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    collection_id UUID NOT NULL REFERENCES nft_collections(collection_id) ON DELETE CASCADE,
    token_id NUMERIC(78, 0) NOT NULL,
    owner_wallet_id UUID NOT NULL REFERENCES wallets(id),
    title VARCHAR(255) NOT NULL,
    description TEXT,
    metadata_uri TEXT NOT NULL,
    image_url TEXT NOT NULL,
    rarity nft_rarity NOT NULL DEFAULT 'common',
    rarity_score NUMERIC(10, 4) DEFAULT 0,
    attributes JSONB DEFAULT '[]'::jsonb,
    is_listed BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_collection_token UNIQUE (collection_id, token_id)
);
CREATE INDEX IF NOT EXISTS idx_nft_items_owner ON nft_items(owner_wallet_id);
CREATE INDEX IF NOT EXISTS idx_nft_items_attributes ON nft_items USING gin(attributes);

CREATE TABLE IF NOT EXISTS nft_listings (
    listing_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    item_id UUID NOT NULL REFERENCES nft_items(item_id) ON DELETE CASCADE,
    seller_wallet_id UUID NOT NULL REFERENCES wallets(id),
    currency_token_id UUID NOT NULL REFERENCES tokens(token_id),
    price NUMERIC(78, 18) NOT NULL CHECK (price > 0),
    auction_type auction_type NOT NULL DEFAULT 'fixed_price',
    starting_price NUMERIC(78, 18),
    reserve_price NUMERIC(78, 18),
    highest_bid NUMERIC(78, 18) DEFAULT 0,
    highest_bidder_id UUID REFERENCES wallets(id),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_nft_listings_active ON nft_listings(item_id, is_active);

-- ============================================================================
-- 13. Cross-Chain Interoperability & Bridge Relay
-- ============================================================================

CREATE TABLE IF NOT EXISTS cross_chain_bridges (
    bridge_tx_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    source_chain_id BIGINT NOT NULL REFERENCES chains(chain_id),
    dest_chain_id BIGINT NOT NULL REFERENCES chains(chain_id),
    sender_wallet_id UUID NOT NULL REFERENCES wallets(id),
    recipient_address VARCHAR(128) NOT NULL,
    token_id UUID NOT NULL REFERENCES tokens(token_id),
    amount NUMERIC(78, 18) NOT NULL CHECK (amount > 0),
    relayer_fee NUMERIC(78, 18) NOT NULL DEFAULT 0,
    source_tx_hash VARCHAR(128) NOT NULL,
    dest_tx_hash VARCHAR(128),
    nonce BIGINT NOT NULL,
    validator_signatures JSONB DEFAULT '[]'::jsonb,
    required_signatures INT NOT NULL DEFAULT 3,
    status bridge_status NOT NULL DEFAULT 'initiated',
    initiated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at TIMESTAMPTZ,
    CONSTRAINT chk_bridge_chains_diff CHECK (source_chain_id <> dest_chain_id)
);
CREATE INDEX IF NOT EXISTS idx_bridge_status ON cross_chain_bridges(status);
CREATE INDEX IF NOT EXISTS idx_bridge_source_tx ON cross_chain_bridges(source_chain_id, source_tx_hash);

-- ============================================================================
-- 14. Decentralized Autonomous Organization (DAO) & Governance
-- ============================================================================

CREATE TABLE IF NOT EXISTS governance_proposals (
    proposal_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    chain_id BIGINT NOT NULL REFERENCES chains(chain_id),
    proposer_wallet_id UUID NOT NULL REFERENCES wallets(id),
    title VARCHAR(255) NOT NULL,
    description TEXT NOT NULL,
    target_contract VARCHAR(128),
    call_data TEXT,
    start_block BIGINT NOT NULL,
    end_block BIGINT NOT NULL,
    quorum_required NUMERIC(78, 18) NOT NULL,
    yes_votes NUMERIC(78, 18) NOT NULL DEFAULT 0,
    no_votes NUMERIC(78, 18) NOT NULL DEFAULT 0,
    abstain_votes NUMERIC(78, 18) NOT NULL DEFAULT 0,
    status proposal_status NOT NULL DEFAULT 'draft',
    execution_tx_hash VARCHAR(128),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_proposal_blocks CHECK (end_block > start_block)
);
CREATE INDEX IF NOT EXISTS idx_proposals_status ON governance_proposals(status);

CREATE TABLE IF NOT EXISTS governance_votes (
    vote_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    proposal_id UUID NOT NULL REFERENCES governance_proposals(proposal_id) ON DELETE CASCADE,
    voter_wallet_id UUID NOT NULL REFERENCES wallets(id),
    vote_option vote_power NOT NULL,
    voting_weight NUMERIC(78, 18) NOT NULL CHECK (voting_weight > 0),
    voted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_proposal_voter UNIQUE (proposal_id, voter_wallet_id)
);

-- ============================================================================
-- 15. Real-Time Price Oracles & Feed Snapshots
-- ============================================================================

CREATE TABLE IF NOT EXISTS price_feeds (
    feed_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    token_id UUID NOT NULL REFERENCES tokens(token_id) ON DELETE CASCADE,
    price_usd NUMERIC(38, 8) NOT NULL CHECK (price_usd >= 0),
    source_oracle VARCHAR(64) NOT NULL DEFAULT 'chainlink',
    confidence_score NUMERIC(5, 4) DEFAULT 0.9999,
    round_id BIGINT,
    fetched_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_price_feeds_token_time ON price_feeds(token_id, fetched_at DESC);

-- ============================================================================
-- 16. System Audit Logs & Microservice Relayer Metrics
-- ============================================================================

CREATE TABLE IF NOT EXISTS system_audit_logs (
    log_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    actor_id UUID REFERENCES users(id) ON DELETE SET NULL,
    action_type VARCHAR(100) NOT NULL,
    entity_name VARCHAR(100) NOT NULL,
    entity_id UUID,
    ip_address INET,
    details JSONB DEFAULT '{}'::jsonb,
    logged_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_audit_logs_actor ON system_audit_logs(actor_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_logged_at ON system_audit_logs(logged_at DESC);

-- ============================================================================
-- 17. High-Value Analytical Views
-- ============================================================================

CREATE OR REPLACE VIEW view_user_portfolio_summary AS
SELECT
    w.user_id,
    w.public_address,
    c.chain_name,
    t.symbol AS token_symbol,
    wb.balance AS token_balance,
    wb.locked_balance,
    COALESCE(pf.price_usd, 0) AS unit_price_usd,
    ROUND(wb.balance * COALESCE(pf.price_usd, 0), 2) AS estimated_usd_value
FROM wallets w
JOIN chains c ON w.chain_id = c.chain_id
JOIN wallet_balances wb ON w.id = wb.wallet_id
JOIN tokens t ON wb.token_id = t.token_id
LEFT JOIN LATERAL (
    SELECT price_usd
    FROM price_feeds
    WHERE token_id = t.token_id
    ORDER BY fetched_at DESC
    LIMIT 1
) pf ON TRUE;

CREATE OR REPLACE VIEW view_amm_pool_analytics AS
SELECT
    p.pool_id,
    c.chain_name,
    t0.symbol AS token0_symbol,
    t1.symbol AS token1_symbol,
    p.reserve0,
    p.reserve1,
    p.fee_tier_bps,
    p.volume_24h_usd,
    p.status
FROM liquidity_pools p
JOIN chains c ON p.chain_id = c.chain_id
JOIN tokens t0 ON p.token0_id = t0.token_id
JOIN tokens t1 ON p.token1_id = t1.token_id;
