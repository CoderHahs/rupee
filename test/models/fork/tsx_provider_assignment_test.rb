require "test_helper"

class Fork::TsxProviderAssignmentTest < ActiveSupport::TestCase
  setup do
    Security.where(ticker: %w[GPV SHOP T]).destroy_all
    @enabled = %w[alpha_vantage eodhd yahoo_finance]
    Setting.stubs(:enabled_securities_providers).returns(@enabled)
    Security.stubs(:provider_for).returns(nil)
    @enabled.each { |name| Security.stubs(:provider_for).with(name).returns(mock(name)) }
  end

  def resolve(ticker, mic, price_provider: nil, match_provider: "yahoo_finance")
    match = Security.new(ticker: ticker, exchange_operating_mic: mic, country_code: "CA", price_provider: match_provider)
    resolver = Security::Resolver.new(ticker, exchange_operating_mic: mic, price_provider: price_provider)
    resolver.send(:find_or_create_provider_match!, match)
  end

  test "a bare TSXV ticker goes to the default TSX provider" do
    with_env("FORK_TSX_PRICE_PROVIDER" => nil) do
      assert_equal "alpha_vantage", resolve("GPV", "XTSX").price_provider
    end
  end

  test "FORK_TSX_PRICE_PROVIDER selects EODHD" do
    with_env("FORK_TSX_PRICE_PROVIDER" => "eodhd") do
      assert_equal "eodhd", resolve("SHOP", "XTSE").price_provider
    end
  end

  test "an unknown value falls back to the default" do
    with_env("FORK_TSX_PRICE_PROVIDER" => "nonsense") do
      assert_equal "alpha_vantage", resolve("GPV", "XTSX").price_provider
    end
  end

  test "an enabled TSX provider already on the security is kept" do
    Security.create!(ticker: "GPV", exchange_operating_mic: "XTSX", price_provider: "eodhd")

    with_env("FORK_TSX_PRICE_PROVIDER" => "alpha_vantage") do
      assert_equal "eodhd", resolve("GPV", "XTSX").price_provider
    end
  end

  test "an explicit provider wins" do
    assert_equal "yahoo_finance", resolve("GPV", "XTSX", price_provider: "yahoo_finance").price_provider
  end

  test "dotted tickers and other exchanges are left to upstream" do
    assert_equal "yahoo_finance", resolve("T.TO", "XTSE").price_provider
    assert_equal "yahoo_finance", resolve("T", "XNYS").price_provider
  end

  test "the match's provider is used when the TSX provider is not enabled" do
    Security.stubs(:provider_for).with("alpha_vantage").returns(nil)

    with_env("FORK_TSX_PRICE_PROVIDER" => "alpha_vantage") do
      assert_equal "yahoo_finance", resolve("GPV", "XTSX").price_provider
    end
  end

  private
    def with_env(vars)
      old = vars.keys.to_h { |k| [ k, ENV[k] ] }
      vars.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
      yield
    ensure
      old.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    end
end
