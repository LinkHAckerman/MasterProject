-- Schema para Magnum Opus: Base de datos completa para usuarios, wallets, transacciones, NFTs y DeFi

-- Tabla de usuarios
CREATE TABLE users (
    id INT PRIMARY KEY AUTO_INCREMENT,
    username VARCHAR(50) UNIQUE,
    email VARCHAR(100) UNIQUE,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Tabla de wallets
CREATE TABLE wallets (
    id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT,
    address VARCHAR(255) UNIQUE,
    private_key TEXT,
    public_key TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id)
);

-- Tabla de transacciones
CREATE TABLE transactions (
    id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT,
    tx_hash VARCHAR(255) UNIQUE,
    amount DECIMAL(18, 8),
    token VARCHAR(50),
    status ENUM('pending', 'confirmed', 'failed'),
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id)
);

-- Tabla de NFTs
CREATE TABLE nfts (
    id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT,
    token_id VARCHAR(255) UNIQUE,
    contract_address VARCHAR(255),
    metadata JSON,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id)
);

-- Tabla de posiciones DeFi
CREATE TABLE defi_positions (
    id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT,
    pool_id VARCHAR(255),
    amount DECIMAL(18, 8),
    apy DECIMAL(5, 2),
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id)
);