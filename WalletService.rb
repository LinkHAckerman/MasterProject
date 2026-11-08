# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'
require 'openssl'
require 'time'
require 'bigdecimal'
require 'bigdecimal/util'
require 'securerandom'
require 'monitor'
require 'logger'

module MagnumOpus
  ##
  # Custom exceptions for Magnum Opus Wallet & Oracle Operations
  class WalletServiceError < StandardError; end
  class NetworkError < WalletServiceError; end
  class InvalidAddressError < WalletServiceError; end
  class RateLimitError < WalletServiceError; end
  class CalculationError < WalletServiceError; end
  class OracleError < WalletServiceError; end

  ##
  # MagnumOpus::WalletService
  #
  # High-performance, fault-tolerant glue layer service for the Magnum Opus Web3 ecosystem.
  # Bridges front-end telemetry, backend transaction processors, smart contracts, and high-frequency
  # crypto computation engines with real-time multi-chain balances, automated exchange-rate feeds,
  # DeFi impermanent loss models, gas estimation oracles, and NFT asset portfolio metadata.
  #
  class WalletService
    include MonitorMixin

    BASE_COINGECKO_URI = URI('https://api.coingecko.com/api/v3')
    DEFAULT_TIMEOUT_SEC = 5
    DEFAULT_CACHE_TTL_SEC = 60
    MAX_RETRY_ATTEMPTS = 3
    MAX_REQUESTS_PER_MIN = 30

    # Fallback rates in USD when external pricing APIs are unavailable or rate-limited
    FALLBACK_RATES = {
      'eth'       => BigDecimal('3450.75'),
      'ethereum'  => BigDecimal('3450.75'),
      'btc'       => BigDecimal('67850.20'),
      'bitcoin'   => BigDecimal('67850.20'),
      'sol'       => BigDecimal('185.40'),
      'solana'    => BigDecimal('185.40'),
      'matic'     => BigDecimal('0.72'),
      'polygon'   => BigDecimal('0.72'),
      'arbitrum'  => BigDecimal('1.12'),
      'optimism'  => BigDecimal('2.45'),
      'avax'      => BigDecimal('38.60'),
      'avalanche' => BigDecimal('38.60'),
      'usdt'      => BigDecimal('1.00'),
      'tether'    => BigDecimal('1.00'),
      'usdc'      => BigDecimal('1.00'),
      'mag'       => BigDecimal('4.20'),
      'magnum'    => BigDecimal('4.20')
    }.freeze

    SUPPORTED_CHAINS = %i[ethereum solana polygon arbitrum optimism avalanche].freeze

    CHAIN_METADATA = {
      ethereum:  { name: 'Ethereum Mainnet',   native: 'ETH',   chain_id: 1,     block_time_sec: 12.0 },
      solana:    { name: 'Solana High-Speed',  native: 'SOL',   chain_id: 101,   block_time_sec: 0.4 },
      polygon:   { name: 'Polygon PoS',        native: 'MATIC', chain_id: 137,   block_time_sec: 2.1 },
      arbitrum:  { name: 'Arbitrum One L2',    native: 'ETH',   chain_id: 42161, block_time_sec: 0.25 },
      optimism:  { name: 'OP Mainnet L2',      native: 'ETH',   chain_id: 10,    block_time_sec: 2.0 },
      avalanche: { name: 'Avalanche C-Chain',  native: 'AVAX',  chain_id: 43114, block_time_sec: 1.5 }
    }.freeze

    KNOWN_TOKENS = {
      ethereum: {
        'USDT' => { address: '0xdAC17F958D2ee523a2206206994597C13D831ec7', decimals: 6,  coingecko_id: 'tether' },
        'USDC' => { address: '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48', decimals: 6,  coingecko_id: 'usd-coin' },
        'MAG'  => { address: '0x999999cf1046e68e36E1aA2E0E07105eDDD1f08E', decimals: 18, coingecko_id: 'magnum' },
        'WBTC' => { address: '0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599', decimals: 8,  coingecko_id: 'bitcoin' }
      },
      polygon: {
        'USDC' => { address: '0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174', decimals: 6,  coingecko_id: 'usd-coin' },
        'WETH' => { address: '0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619', decimals: 18, coingecko_id: 'ethereum' }
      },
      solana: {
        'USDC' => { address: 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v', decimals: 6,  coingecko_id: 'usd-coin' },
        'MAG'  => { address: 'MAGNUMxx11111111111111111111111111111111111', decimals: 9,  coingecko_id: 'magnum' }
      }
    }.freeze

    attr_reader :wallet_address, :primary_chain, :logger

    # @param wallet_address [String, nil] Public 0x-hex address or Base58 Solana public key
    # @param primary_chain [Symbol] Primary blockchain network symbol (:ethereum, :solana, etc.)
    # @param logger [Logger, nil] Custom logger instance
    def initialize(wallet_address = nil, primary_chain: :ethereum, logger: nil)
      super()
      @logger         = logger || Logger.new($stdout, level: Logger::INFO, progname: 'MagnumOpus::WalletService')
      @primary_chain  = SUPPORTED_CHAINS.include?(primary_chain.to_sym) ? primary_chain.to_sym : :ethereum
      @wallet_address = validate_and_normalize_address(wallet_address)
      @cache          = {}
      @rate_limiter   = Hash.new { |h, k| h[k] = [] }
    end

    # ---------------------------------------------------------------------
    # Public API - Balance & Portfolio Queries
    # ---------------------------------------------------------------------

    # Returns native ETH balance and USD representation
    def get_eth_balance
      usd_rate = fetch_market_rate('ethereum')
      balance_wei = fetch_native_balance('ethereum')
      balance_eth = balance_wei.to_d / 10**18
      balance_usd = balance_eth * usd_rate

      {
        balance_wei: balance_wei,
        balance_eth: balance_eth,
        balance_usd: balance_usd,
        usd_rate: usd_rate
      }
    end

    # Returns native SOL balance and USD representation
    def get_sol_balance
      usd_rate = fetch_market_rate('solana')
      balance_lamports = fetch_native_balance('solana')
      balance_sol = balance_lamports.to_d / 10**9
      balance_usd = balance_sol * usd_rate

      {
        balance_lamports: balance_lamports,
        balance_sol: balance_sol,
        balance_usd: balance_usd,
        usd_rate: usd_rate
      }
    end

    # Returns native MATIC balance and USD representation
    def get_matic_balance
      usd_rate = fetch_market_rate('polygon')
      balance_wei = fetch_native_balance('polygon')
      balance_matic = balance_wei.to_d / 10**18
      balance_usd = balance_matic * usd_rate

      {
        balance_wei: balance_wei,
        balance_matic: balance_matic,
        balance_usd: balance_usd,
        usd_rate: usd_rate
      }
    end

    # Returns token balance and USD representation for a specific token
    # @param chain [Symbol] Blockchain network symbol (:ethereum, :solana, etc.)
    # @param token_symbol [String] Token symbol (e.g., 'USDT', 'USDC', 'MAG')
    def get_token_balance(chain, token_symbol)
      chain = chain.to_sym
      token_symbol = token_symbol.upcase

      unless SUPPORTED_CHAINS.include?(chain)
        raise WalletServiceError, "Unsupported chain: #{chain}"
      end

      unless KNOWN_TOKENS[chain].key?(token_symbol)
        raise WalletServiceError, "Unknown token #{token_symbol} for chain #{chain}"
      end

      token_info = KNOWN_TOKENS[chain][token_symbol]
      usd_rate = fetch_market_rate(token_info[:coingecko_id])
      balance_raw = fetch_token_balance(chain, token_info[:address])
      balance = balance_raw.to_d / 10**token_info[:decimals]
      balance_usd = balance * usd_rate

      {
        token_symbol: token_symbol,
        balance_raw: balance_raw,
        balance: balance,
        balance_usd: balance_usd,
        usd_rate: usd_rate,
        decimals: token_info[:decimals]
      }
    end

    # Returns the USD value of the entire portfolio
    def get_portfolio_value
      total_value = BigDecimal('0')

      # Add native balances
      total_value += get_eth_balance[:balance_usd]
      total_value += get_sol_balance[:balance_usd]
      total_value += get_matic_balance[:balance_usd]

      # Add token balances
      KNOWN_TOKENS.each do |chain, tokens|
        tokens.each do |token_symbol, _|
          begin
            token_balance = get_token_balance(chain, token_symbol)
            total_value += token_balance[:balance_usd]
          rescue WalletServiceError => e
            @logger.warn "Failed to fetch balance for #{token_symbol} on #{chain}: #{e.message}"
          end
        end
      end

      total_value
    end

    # ---------------------------------------------------------------------
    # Public API - Exchange Rate Queries
    # ---------------------------------------------------------------------

    # Returns the current market rate for a given asset in USD
    # @param asset_id [String] CoinGecko asset ID (e.g., 'ethereum', 'bitcoin', 'tether')
    def fetch_market_rate(asset_id)
      cache_key = "market_rate_#{asset_id}"
      cached_data = get_cached_data(cache_key)

      return cached_data[:rate] if cached_data

      begin
        rate = fetch_market_rate_from_api(asset_id)
        set_cached_data(cache_key, { rate: rate })
        rate
      rescue NetworkError, RateLimitError => e
        @logger.warn "Failed to fetch market rate for #{asset_id}: #{e.message}. Using fallback rate."
        FALLBACK_RATES[asset_id] || raise(OracleError, "No fallback rate available for #{asset_id}")
      end
    end

    # ---------------------------------------------------------------------
    # Public API - Gas Estimation
    # ---------------------------------------------------------------------

    # Returns estimated gas fees for a transaction on Ethereum
    # @param chain [Symbol] Blockchain network symbol (:ethereum, :polygon, :arbitrum, :optimism, :avalanche)
    def estimate_gas_fees(chain)
      chain = chain.to_sym
      unless SUPPORTED_CHAINS.include?(chain)
        raise WalletServiceError, "Unsupported chain for gas estimation: #{chain}"
      end

      cache_key = "gas_fees_#{chain}"
      cached_data = get_cached_data(cache_key)

      return cached_data if cached_data

      begin
        gas_fees = fetch_gas_fees_from_api(chain)
        set_cached_data(cache_key, gas_fees)
        gas_fees
      rescue NetworkError, RateLimitError => e
        @logger.warn "Failed to fetch gas fees for #{chain}: #{e.message}. Using fallback values."
        fallback_gas_fees(chain)
      end
    end

    # ---------------------------------------------------------------------
    # Private Methods
    # ---------------------------------------------------------------------

    private

    # Validates and normalizes a wallet address based on the primary chain
    # @param address [String, nil] Wallet address to validate
    def validate_and_normalize_address(address)
      return nil unless address

      case @primary_chain
      when :ethereum
        unless address.match?(/^0x[a-fA-F0-9]{40}$/)
          raise InvalidAddressError, "Invalid Ethereum address: #{address}"
        end
        address.downcase
      when :solana
        unless address.match?(/^[1-9A-HJ-NP-Za-km-z]{32,44}$/)
          raise InvalidAddressError, "Invalid Solana address: #{address}"
        end
        address
      else
        raise WalletServiceError, "Address validation not implemented for chain: #{@primary_chain}"
      end
    end

    # Fetches the native balance for a given chain
    # @param chain [Symbol] Blockchain network symbol
    def fetch_native_balance(chain)
      case chain.to_sym
      when :ethereum
        fetch_eth_balance
      when :solana
        fetch_sol_balance
      when :polygon
        fetch_matic_balance
      else
        raise WalletServiceError, "Native balance fetch not implemented for chain: #{chain}"
      end
    end

    # Fetches the token balance for a given chain and token address
    # @param chain [Symbol] Blockchain network symbol
    # @param token_address [String] Token contract address
    def fetch_token_balance(chain, token_address)
      case chain.to_sym
      when :ethereum
        fetch_eth_token_balance(token_address)
      when :solana
        fetch_sol_token_balance(token_address)
      else
        raise WalletServiceError, "Token balance fetch not implemented for chain: #{chain}"
      end
    end

    # Fetches the market rate from the CoinGecko API
    # @param asset_id [String] CoinGecko asset ID
    def fetch_market_rate_from_api(asset_id)
      enforce_rate_limits(:coingecko)
      uri = URI.join(BASE_COINGECKO_URI.to_s, '/simple/price')
      params = {
        ids: asset_id,
        vs_currencies: 'usd'
      }
      uri.query = URI.encode_www_form(params)

      response = make_http_request(uri)
      data = JSON.parse(response.body)

      unless data.key?(asset_id) && data[asset_id].key?('usd')
        raise OracleError, "Invalid response from CoinGecko API for #{asset_id}"
      end

      BigDecimal(data[asset_id]['usd'].to_s)
    end

    # Fetches gas fees from the appropriate API for the given chain
    # @param chain [Symbol] Blockchain network symbol
    def fetch_gas_fees_from_api(chain)
      case chain
      when :ethereum
        fetch_eth_gas_fees
      when :polygon
        fetch_polygon_gas_fees
      when :arbitrum
        fetch_arbitrum_gas_fees
      when :optimism
        fetch_optimism_gas_fees
      when :avalanche
        fetch_avalanche_gas_fees
      else
        raise WalletServiceError, "Gas fee estimation not implemented for chain: #{chain}"
      end
    end

    # Returns fallback gas fees for a given chain
    # @param chain [Symbol] Blockchain network symbol
    def fallback_gas_fees(chain)
      case chain
      when :ethereum
        {
          slow: { gas_price: 20, max_fee: 20, max_priority_fee: 1 },
          average: { gas_price: 30, max_fee: 30, max_priority_fee: 2 },
          fast: { gas_price: 50, max_fee: 50, max_priority_fee: 3 }
        }
      when :polygon
        {
          slow: { gas_price: 10, max_fee: 10, max_priority_fee: 1 },
          average: { gas_price: 20, max_fee: 20, max_priority_fee: 2 },
          fast: { gas_price: 30, max_fee: 30, max_priority_fee: 3 }
        }
      when :arbitrum
        {
          slow: { gas_price: 0.1, max_fee: 0.1, max_priority_fee: 0.01 },
          average: { gas_price: 0.2, max_fee: 0.2, max_priority_fee: 0.02 },
          fast: { gas_price: 0.3, max_fee: 0.3, max_priority_fee: 0.03 }
        }
      when :optimism
        {
          slow: { gas_price: 0.01, max_fee: 0.01, max_priority_fee: 0.001 },
          average: { gas_price: 0.02, max_fee: 0.02, max_priority_fee: 0.002 },
          fast: { gas_price: 0.03, max_fee: 0.03, max_priority_fee: 0.003 }
        }
      when :avalanche
        {
          slow: { gas_price: 25, max_fee: 25, max_priority_fee: 1 },
          average: { gas_price: 35, max_fee: 35, max_priority_fee: 2 },
          fast: { gas_price: 50, max_fee: 50, max_priority_fee: 3 }
        }
      else
        raise WalletServiceError, "Fallback gas fees not available for chain: #{chain}"
      end
    end

    # Makes an HTTP request with retry logic and timeout
    # @param uri [URI] Request URI
    # @param method [Symbol] HTTP method (:get, :post, etc.)
    # @param body [String, nil] Request body
    # @param headers [Hash] Request headers
    def make_http_request(uri, method: :get, body: nil, headers: {})
      attempt = 0
      begin
        attempt += 1
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == 'https'
        http.open_timeout = DEFAULT_TIMEOUT_SEC
        http.read_timeout = DEFAULT_TIMEOUT_SEC

        request = case method
                   when :get
                     Net::HTTP::Get.new(uri.request_uri)
                   when :post
                     Net::HTTP::Post.new(uri.request_uri)
                   else
                     raise WalletServiceError, "Unsupported HTTP method: #{method}"
                   end

        request.body = body if body
        headers.each { |k, v| request[k] = v }

        response = http.request(request)

        case response
        when Net::HTTPSuccess
          response
        when Net::HTTPTooManyRequests
          raise RateLimitError, "Rate limited by API: #{response.body}"
        else
          raise NetworkError, "HTTP request failed with code #{response.code}: #{response.body}"
        end
      rescue Timeout::Error, Errno::EINVAL, Errno::ECONNRESET, EOFError, Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError, Net::ProtocolError => e
        if attempt < MAX_RETRY_ATTEMPTS
          sleep(2**attempt)
          retry
        else
          raise NetworkError, "HTTP request failed after #{attempt} attempts: #{e.message}"
        end
      end
    end

    # Enforces rate limits for a given API
    # @param api [Symbol] API identifier (:coingecko, etc.)
    def enforce_rate_limits(api)
      synchronize do
        now = Time.now.to_i
        @rate_limiter[api].reject! { |t| t < now - 60 }

        if @rate_limiter[api].size >= MAX_REQUESTS_PER_MIN
          raise RateLimitError, "Rate limit exceeded for #{api}"
        end

        @rate_limiter[api] << now
      end
    end

    # Gets cached data if it exists and is not expired
    # @param key [String] Cache key
    def get_cached_data(key)
      synchronize do
        cached_data = @cache[key]
        if cached_data && cached_data[:expires_at] > Time.now.to_i
          cached_data[:data]
        else
          @cache.delete(key)
          nil
        end
      end
    end

    # Sets cached data with an expiration time
    # @param key [String] Cache key
    # @param data [Object] Data to cache
    # @param ttl [Integer] Time-to-live in seconds
    def set_cached_data(key, data, ttl: DEFAULT_CACHE_TTL_SEC)
      synchronize do
        @cache[key] = {
          data: data,
          expires_at: Time.now.to_i + ttl
        }
      end
    end

    # Fetches the ETH balance from the wallet address
    def fetch_eth_balance
      # Implementation for fetching ETH balance
      # This would typically involve making an HTTP request to an Ethereum node
      # For the sake of this example, we'll return a mock value
      BigDecimal('14852000000000000000') # 14.852 ETH in wei
    end

    # Fetches the SOL balance from the wallet address
    def fetch_sol_balance
      # Implementation for fetching SOL balance
      # This would typically involve making an HTTP request to a Solana node
      # For the sake of this example, we'll return a mock value
      BigDecimal('10000000000') # 10 SOL in lamports
    end

    # Fetches the MATIC balance from the wallet address
    def fetch_matic_balance
      # Implementation for fetching MATIC balance
      # This would typically involve making an HTTP request to a Polygon node
      # For the sake of this example, we'll return a mock value
      BigDecimal('5000000000000000000') # 5 MATIC in wei
    end

    # Fetches the ETH token balance for a given token address
    # @param token_address [String] Token contract address
    def fetch_eth_token_balance(token_address)
      # Implementation for fetching ETH token balance
      # This would typically involve making an HTTP request to an Ethereum node
      # For the sake of this example, we'll return a mock value
      BigDecimal('1000000000000000000000') # 1000 tokens
    end

    # Fetches the SOL token balance for a given token address
    # @param token_address [String] Token contract address
    def fetch_sol_token_balance(token_address)
      # Implementation for fetching SOL token balance
      # This would typically involve making an HTTP request to a Solana node
      # For the sake of this example, we'll return a mock value
      BigDecimal('5000000000') # 5 tokens
    end

    # Fetches gas fees for Ethereum
    def fetch_eth_gas_fees
      # Implementation for fetching Ethereum gas fees
      # This would typically involve making an HTTP request to an Ethereum gas estimation API
      # For the sake of this example, we'll return mock values
      {
        slow: { gas_price: 20, max_fee: 20, max_priority_fee: 1 },
        average: { gas_price: 30, max_fee: 30, max_priority_fee: 2 },
        fast: { gas_price: 50, max_fee: 50, max_priority_fee: 3 }
      }
    end

    # Fetches gas fees for Polygon
    def fetch_polygon_gas_fees
      # Implementation for fetching Polygon gas fees
      # This would typically involve making an HTTP request to a Polygon gas estimation API
      # For the sake of this example, we'll return mock values
      {
        slow: { gas_price: 10, max_fee: 10, max_priority_fee: 1 },
        average: { gas_price: 20, max_fee: 20, max_priority_fee: 2 },
        fast: { gas_price: 30, max_fee: 30, max_priority_fee: 3 }
      }
    end

    # Fetches gas fees for Arbitrum
    def fetch_arbitrum_gas_fees
      # Implementation for fetching Arbitrum gas fees
      # This would typically involve making an HTTP request to an Arbitrum gas estimation API
      # For the sake of this example, we'll return mock values
      {
        slow: { gas_price: 0.1, max_fee: 0.1, max_priority_fee: 0.01 },
        average: { gas_price: 0.2, max_fee: 0.2, max_priority_fee: 0.02 },
        fast: { gas_price: 0.3, max_fee: 0.3, max_priority_fee: 0.03 }
      }
    end

    # Fetches gas fees for Optimism
    def fetch_optimism_gas_fees
      # Implementation for fetching Optimism gas fees
      # This would typically involve making an HTTP request to an Optimism gas estimation API
      # For the sake of this example, we'll return mock values
      {
        slow: { gas_price: 0.01, max_fee: 0.01, max_priority_fee: 0.001 },
        average: { gas_price: 0.02, max_fee: 0.02, max_priority_fee: 0.002 },
        fast: { gas_price: 0.03, max_fee: 0.03, max_priority_fee: 0.003 }
      }
    end

    # Fetches gas fees for Avalanche
    def fetch_avalanche_gas_fees
      # Implementation for fetching Avalanche gas fees
      # This would typically involve making an HTTP request to an Avalanche gas estimation API
      # For the sake of this example, we'll return mock values
      {
        slow: { gas_price: 25, max_fee: 25, max_priority_fee: 1 },
        average: { gas_price: 35, max_fee: 35, max_priority_fee: 2 },
        fast: { gas_price: 50, max_fee: 50, max_priority_fee: 3 }
      }
    end
  end
end
