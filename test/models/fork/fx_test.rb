require "test_helper"

class Fork::FxTest < ActiveSupport::TestCase
  include ProviderTestHelper

  FRIDAY = Date.new(2026, 9, 25)
  SATURDAY = Date.new(2026, 9, 26)

  setup do
    ExchangeRate.delete_all
    Rails.cache.clear
    ExchangeRate.stubs(:provider).returns(nil)
  end

  teardown { Fork::RequestFx.reset }

  def observed(from, to, date, rate, observed_on: date, source: "bank_of_canada")
    ExchangeRate.create!(from_currency: from, to_currency: to, date: date, rate: rate, observed_on: observed_on, source: source)
  end

  test "identity is a rate of 1 with no carry and no row" do
    quote = Fork::Fx.lookup(from: "CAD", to: "CAD", date: FRIDAY)

    assert_equal 1, quote.rate
    assert_equal 0, quote.carry_days
    assert_nil quote.row
  end

  test "6.1: a Saturday row filled from Friday converts at 1.4145 with a carry of 1 day and no banner" do
    observed("USD", "CAD", FRIDAY, "1.4145")
    observed("USD", "CAD", SATURDAY, "1.4145", observed_on: FRIDAY)

    quote = Fork::Fx.lookup(from: "USD", to: "CAD", date: SATURDAY)

    assert_equal BigDecimal("1.4145"), quote.rate
    assert_equal 1, quote.carry_days
    assert_equal FRIDAY, quote.observed_on
    assert_equal "bank_of_canada", quote.source
    assert quote.carried?
    assert_equal BigDecimal("141.45"), Money.new(100, "USD").exchange_to("CAD", date: SATURDAY).amount
    assert_empty Fork::RequestFx.instance.banner_carries
    assert_empty Fork::RequestFx.instance.misses
  end

  test "6.1: an observation 8 days old is not used and is reported missing" do
    observed("USD", "CAD", Date.new(2026, 9, 18), "1.4000")
    observed("USD", "CAD", SATURDAY, "1.4000", observed_on: Date.new(2026, 9, 18))

    assert_nil Fork::Fx.lookup(from: "USD", to: "CAD", date: SATURDAY)
    assert_raises(Money::ConversionError) { Money.new(100, "USD").exchange_to("CAD", date: SATURDAY) }
    assert Fork::RequestFx.instance.misses.key?([ "USD", "CAD", SATURDAY ])
    assert_empty ExchangeRate.rates_for([ "USD" ], to: "CAD", date: SATURDAY)
  end

  test "a carry of more than 3 days gets a banner" do
    observed("USD", "CAD", Date.new(2026, 9, 21), "1.4000")

    quote = Fork::Fx.lookup(from: "USD", to: "CAD", date: SATURDAY)

    assert_equal 5, quote.carry_days
    assert_equal 1, Fork::RequestFx.instance.banner_carries.size
  end

  test "an unobserved row counts as observed on its own date" do
    ExchangeRate.create!(from_currency: "USD", to_currency: "CAD", date: FRIDAY, rate: 1.41)

    assert_equal 0, Fork::Fx.lookup(from: "USD", to: "CAD", date: FRIDAY).carry_days
  end

  test "only earlier observations are used" do
    observed("USD", "CAD", SATURDAY, "1.5000")

    assert_nil Fork::Fx.lookup(from: "USD", to: "CAD", date: FRIDAY)
  end

  test "fetches and caches one rate when none is stored, and caches a miss for an hour" do
    provider = mock("provider")
    ExchangeRate.stubs(:provider).returns(provider)
    provider.expects(:fetch_exchange_rate).once.returns(
      provider_success_response(Fork::SourcedRate.new(date: FRIDAY, from: "USD", to: "CAD", rate: 1.4145, source: "bank_of_canada"))
    )

    quote = Fork::Fx.lookup(from: "USD", to: "CAD", date: SATURDAY)

    assert_equal 1, quote.carry_days
    row = ExchangeRate.find_by!(from_currency: "USD", to_currency: "CAD", date: FRIDAY)
    assert_equal FRIDAY, row.observed_on
    assert_equal "bank_of_canada", row.source

    provider.expects(:fetch_exchange_rate).once.returns(provider_error_response(StandardError.new("none")))
    ActiveSupport::Cache::MemoryStore.new.tap { |store| Rails.stubs(:cache).returns(store) }
    assert_nil Fork::Fx.lookup(from: "EUR", to: "CAD", date: SATURDAY)
    assert_nil Fork::Fx.lookup(from: "EUR", to: "CAD", date: SATURDAY)
  end

  test "rates_for leaves out a currency with no rate and never returns 1" do
    observed("USD", "CAD", FRIDAY, "1.4145")

    rates = ExchangeRate.rates_for(%w[USD EUR], to: "CAD", date: FRIDAY)

    assert_equal({ "USD" => BigDecimal("1.4145") }, rates)
  end

  test "find_or_fetch_rate returns a row, and nil when there is no rate" do
    observed("USD", "CAD", FRIDAY, "1.4145")

    assert_equal BigDecimal("1.4145"), ExchangeRate.find_or_fetch_rate(from: "USD", to: "CAD", date: SATURDAY).rate
    assert_nil ExchangeRate.find_or_fetch_rate(from: "EUR", to: "CAD", date: SATURDAY)
    assert_equal 1, ExchangeRate.find_or_fetch_rate(from: "CAD", to: "CAD", date: SATURDAY).rate
  end
end
