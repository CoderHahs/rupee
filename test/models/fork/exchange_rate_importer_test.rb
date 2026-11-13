require "test_helper"

class Fork::ExchangeRateImporterTest < ActiveSupport::TestCase
  include ProviderTestHelper

  setup do
    ExchangeRate.delete_all
    @provider = mock("provider")
    @provider.stubs(:max_history_days).returns(nil)
    Setting.stubs(:exchange_rate_provider).returns("fx_router")
  end

  def sourced(date, rate)
    Fork::SourcedRate.new(date: date, from: "USD", to: "CAD", rate: rate, source: "bank_of_canada")
  end

  def import(start_date, end_date)
    ExchangeRate::Importer.new(exchange_rate_provider: @provider, from: "USD", to: "CAD", start_date: start_date, end_date: end_date).import_provider_rates
  end

  test "observed rows carry their own date and source; filled and inverse rows copy the carried observation" do
    friday = Date.current.beginning_of_week + 4.days - 7
    saturday = friday + 1
    @provider.stubs(:fetch_exchange_rates).returns(provider_success_response([ sourced(friday, 1.4145) ]))

    import(friday, saturday)

    fri = ExchangeRate.find_by!(from_currency: "USD", to_currency: "CAD", date: friday)
    sat = ExchangeRate.find_by!(from_currency: "USD", to_currency: "CAD", date: saturday)
    assert_equal [ friday, "bank_of_canada" ], [ fri.observed_on, fri.source ]
    assert_equal [ friday, "bank_of_canada" ], [ sat.observed_on, sat.source ]
    inverse = ExchangeRate.find_by!(from_currency: "CAD", to_currency: "USD", date: saturday)
    assert_equal [ friday, "bank_of_canada" ], [ inverse.observed_on, inverse.source ]
  end

  test "a rate without a source takes the configured provider name" do
    day = Date.current - 10
    plain = Provider::ExchangeRateConcept::Rate.new(date: day, from: "USD", to: "CAD", rate: 1.3)
    @provider.stubs(:fetch_exchange_rates).returns(provider_success_response([ plain ]))

    import(day, day)

    assert_equal "fx_router", ExchangeRate.find_by!(from_currency: "USD", to_currency: "CAD", date: day).source
  end

  test "a filled row dated today is re-fetched until the rate is published" do
    yesterday = Date.current - 1
    today = Date.current
    ExchangeRate.create!(from_currency: "USD", to_currency: "CAD", date: yesterday, rate: 1.40, observed_on: yesterday, source: "bank_of_canada")
    ExchangeRate.create!(from_currency: "USD", to_currency: "CAD", date: today, rate: 1.40, observed_on: yesterday, source: "bank_of_canada")
    @provider.expects(:fetch_exchange_rates).once.returns(provider_success_response([ sourced(yesterday, 1.40), sourced(today, 1.41) ]))

    import(yesterday, today)

    row = ExchangeRate.find_by!(from_currency: "USD", to_currency: "CAD", date: today)
    assert_equal BigDecimal("1.41"), row.rate
    assert_equal today, row.observed_on
  end

  test "observed rows dated today are not re-fetched" do
    today = Date.current
    ExchangeRate.create!(from_currency: "USD", to_currency: "CAD", date: today, rate: 1.41, observed_on: today, source: "bank_of_canada")
    ExchangeRate.create!(from_currency: "CAD", to_currency: "USD", date: today, rate: 0.709219858156, observed_on: today, source: "bank_of_canada")
    @provider.expects(:fetch_exchange_rates).never

    import(today, today)
  end
end
