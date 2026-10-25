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
    transaction_type VARCHAR(50) CHECK (transaction_type IN ('transfer','swap','stake','unstake','mint','burn','approve','deposit','withdraw','liquidity_add','liquidity_remove','borrow','repay','claim_reward','vote','execute_order','create_collection','transfer_nft')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB
);

CREATE TRIGGER trg_transactions_updated_at
BEFORE UPDATE ON transactions
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_transactions_wallet_id ON transactions(wallet_id);
CREATE INDEX IF NOT EXISTS idx_transactions_asset_id ON transactions(asset_id);
CREATE INDEX IF NOT EXISTS idx_transactions_tx_hash ON transactions(tx_hash);
CREATE INDEX IF NOT EXISTS idx_transactions_status ON transactions(status);
CREATE INDEX IF NOT EXISTS idx_transactions_created_at ON transactions(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_balances_wallet_asset ON balances(wallet_id, asset_id);
CREATE INDEX IF NOT EXISTS idx_assets_network ON assets(network);
CREATE INDEX IF NOT EXISTS idx_assets_contract_address ON assets(contract_address);
CREATE INDEX IF NOT EXISTS idx_nft_tokens_owner ON nft_tokens(owner_address);
CREATE INDEX IF NOT EXISTS idx_nft_tokens_collection ON nft_tokens(collection_id);

-- DeFi Protocols and Liquidity Pools
CREATE TABLE IF NOT EXISTS defi_protocols (
    protocol_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(100) NOT NULL,
    symbol VARCHAR(20),
    network VARCHAR(30) NOT NULL,
    contract_address VARCHAR(42) NOT NULL,
    protocol_type VARCHAR(50) CHECK (protocol_type IN ('dex','lending','yield','derivatives','insurance','staking','bridge','launchpad')),
    tvl NUMERIC(38,18),
    apy NUMERIC(10,4),
    risk_level VARCHAR(20) CHECK (risk_level IN ('low','medium','high')),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESHAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB,
    CONSTRAINT chk_defi_network CHECK (network IN ('Ethereum','Polygon','BinanceSmartChain','Solana','Avalanche','PolygonZK','Arbitrum','Optimism','Base','Mantle'))
);

CREATE TRIGGER trg_defi_protocols_updated_at
BEFORE UPDATE ON defi_protocols
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- Liquidity Pools
CREATE TABLE IF NOT EXISTS liquidity_pools (
    pool_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    protocol_id UUID NOT NULL REFERENCES defi_protocols(protocol_id) ON DELETE CASCADE,
    token0_asset_id UUID NOT NULL REFERENCES assets(asset_id),
    token1_asset_id UUID NOT NULL REFERENCES assets(asset_id),
    reserve0 NUMERIC(38,18) NOT NULL DEFAULT 0,
    reserve1 NUMERIC(38,18) NOT NULL DEFAULT 0,
    fee_tier NUMERIC(10,6) NOT NULL DEFAULT 0.003,
    total_lp_tokens NUMERIC(38,18) NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB,
    UNIQUE (protocol_id, token0_asset_id, token1_asset_id)
);

CREATE TRIGGER trg_liquidity_pools_updated_at
BEFORE UPDATE ON liquidity_pools
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- Staking Positions
CREATE TABLE IF NOT EXISTS staking_positions (
    position_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    wallet_id UUID NOT NULL REFERENCES wallets(wallet_id) ON DELETE CASCADE,
    asset_id UUID NOT NULL REFERENCES assets(asset_id),
    protocol_id UUID REFERENCES defi_protocols(protocol_id) ON DELETE SET NULL,
    amount_staked NUMERIC(38,18) NOT NULL,
    rewards_earned NUMERIC(38,18) NOT NULL DEFAULT 0,
    rewards_claimed NUMERIC(38,18) NOT NULL DEFAULT 0,
    start_time TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lock_until TIMESTAMPTZ,
    is_compounding BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB
);

CREATE TRIGGER trg_staking_positions_updated_at
BEFORE UPDATE ON staking_positions
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- Trading Orders
CREATE TABLE IF NOT EXISTS trading_orders (
    order_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    wallet_id UUID NOT NULL REFERENCES wallets(wallet_id) ON DELETE CASCADE,
    protocol_id UUID REFERENCES defi_protocols(protocol_id) ON DELETE SET NULL,
    base_asset_id UUID NOT NULL REFERENCES assets(asset_id),
    quote_asset_id UUID NOT NULL REFERENCES assets(asset_id),
    order_type VARCHAR(20) CHECK (order_type IN ('limit','market','stop_limit','stop_market')),
    side VARCHAR(10) CHECK (side IN ('buy','sell')),
    price NUMERIC(38,18),
    amount NUMERIC(38,18) NOT NULL,
    filled_amount NUMERIC(38,18) NOT NULL DEFAULT 0,
    remaining_amount NUMERIC(38,18) GENERATED ALWAYS AS (amount - filled_amount) STORED,
    status VARCHAR(20) CHECK (status IN ('open','partially_filled','filled','cancelled','expired')) NOT NULL DEFAULT 'open',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ,
    metadata JSONB
);

CREATE TRIGGER trg_trading_orders_updated_at
BEFORE UPDATE ON trading_orders
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- Order Fills
CREATE TABLE IF NOT EXISTS order_fills (
    fill_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id UUID NOT NULL REFERENCES trading_orders(order_id) ON DELETE CASCADE,
    matched_order_id UUID REFERENCES trading_orders(order_id) ON DELETE SET NULL,
    fill_price NUMERIC(38,18) NOT NULL,
    fill_amount NUMERIC(38,18) NOT NULL,
    fee NUMERIC(38,18) NOT NULL,
    fee_asset_id UUID REFERENCES assets(asset_id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB
);

CREATE TRIGGER trg_order_fills_updated_at
BEFORE UPDATE ON order_fills
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- Price Feeds and Market Data
CREATE TABLE IF NOT EXISTS price_feeds (
    feed_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    asset_id UUID NOT NULL REFERENCES assets(asset_id),
    price NUMERIC(38,18) NOT NULL,
    price_change_24h NUMERIC(20,8),
    volume_24h NUMERIC(38,18),
    market_cap NUMERIC(38,18),
    circulating_supply NUMERIC(38,18),
    total_supply NUMERIC(38,18),
    source VARCHAR(50),
    confidence_interval NUMERIC(20,8),
    timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB
);

CREATE INDEX IF NOT EXISTS idx_price_feeds_asset_id ON price_feeds(asset_id);
CREATE INDEX IF NOT EXISTS idx_price_feeds_timestamp ON price_feeds(timestamp DESC);

-- User Portfolio Snapshots
CREATE TABLE IF NOT EXISTS portfolio_snapshots (
    snapshot_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    wallet_id UUID NOT NULL REFERENCES wallets(wallet_id) ON DELETE CASCADE,
    total_value_usd NUMERIC(38,18) NOT NULL,
    asset_breakdown JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_portfolio_snapshots_wallet_id ON portfolio_snapshots(wallet_id);
CREATE INDEX IF NOT EXISTS idx_portfolio_snapshots_created_at ON portfolio_snapshots(created_at DESC);

-- API Keys and Authentication
CREATE TABLE IF NOT EXISTS api_keys (
    key_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    api_key_hash VARCHAR(255) NOT NULL UNIQUE,
    permissions JSONB,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ,
    last_used_at TIMESTAMPTZ,
    metadata JSONB
);

CREATE INDEX IF NOT EXISTS idx_api_keys_user_id ON api_keys(user_id);
CREATE INDEX IF NOT EXISTS idx_api_keys_is_active ON api_keys(is_active);

-- Audit Logs
CREATE TABLE IF NOT EXISTS audit_logs (
    log_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    action VARCHAR(100) NOT NULL,
    resource_type VARCHAR(50),
    resource_id UUID,
    ip_address INET,
    user_agent TEXT,
    success BOOLEAN NOT NULL,
    error_message TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB
);

CREATE INDEX IF NOT EXISTS idx_audit_logs_user_id ON audit_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_action ON audit_logs(action);
CREATE INDEX IF NOT EXISTS idx_audit_logs_created_at ON audit_logs(created_at DESC);

-- Notifications
CREATE TABLE IF NOT EXISTS notifications (
    notification_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title VARCHAR(255) NOT NULL,
    message TEXT,
    notification_type VARCHAR(50) CHECK (notification_type IN ('alert','info','success','warning','transaction','market')),
    is_read BOOLEAN NOT NULL DEFAULT FALSE,
    priority VARCHAR(20) CHECK (priority IN ('low','medium','high','critical')) NOT NULL DEFAULT 'medium',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    read_at TIMESTAMPTZ,
    metadata JSONB
);

CREATE INDEX IF NOT EXISTS idx_notifications_user_id ON notifications(user_id);
CREATE INDEX IF NOT EXISTS idx_notifications_is_read ON notifications(is_read);
CREATE INDEX IF NOT EXISTS idx_notifications_created_at ON notifications(created_at DESC);

-- Bridge Transactions
CREATE TABLE IF NOT EXISTS bridge_transactions (
    bridge_tx_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    wallet_id UUID NOT NULL REFERENCES wallets(wallet_id) ON DELETE CASCADE,
    source_network VARCHAR(30) NOT NULL,
    destination_network VARCHAR(30) NOT NULL,
    source_asset_id UUID NOT NULL REFERENCES assets(asset_id),
    destination_asset_id UUID NOT NULL REFERENCES assets(asset_id),
    amount_sent NUMERIC(38,18) NOT NULL,
    amount_received NUMERIC(38,18),
    fee NUMERIC(38,18),
    bridge_provider VARCHAR(100),
    status VARCHAR(20) CHECK (status IN ('pending','processing','completed','failed','refunded')) NOT NULL DEFAULT 'pending',
    source_tx_hash VARCHAR(66),
    destination_tx_hash VARCHAR(66),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB,
    CONSTRAINT chk_bridge_networks CHECK (source_network IN ('Ethereum','Polygon','BinanceSmartChain','Solana','Avalanche','PolygonZK','Arbitrum','Optimism','Base','Mantle') AND destination_network IN ('Ethereum','Polygon','BinanceSmartChain','Solana','Avalanche','PolygonZK','Arbitrum','Optimism','Base','Mantle'))
);

CREATE TRIGGER trg_bridge_transactions_updated_at
BEFORE UPDATE ON bridge_transactions
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

CREATE INDEX IF NOT EXISTS idx_bridge_transactions_wallet_id ON bridge_transactions(wallet_id);
CREATE INDEX IF NOT EXISTS idx_bridge_transactions_status ON bridge_transactions(status);

-- Governance Proposals and Votes
CREATE TABLE IF NOT EXISTS governance_proposals (
    proposal_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    title VARCHAR(255) NOT NULL,
    description TEXT,
    proposer_wallet_id UUID NOT NULL REFERENCES wallets(wallet_id),
    protocol_id UUID REFERENCES defi_protocols(protocol_id) ON DELETE SET NULL,
    start_time TIMESTAMPTZ NOT NULL,
    end_time TIMESTAMPTZ NOT NULL,
    for_votes NUMERIC(38,18) NOT NULL DEFAULT 0,
    against_votes NUMERIC(38,18) NOT NULL DEFAULT 0,
    abstain_votes NUMERIC(38,18) NOT NULL DEFAULT 0,
    quorum NUMERIC(10,4),
    status VARCHAR(20) CHECK (status IN ('active','succeeded','defeated','executed','cancelled')) NOT NULL DEFAULT 'active',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB
);

CREATE TRIGGER trg_governance_proposals_updated_at
BEFORE UPDATE ON governance_proposals
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

CREATE TABLE IF NOT EXISTS governance_votes (
    vote_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    proposal_id UUID NOT NULL REFERENCES governance_proposals(proposal_id) ON DELETE CASCADE,
    voter_wallet_id UUID NOT NULL REFERENCES wallets(wallet_id),
    vote_choice VARCHAR(10) CHECK (vote_choice IN ('for','against','abstain')) NOT NULL,
    voting_power NUMERIC(38,18) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB,
    UNIQUE (proposal_id, voter_wallet_id)
);

CREATE INDEX IF NOT EXISTS idx_governance_votes_proposal_id ON governance_votes(proposal_id);
CREATE INDEX IF NOT EXISTS idx_governance_votes_voter_wallet_id ON governance_votes(voter_wallet_id);

-- Yield Farming Positions
CREATE TABLE IF NOT EXISTS yield_farms (
    farm_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    protocol_id UUID NOT NULL REFERENCES defi_protocols(protocol_id) ON DELETE CASCADE,
    reward_asset_id UUID NOT NULL REFERENCES assets(asset_id),
    staking_asset_id UUID NOT NULL REFERENCES assets(asset_id),
    alloc_point NUMERIC(20,8) NOT NULL,
    apr NUMERIC(10,4),
    apy NUMERIC(10,4),
    tvl NUMERIC(38,18),
    start_time TIMESTAMPTZ,
    end_time TIMESTAMPTZ,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB
);

CREATE TRIGGER trg_yield_farms_updated_at
BEFORE UPDATE ON yield_farms
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

CREATE TABLE IF NOT EXISTS yield_farm_positions (
    position_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    farm_id UUID NOT NULL REFERENCES yield_farms(farm_id) ON DELETE CASCADE,
    wallet_id UUID NOT NULL REFERENCES wallets(wallet_id) ON DELETE CASCADE,
    amount_deposited NUMERIC(38,18) NOT NULL,
    rewards_earned NUMERIC(38,18) NOT NULL DEFAULT 0,
    rewards_claimed NUMERIC(38,18) NOT NULL DEFAULT 0,
    deposit_time TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_harvest_time TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB
);

CREATE TRIGGER trg_yield_farm_positions_updated_at
BEFORE UPDATE ON yield_farm_positions
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

CREATE INDEX IF NOT EXISTS idx_yield_farm_positions_wallet_id ON yield_farm_positions(wallet_id);
CREATE INDEX IF NOT EXISTS idx_yield_farm_positions_farm_id ON yield_farm_positions(farm_id);

-- Lending Positions
CREATE TABLE IF NOT EXISTS lending_positions (
    position_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    wallet_id UUID NOT NULL REFERENCES wallets(wallet_id) ON DELETE CASCADE,
    protocol_id UUID NOT NULL REFERENCES defi_protocols(protocol_id),
    asset_id UUID NOT NULL REFERENCES assets(asset_id),
    position_type VARCHAR(10) CHECK (position_type IN ('deposit','borrow')) NOT NULL,
    amount NUMERIC(38,18) NOT NULL,
    interest_rate NUMERIC(10,6),
    collateral_factor NUMERIC(10,6),
    health_factor NUMERIC(20,8),
    liquidation_threshold NUMERIC(10,6),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB
);

CREATE TRIGGER trg_lending_positions_updated_at
BEFORE UPDATE ON lending_positions
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

CREATE INDEX IF NOT EXISTS idx_lending_positions_wallet_id ON lending_positions(wallet_id);
CREATE INDEX IF NOT EXISTS idx_lending_positions_protocol_id ON lending_positions(protocol_id);

-- Insurance Policies
CREATE TABLE IF NOT EXISTS insurance_policies (
    policy_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    wallet_id UUID NOT NULL REFERENCES wallets(wallet_id) ON DELETE CASCADE,
    protocol_id UUID NOT NULL REFERENCES defi_protocols(protocol_id),
    asset_id UUID NOT NULL REFERENCES assets(asset_id),
    coverage_amount NUMERIC(38,18) NOT NULL,
    premium NUMERIC(38,18) NOT NULL,
    start_time TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    end_time TIMESTAMPTZ NOT NULL,
    status VARCHAR(20) CHECK (status IN ('active','expired','claimed','cancelled')) NOT NULL DEFAULT 'active',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB
);

CREATE TRIGGER trg_insurance_policies_updated_at
BEFORE UPDATE ON insurance_policies
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

CREATE INDEX IF NOT EXISTS idx_insurance_policies_wallet_id ON insurance_policies(wallet_id);
CREATE INDEX IF NOT EXISTS idx_insurance_policies_status ON insurance_policies(status);

-- Token Approvals
CREATE TABLE IF NOT EXISTS token_approvals (
    approval_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    wallet_id UUID NOT NULL REFERENCES wallets(wallet_id) ON DELETE CASCADE,
    asset_id UUID NOT NULL REFERENCES assets(asset_id),
    spender_address VARCHAR(42) NOT NULL,
    amount_allowed NUMERIC(38,18) NOT NULL,
    amount_used NUMERIC(38,18) NOT NULL DEFAULT 0,
    expires_at TIMESTAMPTZ,
    is_revoked BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB,
    UNIQUE (wallet_id, asset_id, spender_address)
);

CREATE TRIGGER trg_token_approvals_updated_at
BEFORE UPDATE ON token_approvals
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

CREATE INDEX IF NOT EXISTS idx_token_approvals_wallet_id ON token_approvals(wallet_id);
CREATE INDEX IF NOT EXISTS idx_token_approvals_spender_address ON token_approvals(spender_address);

-- Multi-signature Wallet Support
CREATE TABLE IF NOT EXISTS multisig_wallets (
    multisig_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(100),
    network VARCHAR(30) NOT NULL,
    address VARCHAR(42) NOT NULL UNIQUE,
    required_signatures SMALLINT NOT NULL,
    total_owners SMALLINT NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB,
    CONSTRAINT chk_multisig_network CHECK (network IN ('Ethereum','Polygon','BinanceSmartChain','Solana','Avalanche','PolygonZK','Arbitrum','Optimism','Base','Mantle'))
);

CREATE TRIGGER trg_multisig_wallets_updated_at
BEFORE UPDATE ON multisig_wallets
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

CREATE TABLE IF NOT EXISTS multisig_members (
    member_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    multisig_id UUID NOT NULL REFERENCES multisig_wallets(multisig_id) ON DELETE CASCADE,
    wallet_id UUID NOT NULL REFERENCES wallets(wallet_id) ON DELETE CASCADE,
    added_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    metadata JSONB,
    UNIQUE (multisig_id, wallet_id)
);

CREATE INDEX IF NOT EXISTS idx_multisig_members_multisig_id ON multisig_members(multisig_id);
CREATE INDEX IF NOT EXISTS idx_multisig_members_wallet_id ON multisig_members(wallet_id);

-- Transaction History Views
CREATE OR REPLACE VIEW v_wallet_balances AS
SELECT
    w.wallet_id,
    w.address,
    w.network,
    a.asset_id,
    a.symbol,
    a.name,
    a.decimals,
    b.balance,
    b.is_locked,
    b.last_updated
FROM wallets w
JOIN balances b ON w.wallet_id = b.wallet_id
JOIN assets a ON b.asset_id = a.asset_id;

CREATE OR REPLACE VIEW v_user_portfolios AS
SELECT
    u.id as user_id,
    u.email,
    w.wallet_id,
    w.address,
    w.network,
    SUM(pf.price * b.balance / POWER(10, a.decimals)) as total_value_usd,
    COUNT(DISTINCT a.asset_id) as asset_count
FROM users u
JOIN wallets w ON u.id = w.user_id
JOIN balances b ON w.wallet_id = b.wallet_id
JOIN assets a ON b.asset_id = a.asset_id
LEFT JOIN price_feeds pf ON a.asset_id = pf.asset_id AND pf.timestamp = (
    SELECT MAX(timestamp) FROM price_feeds pf2 WHERE pf2.asset_id = a.asset_id
)
WHERE w.is_active = TRUE AND b.balance > 0
GROUP BY u.id, u.email, w.wallet_id, w.address, w.network;

-- Functions
CREATE OR REPLACE FUNCTION get_wallet_balance(p_wallet_id UUID, p_asset_id UUID)
RETURNS NUMERIC(38,18) AS $$
DECLARE
    v_balance NUMERIC(38,18);
BEGIN
    SELECT balance INTO v_balance
    FROM balances
    WHERE wallet_id = p_wallet_id AND asset_id = p_asset_id;
    
    RETURN COALESCE(v_balance, 0);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION update_wallet_balance(p_wallet_id UUID, p_asset_id UUID, p_amount NUMERIC(38,18))
RETURNS VOID AS $$
BEGIN
    INSERT INTO balances (wallet_id, asset_id, balance, last_updated)
    VALUES (p_wallet_id, p_asset_id, p_amount, NOW())
    ON CONFLICT (wallet_id, asset_id) 
    DO UPDATE SET balance = EXCLUDED.balance, last_updated = NOW();
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION record_transaction(
    p_wallet_id UUID,
    p_asset_id UUID,
    p_tx_hash VARCHAR(66),
    p_from_address VARCHAR(42),
    p_to_address VARCHAR(42),
    p_amount NUMERIC(38,18),
    p_fee NUMERIC(38,18),
    p_gas_price NUMERIC(38,18),
    p_gas_used BIGINT,
    p_transaction_type VARCHAR(50),
    p_status tx_status DEFAULT 'pending'
) RETURNS UUID AS $$
DECLARE
    v_tx_id UUID;
BEGIN
    INSERT INTO transactions (
        tx_id, wallet_id, asset_id, tx_hash, from_address, to_address,
        amount, fee, gas_price, gas_used, transaction_type, status
    ) VALUES (
        uuid_generate_v4(), p_wallet_id, p_asset_id, p_tx_hash, p_from_address, p_to_address,
        p_amount, p_fee, p_gas_price, p_gas_used, p_transaction_type, p_status
    ) RETURNING tx_id INTO v_tx_id;
    
    RETURN v_tx_id;
END;
$$ LANGUAGE plpgsql;

-- Trigger function for updated_at columns
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;