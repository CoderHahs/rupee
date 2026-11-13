require "test_helper"

class Provider::FxRouterTest < ActiveSupport::TestCase
  include ProviderTestHelper

  setup do
    @valet = mock("valet")
    @frankfurter = mock("frankfurter")
    @router = Provider::FxRouter.new(bank_of_canada: @valet, frankfurter: @frankfurter)
  end

  def rate(date, from, to, value)
    Provider::ExchangeRateConcept::Rate.new(date: date, from: from, to: to, rate: value)
  end

  def sourced(date, value)
    Fork::SourcedRate.new(date: date, from: "USD", to: "CAD", rate: value, source: "bank_of_canada")
  end

  test "a CAD pair with a series goes to the Bank of Canada" do
    @valet.expects(:fetch_exchange_rate).returns(provider_success_response(sourced(Date.new(2026, 9, 25), 1.4145)))
    @frankfurter.expects(:fetch_exchange_rate).never

    assert_equal "bank_of_canada", @router.fetch_exchange_rate(from: "USD", to: "CAD", date: Date.new(2026, 9, 25)).data.source
  end

  test "every other pair goes to Frankfurter and is tagged" do
    @valet.expects(:fetch_exchange_rates).never
    @frankfurter.expects(:fetch_exchange_rates).returns(provider_success_response([ rate(Date.new(2026, 9, 25), "USD", "EUR", 0.85) ]))

    data = @router.fetch_exchange_rates(from: "USD", to: "EUR", start_date: Date.new(2026, 9, 25), end_date: Date.new(2026, 9, 25)).data

    assert_equal "frankfurter", data.first.source
  end

  test "an unlisted currency paired with CAD goes to Frankfurter" do
    @valet.expects(:fetch_exchange_rate).never
    @frankfurter.expects(:fetch_exchange_rate).returns(provider_success_response(rate(Date.new(2026, 9, 25), "AED", "CAD", 0.38)))

    assert_equal "frankfurter", @router.fetch_exchange_rate(from: "AED", to: "CAD", date: Date.new(2026, 9, 25)).data.source
  end

  test "falls back to Frankfurter when Valet errors" do
    @valet.expects(:fetch_exchange_rates).returns(provider_error_response(StandardError.new("down")))
    @frankfurter.expects(:fetch_exchange_rates).returns(provider_success_response([ rate(Date.new(2026, 9, 25), "USD", "CAD", 1.41) ]))

    data = @router.fetch_exchange_rates(from: "USD", to: "CAD", start_date: Date.new(2026, 9, 25), end_date: Date.new(2026, 9, 25)).data

    assert_equal "frankfurter", data.first.source
  end

  test "falls back to Frankfurter when Valet returns nothing" do
    @valet.expects(:fetch_exchange_rate).returns(provider_error_response(StandardError.new("none")))
    @frankfurter.expects(:fetch_exchange_rate).returns(provider_success_response(rate(Date.new(2026, 9, 25), "USD", "CAD", 1.41)))

    assert_equal "frankfurter", @router.fetch_exchange_rate(from: "USD", to: "CAD", date: Date.new(2026, 9, 25)).data.source
  end

  test "uses Frankfurter for the part of a range more than 7 days before Valet's first observation" do
    first = Date.new(2026, 9, 20)
    @valet.expects(:fetch_exchange_rates).returns(provider_success_response([ sourced(first, 1.40), sourced(first + 1, 1.41) ]))
    @frankfurter.expects(:fetch_exchange_rates)
                .with(from: "USD", to: "CAD", start_date: Date.new(2026, 9, 1), end_date: first - 1)
                .returns(provider_success_response([ rate(Date.new(2026, 9, 1), "USD", "CAD", 1.30) ]))

    data = @router.fetch_exchange_rates(from: "USD", to: "CAD", start_date: Date.new(2026, 9, 1), end_date: first + 1).data

    assert_equal %w[frankfurter bank_of_canada bank_of_canada], data.map(&:source)
  end
end
