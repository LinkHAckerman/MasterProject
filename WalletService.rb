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
  # High‑performance, fault‑tolerant glue‑layer service for the Magnum Opus Web3 ecosystem.
  # Bridges front‑end telemetry, back‑end transaction processors, smart contracts, and
  # high‑frequency crypto computation engines with real‑time multi‑chain balances,
  # automated exchange‑rate feeds, DeFi impermanent‑loss models, gas‑estimation oracles,
  # and NFT asset‑portfolio metadata.
  #
  class WalletService
    include MonitorMixin

    # ---------------------------------------------------------------------
    # Configuration constants
    # ---------------------------------------------------------------------
    BASE_COINGECKO_URI    = URI('https://api.coingecko.com/api/v3')
    DEFAULT_TIMEOUT_SEC   = 5
    DEFAULT_CACHE_TTL_SEC = 60
    MAX_RETRY_ATTEMPTS    = 3
    MAX_REQUESTS_PER_MIN  = 30

    # Fallback rates in USD when external pricing APIs are unavailable or rate‑limited
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
      'bnb'       => BigDecimal('582.30'),
      'usdt'      => BigDecimal('1.00'),
      'tether'    => BigDecimal('1.00'),
      'usdc'      => BigDecimal('1.00'),
      'mag'       => BigDecimal('4.20'),
      'magnum'    => BigDecimal('4.20')
    }.freeze

    SUPPORTED_CHAINS = %i[ethereum solana polygon arbitrum optimism avalanche bsc].freeze

    CHAIN_METADATA = {
      ethereum:  { name: 'Ethereum Mainnet',   native: 'ETH',   chain_id: 1,     block_time_sec: 12.0, rpc: 'https://rpc.ankr.com/eth' },
      solana:    { name: 'Solana High‑Speed',  native: 'SOL',   chain_id: 101,   block_time_sec: 0.4,  rpc: 'https://api.mainnet-beta.solana.com' },
      polygon:   { name: 'Polygon PoS',        native: 'MATIC', chain_id: 137,   block_time_sec: 2.1,  rpc: 'https://polygon-rpc.com' },
      arbitrum:  { name: 'Arbitrum One L2',    native: 'ETH',   chain_id: 42161, block_time_sec: 0.25, rpc: 'https://arb1.arbitrum.io/rpc' },
      optimism:  { name: 'OP Mainnet L2',      native: 'ETH',   chain_id: 10,    block_time_sec: 2.0,  rpc: 'https://mainnet.optimism.io' },
      avalanche: { name: 'Avalanche C‑Chain',  native: 'AVAX',  chain_id: 43114, block_time_sec: 1.5,  rpc: 'https://api.avax.network/ext/bc/C/rpc' },
      bsc:       { name: 'BNB Smart Chain',    native: 'BNB',   chain_id: 56,    block_time_sec: 3.0,  rpc: 'https://bsc-dataseed.binance.org' }
    }.freeze

    # Token metadata per chain – address, decimals and CoinGecko identifier
    KNOWN_TOKENS = {
      ethereum: {
        'USDT' => { address: '0xdAC17F958D2ee523a2206206994597C13D831ec7', decimals: 6,  coingecko_id: 'tether' },
        'USDC' => { address: '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48', decimals: 6,  coingecko_id: 'usd-coin' },
        'MAG'  => { address: '0x999999cf1046e68e36E1aA2E0E07105eDDD1f08E', decimals: 18, coingecko_id: 'magnum' },
        'WBTC' => { address: '0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599', decimals: 8,  coingecko_id: 'bitcoin' }
      },
      polygon: {
        'USDC' => { address: '0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174', decimals: 6,  coingecko_id: 'usd-coin' },
        'WETH' => { address: '0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619', decimals: 18, coingecko_id: 'ethereum' },
        'MAG'  => { address: '0x333333cf1046e68e36E1aA2E0E07105eDDD1f08E', decimals: 18, coingecko_id: 'magnum' }
      },
      solana: {
        'USDC' => { address: 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v', decimals: 6,  coingecko_id: 'usd-coin' },
        'MAG'  => { address: 'MAGNUMxx11111111111111111111111111111111111', decimals: 9,  coingecko_id: 'magnum' }
      },
      arbitrum: {
        'USDC' => { address: '0xaf88d065e77c8cC2239327C5EDb3A432268e5831', decimals: 6,  coingecko_id: 'usd-coin' },
        'ARB'  => { address: '0x912CE59144191C1204E64559FE8253a0e49E6548', decimals: 18, coingecko_id: 'arbitrum' },
        'MAG'  => { address: '0x777777cf1046e68e36E1aA2E0E07105eDDD1f08E', decimals: 18, coingecko_id: 'magnum' }
      }
    }.freeze

    # ---------------------------------------------------------------------
    # Instance state
    # ---------------------------------------------------------------------
    def initialize(logger: nil)
      super() # MonitorMixin initialization
      @logger = logger || Logger.new($stdout)
      @cache = {}
      @request_timestamps = []
    end

    # ---------------------------------------------------------------------
    # Public API
    # ---------------------------------------------------------------------
    # Returns the USD price for a native chain token or any CoinGecko identifier.
    # Symbol can be a symbol (e.g. 'eth') or a full CoinGecko id (e.g. 'ethereum').
    def price(symbol)
      key = symbol.to_s.downcase
      cached = fetch_from_cache("price:#{key}")
      return cached if cached

      begin
        uri = BASE_COINGECKO_URI + "/simple/price?ids=#{URI.encode_www_form_component(key)}&vs_currencies=usd"
        json = fetch_json(uri)
        price = json[key]['usd']
        bd_price = BigDecimal(price.to_s)
        store_in_cache("price:#{key}", bd_price)
        bd_price
      rescue StandardError => e
        @logger.warn "CoinGecko request failed for #{key}: #{e.message}. Using fallback."
        FALLBACK_RATES[key] || (raise OracleError, "No fallback price for #{key}")
      end
    end

    # Returns the USD price for a known token on a specific chain.
    # token_symbol must exist in KNOWN_TOKENS[chain].
    def token_price(chain, token_symbol)
      chain_key = chain.to_sym
      raise ArgumentError, "Unsupported chain #{chain}" unless SUPPORTED_CHAINS.include?(chain_key)

      token_info = KNOWN_TOKENS.dig(chain_key, token_symbol.upcase)
      raise ArgumentError, "Unknown token #{token_symbol} on #{chain}" unless token_info

      coingecko_id = token_info[:coingecko_id]
      price(coingecko_id)
    end

    # Simple exchange rate between two symbols (both must resolve via #price).
    def exchange_rate(base_symbol, quote_symbol)
      base_price = price(base_symbol)
      quote_price = price(quote_symbol)
      raise CalculationError, "Zero price for quote #{quote_symbol}" if quote_price.zero?
      (base_price / quote_price).to_f
    end

    # Retrieves the native balance for an address on a given chain.
    # Currently implements a lightweight Ethereum balance lookup via Etherscan API
    # (requires an ENV['ETHERSCAN_API_KEY']). For other chains it raises NotImplementedError.
    def native_balance(address, chain)
      validate_address!(address)
      chain_key = chain.to_sym
      raise ArgumentError, "Unsupported chain #{chain}" unless SUPPORTED_CHAINS.include?(chain_key)

      case chain_key
      when :ethereum, :bsc, :polygon, :arbitrum, :optimism, :avalanche
        etherscan_api_key = ENV['ETHERSCAN_API_KEY']
        raise ConfigurationError, 'ETHERSCAN_API_KEY not set' unless etherscan_api_key
        base_url = case chain_key
                   when :ethereum then 'https://api.etherscan.io/api'
                   when :bsc      then 'https://api.bscscan.com/api'
                   when :polygon   then 'https://api.polygonscan.com/api'
                   when :arbitrum  then 'https://api.arbiscan.io/api'
                   when :optimism  then 'https://api-optimistic.etherscan.io/api'
                   when :avalanche then 'https://api.snowtrace.io/api'
                   end
        uri = URI(base_url)
        uri.query = URI.encode_www_form({module: 'account', action: 'balance', address: address, tag: 'latest', apikey: etherscan_api_key})
        json = fetch_json(uri)
        raise OracleError, "Etherscan error: #{json['message']}" unless json['status'] == '1'
        wei = BigDecimal(json['result'])
        eth = wei / (10**18)
        eth
      else
        raise NotImplementedError, "Native balance lookup not implemented for #{chain}"
      end
    end

    # Retrieves the token balance for a known token on a supported chain.
    # Uses the same Etherscan‑compatible API (or Solana RPC for SOL tokens).
    def token_balance(address, chain, token_symbol)
      validate_address!(address)
      chain_key = chain.to_sym
      raise ArgumentError, "Unsupported chain #{chain}" unless SUPPORTED_CHAINS.include?(chain_key)

      token_info = KNOWN_TOKENS.dig(chain_key, token_symbol.upcase)
      raise ArgumentError, "Unknown token #{token_symbol} on #{chain}" unless token_info

      case chain_key
      when :ethereum, :bsc, :polygon, :arbitrum, :optimism, :avalanche
        etherscan_api_key = ENV['ETHERSCAN_API_KEY']
        raise ConfigurationError, 'ETHERSCAN_API_KEY not set' unless etherscan_api_key
        base_url = case chain_key
                   when :ethereum then 'https://api.etherscan.io/api'
                   when :bsc      then 'https://api.bscscan.com/api'
                   when :polygon   then 'https://api.polygonscan.com/api'
                   when :arbitrum  then 'https://api.arbiscan.io/api'
                   when :optimism  then 'https://api-optimistic.etherscan.io/api'
                   when :avalanche then 'https://api.snowtrace.io/api'
                   end
        uri = URI(base_url)
        uri.query = URI.encode_www_form({module: 'account', action: 'tokenbalance', contractaddress: token_info[:address], address: address, tag: 'latest', apikey: etherscan_api_key})
        json = fetch_json(uri)
        raise OracleError, "Etherscan tokenbalance error: #{json['message']}" unless json['status'] == '1'
        raw = BigDecimal(json['result'])
        raw / (10**token_info[:decimals])
      when :solana
        # Minimal Solana RPC call for SPL token balance
        rpc_uri = URI(CHAIN_METADATA[:solana][:rpc])
        payload = {
          jsonrpc: '2.0',
          id: SecureRandom.random_number(1_000_000),
          method: 'getTokenAccountBalance',
          params: [address]
        }
        response = post_json(rpc_uri, payload)
        if response['error']
          raise OracleError, "Solana RPC error: #{response['error']['message']}"
        end
        amount = response['result']['value']['uiAmount']
        BigDecimal(amount.to_s)
      else
        raise NotImplementedError, "Token balance lookup not implemented for #{chain}"
      end
    end

    # ---------------------------------------------------------------------
    # Helper methods
    # ---------------------------------------------------------------------
    private

    def validate_address!(address)
      raise InvalidAddressError, 'Address cannot be nil or empty' if address.nil? || address.strip.empty?
      # Very light sanity check – real validation would be chain‑specific.
      raise InvalidAddressError, "Invalid address format: #{address}" unless address.match?(/^0x[0-9a-fA-F]{40}$/) || address.match?(/^[A-Za-z0-9]{44,}$/)
    end

    def fetch_json(uri)
      enforce_rate_limit!
      attempts = 0
      begin
        attempts += 1
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = (uri.scheme == 'https')
        http.read_timeout = DEFAULT_TIMEOUT_SEC
        request = Net::HTTP::Get.new(uri)
        response = http.request(request)
        case response
        when Net::HTTPSuccess
          JSON.parse(response.body)
        else
          raise NetworkError, "HTTP #{response.code} #{response.message} for #{uri}"
        end
      rescue *network_exceptions => e
        @logger.warn "Attempt #{attempts} failed for #{uri}: #{e.class} #{e.message}"
        retry if attempts < MAX_RETRY_ATTEMPTS
        raise NetworkError, "Failed after #{attempts} attempts: #{e.message}"
      end
    end

    def post_json(uri, payload)
      enforce_rate_limit!
      attempts = 0
      begin
        attempts += 1
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = (uri.scheme == 'https')
        http.read_timeout = DEFAULT_TIMEOUT_SEC
        request = Net::HTTP::Post.new(uri)
        request['Content-Type'] = 'application/json'
        request.body = payload.to_json
        response = http.request(request)
        case response
        when Net::HTTPSuccess
          JSON.parse(response.body)
        else
          raise NetworkError, "HTTP #{response.code} #{response.message} for #{uri}"
        end
      rescue *network_exceptions => e
        @logger.warn "POST attempt #{attempts} failed for #{uri}: #{e.class} #{e.message}"
        retry if attempts < MAX_RETRY_ATTEMPTS
        raise NetworkError, "POST failed after #{attempts} attempts: #{e.message}"
      end
    end

    def network_exceptions
      [Timeout::Error, Errno::ECONNREFUSED, Errno::ECONNRESET, SocketError, OpenSSL::SSL::SSLError]
    end

    # Simple token‑bucket style rate limiter – allows MAX_REQUESTS_PER_MIN within a rolling minute.
    def enforce_rate_limit!
      now = Time.now
      synchronize do
        @request_timestamps.reject! { |ts| ts < now - 60 }
        if @request_timestamps.size >= MAX_REQUESTS_PER_MIN
          raise RateLimitError, "Exceeded #{MAX_REQUESTS_PER_MIN} requests per minute"
        end
        @request_timestamps << now
      end
    end

    def cache_key(key)
      "wallet_service:#{key}"
    end

    def fetch_from_cache(key)
      entry = @cache[cache_key(key)]
      return nil unless entry
      if Time.now - entry[:timestamp] < DEFAULT_CACHE_TTL_SEC
        entry[:value]
      else
        @cache.delete(cache_key(key))
        nil
      end
    end

    def store_in_cache(key, value)
      @cache[cache_key(key)] = {value: value, timestamp: Time.now}
    end
  end

  # Custom error for missing configuration like API keys.
  class ConfigurationError < WalletServiceError; end
end