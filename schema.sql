-- Magnum Opus schema for PostgreSQL
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE users (
	id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
	email VARCHAR(255) NOT NULL UNIQUE,
	password_hash VARCHAR(255) NOT NULL,
	created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
	updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

CREATE TABLE wallets (
	id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
	user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
	address VARCHAR(42) NOT NULL UNIQUE,
	blockchain VARCHAR(32) NOT NULL,
	label VARCHAR(100),
	created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
	updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

CREATE TABLE tokens (
	id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
	symbol VARCHAR(10) NOT NULL,
	name VARCHAR(100) NOT NULL,
	decimals SMALLINT NOT NULL,
	contract_address VARCHAR(42) NOT NULL,
	blockchain VARCHAR(32) NOT NULL,
	UNIQUE (blockchain, contract_address)
);

CREATE TABLE wallet_balances (
	wallet_id UUID NOT NULL REFERENCES wallets(id) ON DELETE CASCADE,
	token_id UUID NOT NULL REFERENCES tokens(id) ON DELETE CASCADE,
	balance NUMERIC(78,0) NOT NULL DEFAULT 0,
	last_updated TIMESTAMP WITH TIME ZONE DEFAULT now(),
	PRIMARY KEY (wallet_id, token_id)
);

CREATE TABLE transactions (
	id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
	wallet_id UUID NOT NULL REFERENCES wallets(id) ON DELETE CASCADE,
	token_id UUID NOT NULL REFERENCES tokens(id) ON DELETE CASCADE,
	tx_hash VARCHAR(66) NOT NULL UNIQUE,
	block_number BIGINT NOT NULL,
	amount NUMERIC(78,0) NOT NULL,
	direction VARCHAR(4) NOT NULL CHECK (direction IN ('IN','OUT')),
	status VARCHAR(12) NOT NULL CHECK (status IN ('PENDING','CONFIRMED','FAILED')),
	created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
	confirmed_at TIMESTAMP WITH TIME ZONE
);

CREATE INDEX idx_tx_wallet ON transactions(wallet_id);
CREATE INDEX idx_tx_token ON transactions(token_id);
CREATE INDEX idx_tx_block ON transactions(block_number);

-- Auditing table for price snapshots
CREATE TABLE price_snapshots (
	id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
	token_id UUID NOT NULL REFERENCES tokens(id) ON DELETE CASCADE,
	price_usd NUMERIC(38,18) NOT NULL,
	source VARCHAR(50) NOT NULL,
	captured_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Views for portfolio aggregation
CREATE VIEW user_portfolio AS
SELECT
	u.id AS user_id,
	t.symbol,
	t.name,
	SUM(wb.balance) AS total_balance,
	ps.price_usd,
	(SUM(wb.balance) * ps.price_usd) AS usd_value
FROM users u
JOIN wallets w ON w.user_id = u.id
JOIN wallet_balances wb ON wb.wallet_id = w.id
JOIN tokens t ON t.id = wb.token_id
LEFT JOIN LATERAL (
	SELECT price_usd
	FROM price_snapshots ps
	WHERE ps.token_id = t.id
	ORDER BY ps.captured_at DESC
	LIMIT 1
) ps ON true
GROUP BY u.id, t.id, ps.price_usd;

-- Functions for updating balances atomically
CREATE OR REPLACE FUNCTION adjust_wallet_balance(p_wallet_id UUID, p_token_id UUID, p_amount NUMERIC, p_direction VARCHAR)
RETURNS VOID AS $$
BEGIN
	IF p_direction = 'IN' THEN
		INSERT INTO wallet_balances (wallet_id, token_id, balance, last_updated)
		VALUES (p_wallet_id, p_token_id, p_amount, now())
		ON CONFLICT (wallet_id, token_id) DO UPDATE
		SET balance = wallet_balances.balance + p_amount,
		    last_updated = now();
	ELSIF p_direction = 'OUT' THEN
		UPDATE wallet_balances
		SET balance = balance - p_amount,
		    last_updated = now()
		WHERE wallet_id = p_wallet_id AND token_id = p_token_id
		AND balance >= p_amount;
		IF NOT FOUND THEN
			RAISE EXCEPTION 'Insufficient balance for wallet % token %', p_wallet_id, p_token_id;
		END IF;
	ELSE
		RAISE EXCEPTION 'Invalid direction %', p_direction;
	END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Sample data
INSERT INTO users (email, password_hash) VALUES
('alice@example.com', crypt('alicepwd', gen_salt('bf'))),
('bob@example.com', crypt('bobpwd', gen_salt('bf')));

INSERT INTO tokens (symbol, name, decimals, contract_address, blockchain) VALUES
('ETH', 'Ethereum', 18, '0x0000000000000000000000000000000000000000', 'Ethereum'),
('USDT', 'Tether USD', 6, '0xdAC17F958D2ee523a2206206994597C13D831ec7', 'Ethereum'),
('SOL', 'Solana', 9, 'So11111111111111111111111111111111111111112', 'Solana');

-- Create wallets for sample users
INSERT INTO wallets (user_id, address, blockchain, label)
SELECT id, '0x' || substr(md5(random()::text),1,40), 'Ethereum', 'Main Wallet'
FROM users WHERE email='alice@example.com';

INSERT INTO wallets (user_id, address, blockchain, label)
SELECT id, '0x' || substr(md5(random()::text),1,40), 'Ethereum', 'Main Wallet'
FROM users WHERE email='bob@example.com';