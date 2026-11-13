require "test_helper"
require "ostruct"

class Fork::HealthCheckPolicyTest < ActiveSupport::TestCase
  include ProviderTestHelper

  setup do
    @security = Security.create!(ticker: "HLT#{SecureRandom.hex(3)}", offline: false, last_health_check_at: nil)
    @provider = mock
    Security.any_instance.stubs(:price_data_provider).returns(@provider)
  end

  test "the probe asks for the 7 days ending today and passes on a price" do
    @provider.expects(:fetch_security_prices)
      .with(symbol: @security.ticker, exchange_operating_mic: @security.exchange_operating_mic,
            start_date: Date.current - 7.days, end_date: Date.current)
      .returns(provider_success_response([ OpenStruct.new(date: 2.days.ago.to_date, price: 5, currency: "USD") ]))

    @security.update!(failed_fetch_count: 3, offline: true)
    Security::HealthChecker.new(@security).run_check

    @security.reload
    assert_equal 0, @security.failed_fetch_count
    refute @security.offline?
  end

  test "a failed health check keeps prices when the security goes offline" do
    Security::Price.create!(security: @security, date: Date.current, price: 100, currency: "USD")
    @security.update!(failed_fetch_count: Security::HealthChecker::MAX_CONSECUTIVE_FAILURES)
    @provider.stubs(:fetch_security_prices).returns(provider_error_response(StandardError.new("No prices found")))

    Security::HealthChecker.new(@security).run_check

    @security.reload
    assert @security.offline?
    assert_equal "health_check_failed", @security.offline_reason
    assert_equal 1, @security.prices.count
  end

  test "an ordinary failure counts" do
    @provider.stubs(:fetch_security_prices).returns(provider_success_response([]))

    Security::HealthChecker.new(@security).run_check

    assert_equal 1, @security.reload.failed_fetch_count
  end

  test "a rate limit records no verdict" do
    @provider.stubs(:fetch_security_prices)
      .returns(provider_error_response(Provider::TwelveData::RateLimitError.new("slow down")))

    Security::HealthChecker.new(@security).run_check

    @security.reload
    assert_equal 0, @security.failed_fetch_count
    assert_not_nil @security.last_health_check_at
  end

  test "no provider records no verdict" do
    Security.any_instance.stubs(:price_data_provider).returns(nil)

    Security::HealthChecker.new(@security).run_check

    assert_equal 0, @security.reload.failed_fetch_count
  end

  test "Alpha Vantage and EODHD are skipped and count healthy" do
    [ Provider::AlphaVantage.new("k"), Provider::Eodhd.new("k") ].each do |provider|
      Security.any_instance.stubs(:price_data_provider).returns(provider)
      provider.expects(:fetch_security_prices).never
      @security.update!(failed_fetch_count: 2)

      Security::HealthChecker.new(@security).run_check

      assert_equal 0, @security.reload.failed_fetch_count
    end
  end
end
