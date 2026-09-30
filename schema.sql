CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE users (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  wallet_address VARCHAR(66) UNIQUE NOT NULL,
  email VARCHAR(255) UNIQUE,
  full_name VARCHAR(150),
  profile_data JSONB DEFAULT '{}',
  created_at TIMESTAMP DEFAULT NOW(),
  last_login TIMESTAMP DEFAULT NOW(),
  is_active BOOLEAN DEFAULT TRUE,
  referral_code VARCHAR(16) UNIQUE,
  referral_earnings NUMERIC(15, 8) DEFAULT 0
);

CREATE TABLE wallets (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  chain_id INTEGER NOT NULL,
  address VARCHAR(255) NOT NULL,
  label VARCHAR(100),
  is_primary BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(user_id, chain_id, address)
);

CREATE TABLE transactions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  wallet_id UUID REFERENCES wallets(id) ON DELETE CASCADE,
  tx_hash VARCHAR(66) UNIQUE NOT NULL,
  chain_id INTEGER NOT NULL,
  from_address VARCHAR(255),
  to_address VARCHAR(255),
  value NUMERIC(78, 18) NOT NULL,
  gas_price NUMERIC(78, 18),
  gas_limit INTEGER,
  status VARCHAR(50) DEFAULT 'pending',
  block_number BIGINT,
  timestamp TIMESTAMP DEFAULT NOW(),
  type VARCHAR(50) CHECK (type IN ('transfer', 'swap', 'mint', 'burn', 'deploy', 'staking', 'unstaking')),
  status_details JSONB DEFAULT '{}',
  log_index INTEGER
);

CREATE TABLE nfts (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  wallet_id UUID REFERENCES wallets(id) ON DELETE CASCADE,
  token_id VARCHAR(255) NOT NULL,
  contract_address VARCHAR(66) NOT NULL,
  chain_id INTEGER NOT NULL,
  name VARCHAR(255),
  symbol VARCHAR(50),
  token_uri TEXT,
  metadata JSONB DEFAULT '{}',
  collection_name VARCHAR(150),
  rarity_tier VARCHAR(20),
  created_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(wallet_id, contract_address, token_id)
);

CREATE TABLE defi_positions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  wallet_id UUID REFERENCES wallets(id) ON DELETE CASCADE,
  pair_id VARCHAR(100) NOT NULL,
  chain_id INTEGER NOT NULL,
  token_in_address VARCHAR(66) NOT NULL,
  token_out_address VARCHAR(66) NOT NULL,
  amount_in NUMERIC(78, 18) NOT NULL,
  amount_out NUMERIC(78, 18),
  liquidity NUMERIC(78, 18),
  apy NUMERIC(10, 4),
  fee_tier VARCHAR(20),
  status VARCHAR(50) DEFAULT 'active',
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE market_data (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  pair_id VARCHAR(50) NOT NULL,
  chain_id INTEGER NOT NULL,
  price NUMERIC(36, 18) NOT NULL,
  price_change_24h NUMERIC(15, 8),
  volume_24h NUMERIC(78, 18),
  high_24h NUMERIC(36, 18),
  low_24h NUMERIC(36, 18),
  timestamp TIMESTAMP DEFAULT NOW(),
  UNIQUE(pair_id, chain_id, timestamp)
);

CREATE INDEX idx_transactions_hash ON transactions(tx_hash);
CREATE INDEX idx_transactions_wallet ON transactions(wallet_id);
CREATE INDEX idx_transactions_timestamp ON transactions(timestamp);
CREATE INDEX idx_nfts_contract ON nfts(contract_address);
CREATE INDEX idx_nfts_wallet ON nfts(wallet_id);
CREATE INDEX idx_defi_positions_wallet ON defi_positions(wallet_id);
CREATE INDEX idx_defi_positions_apy ON defi_positions(apy DESC);
CREATE INDEX idx_market_data_pair_timestamp ON market_data(pair_id, timestamp DESC);
CREATE INDEX idx_users_referral ON users(referral_code);
