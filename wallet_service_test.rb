require 'minitest/autorun'
require 'logger'
require 'bigdecimal'
require_relative 'WalletService'

module MagnumOpus
  class WalletServiceTest < Minitest::Test
    def setup
      @logger = Logger.new(nil)
      @service = WalletService.new(logger: @logger)
    end

    def test_price_successful
      stub_response = {"ethereum" => {"usd" => "3500.00"}}
      @service.stub(:fetch_json, stub_response) do
        price = @service.price('ethereum')
        assert_instance_of(BigDecimal, price)
        assert_equal(BigDecimal('3500.00'), price)
      end
    end

    def test_price_fallback_on_error
      @service.stub(:fetch_json, proc { raise StandardError.new('network') }) do
        price = @service.price('eth')
        assert_equal(WalletService::FALLBACK_RATES['eth'], price)
      end
    end

    def test_token_price_known_token
      @service.stub(:price, BigDecimal('1.00')) do
        price = @service.token_price(:ethereum, 'USDT')
        assert_equal(BigDecimal('1.00'), price)
      end
    end

    def test_exchange_rate
      @service.stub(:price, proc { |sym| sym.to_s == 'eth' ? BigDecimal('3500') : BigDecimal('1') }) do
        rate = @service.exchange_rate('eth', 'usdt')
        assert_in_delta(3500.0, rate, 0.0001)
      end
    end

    def test_native_balance_without_api_key
      ENV.delete('ETHERSCAN_API_KEY')
      address = '0x1234567890abcdef1234567890abcdef12345678'
      balance = @service.native_balance(address, :ethereum)
      assert_equal(BigDecimal('14.852'), balance)
    end

    def test_native_balance_invalid_address
      assert_raises(InvalidAddressError) do
        @service.native_balance('invalid_address', :ethereum)
      end
    end
  end
end