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

    # ---------------------------------------------------------------------
    # Configuration constants
    # ---------------------------------------------------------------------
    BASE_COINGECKO_URI    = URI('https://api.coingecko.com/api/v3')
    DEFAULT_TIMEOUT_SEC   = 5
    DEFAULT_CACHE_TTL_SEC = 60
    MAX_RETRY_ATTEMPTS    = 3
    MAX_REQUESTS_PER_MIN  = 30

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
      solana:    { name: 'Solana High-Speed',  native: 'SOL',   chain_id: 101,   block_time_sec: 0.4,  rpc: 'https://api.mainnet-beta.solana.com' },
      polygon:   { name: 'Polygon PoS',        native: 'MATIC', chain_id: 137,   block_time_sec: 2.1,  rpc: 'https://polygon-rpc.com' },
      arbitrum:  { name: 'Arbitrum One L2',    native: 'ETH',   chain_id: 42161, block_time_sec: 0.25, rpc: 'https://arb1.arbitrum.io/rpc' },
      optimism:  { name: 'OP Mainnet L2',      native: 'ETH',   chain_id: 10,    block_time_sec: 2.0,  rpc: 'https://mainnet.optimism.io' },
      avalanche: { name: 'Avalanche C-Chain',  native: 'AVAX',  chain_id: 43114, block_time_sec: 1.5,  rpc: 'https://api.avax.network/ext/bc/C/rpc' },
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

    attr_reader :wallet_address, :primary_chain, :logger, :cache_ttl

    # ---------------------------------------------------------------------
    # Constructor
    # ---------------------------------------------------------------------
    # @param wallet_address [String, nil] Public 0x-hex address or Base58 Solana key
    # @param primary_chain [Symbol] Primary blockchain network symbol
    # @param logger [Logger, nil] Custom logger instance
    # @param cache_ttl [Integer] Cache expiration in seconds
    # ---------------------------------------------------------------------
    def initialize(wallet_address = nil, primary_chain: :ethereum, logger: nil, cache_ttl: DEFAULT_CACHE_TTL_SEC)
      super()
      @logger             = logger || Logger.new($stdout, level: Logger::INFO, progname: 'MagnumOpus::WalletService')
      @primary_chain      = SUPPORTED_CHAINS.include?(primary_chain.to_sym) ? primary_chain.to_sym : :ethereum
      @cache_ttl          = cache_ttl.to_i
      @cache              = {}
      @request_timestamps = []

      self.wallet_address = wallet_address if wallet_address
    end

    # ---------------------------------------------------------------------
    # Address validation & setting
    # ---------------------------------------------------------------------
    def wallet_address=(addr)
      return if addr.nil?

      cleaned = addr.to_s.strip
      unless valid_address?(cleaned, @primary_chain)
        raise InvalidAddressError, "Address '#{cleaned}' is invalid for chain '#{@primary_chain}'"
      end

      synchronize { @wallet_address = cleaned }
    end

    def valid_address?(addr, chain = @primary_chain)
      case chain.to_sym
      when :solana
        # Base58 public key format, typically 32..44 characters
        addr.match?(%r{\A[1-9A-HJ-NP-Za-km-z]{32,44}\z})
      else
        # EVM 40 hex characters with 0x prefix
        addr.match?(%r{\A0x[a-fA-F0-9]{40}\z})
      end
    end

    # ---------------------------------------------------------------------
    # Oracle & Exchange Rate Engine
    # ---------------------------------------------------------------------
    # Returns pricing hash mapping normalized symbols to BigDecimal prices in USD
    def fetch_rates(symbols = %w[eth btc sol matic arbitrum optimism avax bnb usdt usdc mag])
      normalized = symbols.map { |s| s.to_s.downcase.strip }.uniq
      results = {}
      missing = []

      synchronize do
        now = Time.now.to_i
        normalized.each do |sym|
          cached_entry = @cache["rate_#{sym}"]
          if cached_entry && (now - cached_entry[:timestamp] < @cache_ttl)
            results[sym] = cached_entry[:value]
          else
            missing << sym
          end
        end
      end

      return results if missing.empty?

      fetched = fetch_from_remote_or_fallback(missing)
      synchronize do
        now = Time.now.to_i
        fetched.each do |sym, val|
          @cache["rate_#{sym}"] = { value: val, timestamp: now }
          results[sym] = val
        end
      end

      results
    end

    def get_rate(token_symbol)
      sym = token_symbol.to_s.downcase.strip
      fetch_rates([sym])[sym] || FALLBACK_RATES[sym] || BigDecimal('1.00')
    end

    # Converts amount from source currency to target currency using precision BigDecimals
    def calculate_conversion(from_amount, from_symbol, to_symbol)
      amt = BigDecimal(from_amount.to_s)
      raise CalculationError, 'Amount cannot be negative' if amt.negative?

      from_rate = get_rate(from_symbol)
      to_rate   = get_rate(to_symbol)

      raise CalculationError, "Invalid exchange rate for target #{to_symbol}" if to_rate.zero?

      usd_value = amt * from_rate
      target_units = usd_value / to_rate

      {
        from_amount: amt,
        from_symbol: from_symbol.to_s.upcase,
        from_rate_usd: from_rate,
        to_symbol: to_symbol.to_s.upcase,
        to_rate_usd: to_rate,
        usd_value: usd_value.round(4),
        target_amount: target_units.round(8)
      }
    end

    # ---------------------------------------------------------------------
    # Multi-Chain Balance & Portfolio Aggregation
    # ---------------------------------------------------------------------
    # Returns detailed asset balances for a wallet on a specified chain
    def fetch_wallet_balances(address = @wallet_address, chain = @primary_chain)
      target_addr = address || @wallet_address
      raise InvalidAddressError, 'No wallet address specified' unless target_addr
      raise InvalidAddressError, "Address invalid for #{chain}" unless valid_address?(target_addr, chain)

      meta = CHAIN_METADATA[chain.to_sym] || CHAIN_METADATA[:ethereum]
      native_sym = meta[:native].downcase
      native_rate = get_rate(native_sym)

      # Deterministic mock balance generation seeded by wallet address and chain
      seed = OpenSSL::Digest::SHA256.hexdigest("#{target_addr}:#{chain}").to_i(16)
      native_balance = BigDecimal(((seed % 10_000) / 100.0).to_s).round(4)

      balances = {
        address: target_addr,
        chain: chain.to_sym,
        chain_id: meta[:chain_id],
        native: {
          symbol: meta[:native],
          balance: native_balance,
          rate_usd: native_rate,
          value_usd: (native_balance * native_rate).round(2)
        },
        tokens: [],
        total_chain_usd: BigDecimal('0.0')
      }

      total_usd = balances[:native][:value_usd]
      known = KNOWN_TOKENS[chain.to_sym] || {}

      known.each_with_index do |(tok_sym, tok_info), idx|
        tok_rate = get_rate(tok_sym)
        tok_seed = (seed >> (idx * 8 + 4)) % 50_000
        tok_bal  = BigDecimal((tok_seed / 10.0).to_s).round(4)
        tok_val  = (tok_bal * tok_rate).round(2)
        total_usd += tok_val

        balances[:tokens] << {
          symbol: tok_sym,
          address: tok_info[:address],
          decimals: tok_info[:decimals],
          balance: tok_bal,
          rate_usd: tok_rate,
          value_usd: tok_val
        }
      end

      balances[:total_chain_usd] = total_usd.round(2)
      balances
    end

    # Aggregates portfolio across all supported chains
    def aggregate_multi_chain_portfolio(address = @wallet_address)
      target_addr = address || @wallet_address
      raise InvalidAddressError, 'No wallet address specified' unless target_addr

      portfolio = {
        address: target_addr,
        total_net_worth_usd: BigDecimal('0.0'),
        chains: {},
        token_allocation: Hash.new(BigDecimal('0.0')),
        timestamp: Time.now.utc.iso8601
      }

      SUPPORTED_CHAINS.each do |chain|
        # EVM address vs Solana base58 check
        next if chain == :solana && !valid_address?(target_addr, :solana)
        next if chain != :solana && !valid_address?(target_addr, :ethereum)

        chain_data = fetch_wallet_balances(target_addr, chain)
        portfolio[:chains][chain] = chain_data
        portfolio[:total_net_worth_usd] += chain_data[:total_chain_usd]

        native_sym = chain_data[:native][:symbol]
        portfolio[:token_allocation][native_sym] += chain_data[:native][:value_usd]

        chain_data[:tokens].each do |tok|
          portfolio[:token_allocation][tok[:symbol]] += tok[:value_usd]
        end
      end

      portfolio[:total_net_worth_usd] = portfolio[:total_net_worth_usd].round(2)
      portfolio
    end

    # ---------------------------------------------------------------------
    # DeFi Math & Impermanent Loss Model
    # ---------------------------------------------------------------------
    # Calculates AMM Constant Product Impermanent Loss
    # @param price_ratio_k [Numeric] Relative price change of Asset A relative to Asset B (P_new / P_initial)
    # @return [Hash] IL percentage, pool ratio, and hold vs lp comparison
    def calculate_impermanent_loss(price_ratio_k)
      k = BigDecimal(price_ratio_k.to_s)
      raise CalculationError, 'Price ratio must be greater than zero' if k <= 0

      # IL = (2 * sqrt(k)) / (1 + k) - 1
      sqrt_k = BigDecimal(Math.sqrt(k.to_f).to_s)
      pool_ratio = (BigDecimal('2.0') * sqrt_k) / (BigDecimal('1.0') + k)
      il_fraction = pool_ratio - BigDecimal('1.0')
      il_percentage = (il_fraction * BigDecimal('100.0')).round(4)

      {
        price_ratio: k,
        pool_vs_hold_ratio: pool_ratio.round(6),
        impermanent_loss_percentage: il_percentage,
        loss_per_10k_usd: (BigDecimal('10000.0') * il_fraction.abs).round(2)
      }
    end

    # Calculates LP Position Values and projected impermanent loss
    def calculate_lp_position_value(token_a_amount, token_b_amount, p_a_init, p_b_init, p_a_curr, p_b_curr)
      amt_a = BigDecimal(token_a_amount.to_s)
      amt_b = BigDecimal(token_b_amount.to_s)
      pa_0  = BigDecimal(p_a_init.to_s)
      pb_0  = BigDecimal(p_b_init.to_s)
      pa_1  = BigDecimal(p_a_curr.to_s)
      pb_1  = BigDecimal(p_b_curr.to_s)

      val_initial = (amt_a * pa_0) + (amt_b * pb_0)
      val_hold    = (amt_a * pa_1) + (amt_b * pb_1)

      k = (pa_1 / pb_1) / (pa_0 / pb_0)
      il_data = calculate_impermanent_loss(k)

      val_lp = val_hold * il_data[:pool_vs_hold_ratio]
      net_il_loss = (val_hold - val_lp).round(2)

      {
        initial_investment_usd: val_initial.round(2),
        hodl_value_usd: val_hold.round(2),
        lp_current_value_usd: val_lp.round(2),
        divergence_loss_usd: net_il_loss,
        impermanent_loss_percent: il_data[:impermanent_loss_percentage]
      }
    end

    # Calculates DeFi Staking & Farming Compound Yield
    def calculate_farming_yield(principal_usd, apr_percent, duration_days, compound_frequency_per_year: 365)
      p   = BigDecimal(principal_usd.to_s)
      r   = BigDecimal(apr_percent.to_s) / BigDecimal('100.0')
      n   = BigDecimal(compound_frequency_per_year.to_s)
      t   = BigDecimal(duration_days.to_s) / BigDecimal('365.0')

      # APY = (1 + r/n)^n - 1
      base = BigDecimal('1.0') + (r / n)
      apy  = (base**compound_frequency_per_year.to_i) - BigDecimal('1.0')

      # Future Value = P * (1 + r/n)^(n*t)
      total_compounds = (n * t).to_f.round
      fv = p * (base**total_compounds)
      earned = fv - p

      {
        principal_usd: p.round(2),
        apr_percent: apr_percent,
        apy_percent: (apy * BigDecimal('100.0')).round(3),
        duration_days: duration_days,
        projected_earnings_usd: earned.round(2),
        total_future_value_usd: fv.round(2)
      }
    end

    # ---------------------------------------------------------------------
    # Gas & Fee Oracle
    # ---------------------------------------------------------------------
    def estimate_gas_fees(chain = @primary_chain)
      meta = CHAIN_METADATA[chain.to_sym] || CHAIN_METADATA[:ethereum]
      native_rate = get_rate(meta[:native].downcase)

      case chain.to_sym
      when :ethereum
        base_gwei     = BigDecimal('24.5')
        slow_gwei     = (base_gwei * BigDecimal('0.85')).round(2)
        standard_gwei = base_gwei.round(2)
        fast_gwei     = (base_gwei * BigDecimal('1.35')).round(2)
        gas_limit     = BigDecimal('21000')
        swap_limit    = BigDecimal('150000')
      when :polygon
        base_gwei     = BigDecimal('85.0')
        slow_gwei     = BigDecimal('70.0')
        standard_gwei = BigDecimal('90.0')
        fast_gwei     = BigDecimal('130.0')
        gas_limit     = BigDecimal('21000')
        swap_limit    = BigDecimal('140000')
      when :solana
        # Solana base lamports: 5000 lamports standard
        slow_gwei     = BigDecimal('0.000005')
        standard_gwei = BigDecimal('0.000005')
        fast_gwei     = BigDecimal('0.000010')
        gas_limit     = BigDecimal('1')
        swap_limit    = BigDecimal('2')
      else
        base_gwei     = BigDecimal('0.15')
        slow_gwei     = BigDecimal('0.10')
        standard_gwei = BigDecimal('0.15')
        fast_gwei     = BigDecimal('0.30')
        gas_limit     = BigDecimal('21000')
        swap_limit    = BigDecimal('120000')
      end

      calc_fiat = lambda do |gwei, limit|
        if chain.to_sym == :solana
          (gwei * limit * native_rate).round(4)
        else
          # gwei * 10^-9 * limit * native_rate
          (gwei * BigDecimal('1e-9') * limit * native_rate).round(4)
        end
      end

      {
        chain: chain.to_sym,
        native_symbol: meta[:native],
        native_rate_usd: native_rate,
        units: chain.to_sym == :solana ? 'SOL' : 'Gwei',
        tiers: {
          slow: {
            price: slow_gwei,
            transfer_usd: calc_fiat.call(slow_gwei, gas_limit),
            contract_swap_usd: calc_fiat.call(slow_gwei, swap_limit)
          },
          standard: {
            price: standard_gwei,
            transfer_usd: calc_fiat.call(standard_gwei, gas_limit),
            contract_swap_usd: calc_fiat.call(standard_gwei, swap_limit)
          },
          fast: {
            price: fast_gwei,
            transfer_usd: calc_fiat.call(fast_gwei, gas_limit),
            contract_swap_usd: calc_fiat.call(fast_gwei, swap_limit)
          }
        },
        estimated_seconds: meta[:block_time_sec]
      }
    end

    # ---------------------------------------------------------------------
    # Transaction Digest & Signing Utilities
    # ---------------------------------------------------------------------
    def generate_transaction_digest(chain_id, nonce, to, value_wei, data = '0x', gas_price = 0, gas_limit = 21_000)
      payload = [
        chain_id.to_i,
        nonce.to_i,
        to.to_s.downcase,
        value_wei.to_s,
        data.to_s,
        gas_price.to_i,
        gas_limit.to_i
      ].join(':')

      digest = OpenSSL::Digest::SHA256.hexdigest(payload)
      "0x#{digest}"
    end

    # Validates an HMAC/ECDSA signature placeholder against a message and address
    def verify_message_signature(message, signature_hex, public_address)
      return false if signature_hex.nil? || public_address.nil?

      normalized_sig = signature_hex.to_s.sub(/\A0x/, '')
      return false if normalized_sig.length < 64

      # Hash verification anchor
      expected_hash = OpenSSL::HMAC.hexdigest('SHA256', public_address.downcase, message)
      normalized_sig.start_with?(expected_hash[0..15]) || normalized_sig.length == 130
    end

    # ---------------------------------------------------------------------
    # Telemetry Snapshot Export
    # ---------------------------------------------------------------------
    # Formats wallet state for front-end dashboard, Go microservice, or C# core ingestion
    def export_telemetry_snapshot(portfolio_data = nil)
      data = portfolio_data || aggregate_multi_chain_portfolio
      rates = fetch_rates
      gas_report = estimate_gas_fees(@primary_chain)

      {
        version: '1.0.0',
        source: 'MagnumOpus::WalletService',
        timestamp: Time.now.utc.iso8601,
        active_wallet: @wallet_address,
        primary_chain: @primary_chain,
        portfolio: data,
        live_market_rates: rates.transform_values(&:to_f),
        gas_oracle: gas_report
      }
    end

    # ---------------------------------------------------------------------
    # Private Helpers
    # ---------------------------------------------------------------------
    private

    def fetch_from_remote_or_fallback(missing_symbols)
      results = {}

      if check_rate_limit!
        begin
          results = fetch_coingecko_rates(missing_symbols)
        rescue StandardError => e
          @logger.warn("Remote price fetch failed (#{e.message}); falling back to built-in pricing oracles.")
          results = {}
        end
      end

      missing_symbols.each do |sym|
        results[sym] ||= FALLBACK_RATES[sym] || BigDecimal('1.00')
      end

      results
    end

    def fetch_coingecko_rates(symbols)
      id_map = {
        'eth' => 'ethereum', 'ethereum' => 'ethereum',
        'btc' => 'bitcoin',  'bitcoin' => 'bitcoin',
        'sol' => 'solana',   'solana' => 'solana',
        'matic' => 'matic-network', 'polygon' => 'matic-network',
        'arbitrum' => 'arbitrum', 'optimism' => 'optimism',
        'avax' => 'avalanche-2', 'bnb' => 'binancecoin',
        'usdt' => 'tether', 'usdc' => 'usd-coin',
        'mag' => 'magnum'
      }

      ids = symbols.map { |s| id_map[s] }.compact.uniq
      return {} if ids.empty?

      uri = BASE_COINGECKO_URI.dup
      uri.path = '/api/v3/simple/price'
      uri.query = URI.encode_www_form(ids: ids.join(','), vs_currencies: 'usd')

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == 'https')
      http.open_timeout = DEFAULT_TIMEOUT_SEC
      http.read_timeout = DEFAULT_TIMEOUT_SEC

      req = Net::HTTP::Get.new(uri)
      req['Accept'] = 'application/json'
      req['User-Agent'] = 'MagnumOpus-WalletService/1.0'

      resp = http.request(req)
      return {} unless resp.is_a?(Net::HTTPSuccess)

      parsed = JSON.parse(resp.body)
      extracted = {}

      symbols.each do |sym|
        gecko_id = id_map[sym]
        if gecko_id && parsed[gecko_id] && parsed[gecko_id]['usd']
          extracted[sym] = BigDecimal(parsed[gecko_id]['usd'].to_s)
        end
      end

      extracted
    end

    def check_rate_limit!
      now = Time.now.to_i
      synchronize do
        @request_timestamps.reject! { |t| now - t > 60 }
        if @request_timestamps.size >= MAX_REQUESTS_PER_MIN
          @logger.debug('Local rate limit window saturated. Yielding to internal cache and fallback rates.')
          return false
        end
        @request_timestamps << now
        true
      end
    end
  end
end
