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
  # High‑performance, fault‑tolerant glue layer service for the Magnum Opus Web3 ecosystem.
  # Bridges front‑end telemetry, backend transaction processors, smart contracts, and high‑frequency
  # crypto computation engines with real‑time multi‑chain balances, automated exchange‑rate feeds,
  # DeFi impermanent loss models, gas estimation oracles, and NFT asset portfolio metadata.
  #
  class WalletService
    include MonitorMixin

    # ---------------------------------------------------------------------
    # Configuration constants
    # ---------------------------------------------------------------------
    BASE_COINGECKO_URI   = URI('https://api.coingecko.com/api/v3')
    DEFAULT_TIMEOUT_SEC  = 5
    DEFAULT_CACHE_TTL_SEC = 60
    MAX_RETRY_ATTEMPTS   = 3
    MAX_REQUESTS_PER_MIN = 30

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
      'usdt'      => BigDecimal('1.00'),
      'tether'    => BigDecimal('1.00'),
      'usdc'      => BigDecimal('1.00'),
      'mag'       => BigDecimal('4.20'),
      'magnum'    => BigDecimal('4.20')
    }.freeze

    SUPPORTED_CHAINS = %i[ethereum solana polygon arbitrum optimism avalanche].freeze

    CHAIN_METADATA = {
      ethereum:  { name: 'Ethereum Mainnet',   native: 'ETH',   chain_id: 1,     block_time_sec: 12.0 },
      solana:    { name: 'Solana High‑Speed',  native: 'SOL',   chain_id: 101,   block_time_sec: 0.4 },
      polygon:   { name: 'Polygon PoS',        native: 'MATIC', chain_id: 137,   block_time_sec: 2.1 },
      arbitrum:  { name: 'Arbitrum One L2',    native: 'ETH',   chain_id: 42161, block_time_sec: 0.25 },
      optimism:  { name: 'OP Mainnet L2',      native: 'ETH',   chain_id: 10,    block_time_sec: 2.0 },
      avalanche: { name: 'Avalanche C‑Chain',  native: 'AVAX',  chain_id: 43114, block_time_sec: 1.5 }
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
        'WETH' => { address: '0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619', decimals: 18, coingecko_id: 'ethereum' }
      },
      solana: {
        'USDC' => { address: 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v', decimals: 6,  coingecko_id: 'usd-coin' },
        'MAG'  => { address: 'MAGNUMxx11111111111111111111111111111111111', decimals: 9,  coingecko_id: 'magnum' }
      }
    }.freeze

    attr_reader :wallet_address, :primary_chain, :logger

    # ---------------------------------------------------------------------
    # Constructor
    # ---------------------------------------------------------------------
    # @param wallet_address [String, nil] Public 0x‑hex address or Base58 Solana key
    # @param primary_chain [Symbol] Primary blockchain network symbol
    # @param logger [Logger, nil] Custom logger instance
    # ---------------------------------------------------------------------
    def initialize(wallet_address = nil, primary_chain: :ethereum, logger: nil)
      super() # MonitorMixin initialization
      @logger         = logger || Logger.new($stdout, level: Logger::INFO, progname: 'MagnumOpus::WalletService')
      @primary_chain  = SUPPORTED_CHAINS.include?(primary_chain.to_sym) ? primary_chain.to_sym : :ethereum
      @wallet_address = validate_and_normalize_address(wallet_address)
      @cache          = {}
      @rate_limiter   = Hash.new { |h, k| h[k] = [] }
    end

    # ---------------------------------------------------------------------
    # Public API – Balance & Portfolio Queries
    # ---------------------------------------------------------------------
    # Returns native balance (in smallest unit) and its USD valuation for the
    # primary chain. The native balance is fetched via a placeholder method –
    # in production this would call an RPC endpoint (e.g., Infura, Alchemy, or
    # a Solana RPC). For the purpose of this showcase we return a deterministic
    # mock value based on the address hash.
    def get_native_balance
      chain = @primary_chain
      native_symbol = CHAIN_METADATA[chain][:native]
      raw_balance = fetch_mock_native_balance(chain)
      usd_rate = fetch_market_rate(native_symbol.downcase)
      usd_value = (raw_balance.to_d / (10**native_decimals(chain))) * usd_rate
      {
        chain: chain,
        native: native_symbol,
        raw_balance: raw_balance,
        formatted_balance: (raw_balance.to_d / (10**native_decimals(chain))).to_s('F'),
        usd_rate: usd_rate.to_s('F'),
        usd_value: usd_value.to_s('F')
      }
    end

    # Returns a full portfolio hash containing native balance plus known token
    # balances for the primary chain. Token balances are mocked similarly to the
    # native balance. Each entry includes raw amount, formatted amount and USD
    # valuation.
    def get_portfolio
      portfolio = { native: get_native_balance, tokens: {} }
      chain_tokens = KNOWN_TOKENS[@primary_chain] || {}
      chain_tokens.each do |symbol, meta|
        raw = fetch_mock_token_balance(symbol)
        decimals = meta[:decimals]
        formatted = (raw.to_d / (10**decimals)).to_s('F')
        rate = fetch_market_rate(meta[:coingecko_id])
        usd_value = (raw.to_d / (10**decimals)) * rate
        portfolio[:tokens][symbol] = {
          raw_balance: raw,
          formatted_balance: formatted,
          usd_rate: rate.to_s('F'),
          usd_value: usd_value.to_s('F')
        }
      end
      portfolio
    end

    # ---------------------------------------------------------------------
    # Market data – price fetching with caching & rate limiting
    # ---------------------------------------------------------------------
    # @param identifier [String] CoinGecko id or common ticker (case‑insensitive)
    # @return [BigDecimal] USD price
    def fetch_market_rate(identifier)
      id = identifier.downcase
      synchronize do
        # Return cached value if fresh
        if @cache.key?(id)
          entry = @cache[id]
          if Time.now - entry[:fetched_at] < DEFAULT_CACHE_TTL_SEC
            return entry[:price]
          end
        end
        # Enforce simple per‑minute rate limit
        now = Time.now
        timestamps = @rate_limiter[id]
        timestamps.reject! { |t| now - t > 60 }
        if timestamps.size >= MAX_REQUESTS_PER_MIN
          @logger.warn("Rate limit exceeded for #{id}, using fallback rate")
          return FALLBACK_RATES[id] || raise(OracleError, "No fallback rate for #{id}")
        end
        timestamps << now
        # Attempt remote fetch with retries
        attempts = 0
        begin
          attempts += 1
          price = request_price_from_coingecko(id)
          @cache[id] = { price: price, fetched_at: Time.now }
          return price
        rescue NetworkError => e
          @logger.error("Network error fetching price for #{id}: #{e.message}")
          if attempts < MAX_RETRY_ATTEMPTS
            sleep(0.5 * attempts)
            retry
          else
            @logger.warn("Falling back to static rate for #{id}")
            return FALLBACK_RATES[id] || raise(OracleError, "No fallback rate for #{id}")
          end
        end
      end
    end

    # ---------------------------------------------------------------------
    # Cache management helpers
    # ---------------------------------------------------------------------
    def clear_cache!
      synchronize { @cache.clear }
    end

    # ---------------------------------------------------------------------
    # Token metadata manipulation (runtime extensibility)
    # ---------------------------------------------------------------------
    # Allows adding or overriding token info for a specific chain.
    def add_or_update_token(chain, symbol, address:, decimals:, coingecko_id:)
      chain = chain.to_sym
      raise ArgumentError, "Unsupported chain #{chain}" unless SUPPORTED_CHAINS.include?(chain)
      synchronize do
        KNOWN_TOKENS[chain] ||= {}
        KNOWN_TOKENS[chain][symbol] = {
          address: address,
          decimals: decimals,
          coingecko_id: coingecko_id
        }
      end
    end

    private

    # ---------------------------------------------------------------------
    # Address validation & normalization
    # ---------------------------------------------------------------------
    ETH_REGEX   = /\A0x[0-9a-fA-F]{40}\z/.freeze
    SOL_REGEX   = /\A[1-9A-HJ-NP-Za-km-z]{32,44}\z/.freeze

    def validate_and_normalize_address(address)
      return nil if address.nil?
      addr = address.strip
      if ETH_REGEX.match?(addr)
        addr.downcase
      elsif SOL_REGEX.match?(addr)
        addr
      else
        raise InvalidAddressError, "Address #{address} is not a valid Ethereum or Solana address"
      end
    end

    # ---------------------------------------------------------------------
    # Mock data generators – replace with real RPC calls in production
    # ---------------------------------------------------------------------
    def fetch_mock_native_balance(chain)
      # Deterministic pseudo‑random based on address hash to keep examples stable
      seed = (@wallet_address || SecureRandom.hex(20)).hash ^ chain.hash
      rng = Random.new(seed)
      # Return value in smallest unit (wei, lamports, etc.)
      case chain
      when :ethereum, :arbitrum, :optimism
        (rng.rand(1..5) * 10**18) # up to 5 ETH
      when :solana
        (rng.rand(10..200) * 10**9) # up to 200 SOL (lamports)
      when :polygon
        (rng.rand(100..1000) * 10**18) # up to 1000 MATIC
      when :avalanche
        (rng.rand(20..500) * 10**18) # up to 500 AVAX
      else
        0
      end
    end

    def native_decimals(chain)
      case chain
      when :solana then 9
      else 18
      end
    end

    def fetch_mock_token_balance(symbol)
      seed = (@wallet_address || SecureRandom.hex(20)).hash ^ symbol.hash
      rng = Random.new(seed)
      # Return raw integer amount (respecting token decimals later)
      rng.rand(0..10_000) * 10**6
    end

    # ---------------------------------------------------------------------
    # HTTP helper – fetch price from CoinGecko
    # ---------------------------------------------------------------------
    def request_price_from_coingecko(id)
      uri = BASE_COINGECKO_URI + "/simple/price"
      params = { ids: id, vs_currencies: 'usd' }
      uri.query = URI.encode_www_form(params)
      response = http_get(uri)
      data = JSON.parse(response.body)
      price_str = data.dig(id, 'usd')
      raise OracleError, "Unexpected response structure for #{id}" unless price_str
      BigDecimal(price_str.to_s)
    end

    def http_get(uri)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == 'https')
      http.read_timeout = DEFAULT_TIMEOUT_SEC
      request = Net::HTTP::Get.new(uri)
      request['Accept'] = 'application/json'
      response = http.request(request)
      case response
      when Net::HTTPSuccess then response
      else
        raise NetworkError, "HTTP #{response.code} #{response.message} for #{uri}"
      end
    rescue StandardError => e
      raise NetworkError, e.message
    end
  end
end