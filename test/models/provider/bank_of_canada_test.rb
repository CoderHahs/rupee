require "test_helper"

class Provider::BankOfCanadaTest < ActiveSupport::TestCase
  VALET = "https://www.bankofcanada.ca/valet/observations/FXUSDCAD/json".freeze

  setup do
    @provider = Provider::BankOfCanada.new
    @provider.stubs(:throttle_request)
  end

  def stub_valet(observations, status: 200)
    stub_request(:get, VALET)
      .with(query: hash_including({}))
      .to_return(status: status, body: { observations: observations }.to_json, headers: { "Content-Type" => "application/json" })
  end

  test "knows which pairs it serves" do
    assert Provider::BankOfCanada.supports?("USD", "CAD")
    assert Provider::BankOfCanada.supports?("CAD", "USD")
    assert_not Provider::BankOfCanada.supports?("USD", "EUR")
    assert_not Provider::BankOfCanada.supports?("CAD", "XYZ")
    assert_equal 27, Provider::BankOfCanada::CURRENCIES.size
  end

  test "foreign to CAD is the published value" do
    stub_valet([ { "d" => "2026-09-24", "FXUSDCAD" => { "v" => "1.4100" } }, { "d" => "2026-09-25", "FXUSDCAD" => { "v" => "1.4145" } } ])

    response = @provider.fetch_exchange_rates(from: "USD", to: "CAD", start_date: Date.new(2026, 9, 24), end_date: Date.new(2026, 9, 25))

    assert response.success?
    assert_equal [ Date.new(2026, 9, 24), Date.new(2026, 9, 25) ], response.data.map(&:date)
    assert_equal BigDecimal("1.4145"), response.data.last.rate
    assert_equal "bank_of_canada", response.data.last.source
  end

  test "CAD to foreign is 1 divided by the value, rounded to 12 places" do
    stub_valet([ { "d" => "2026-09-25", "FXUSDCAD" => { "v" => "1.4145" } } ])

    rate = @provider.fetch_exchange_rate(from: "CAD", to: "USD", date: Date.new(2026, 9, 25)).data

    assert_equal (BigDecimal("1") / BigDecimal("1.4145")).round(12), rate.rate
    assert_equal "USD", rate.to
  end

  test "a single date returns the latest observation under its own date" do
    stub_valet([ { "d" => "2026-09-24", "FXUSDCAD" => { "v" => "1.4100" } }, { "d" => "2026-09-25", "FXUSDCAD" => { "v" => "1.4145" } } ])

    rate = @provider.fetch_exchange_rate(from: "USD", to: "CAD", date: Date.new(2026, 9, 26)).data

    assert_equal Date.new(2026, 9, 25), rate.date
    assert_requested(:get, VALET, query: { "start_date" => "2026-09-19", "end_date" => "2026-09-26" })
  end

  test "a single date with no observation is an error" do
    stub_valet([])

    response = @provider.fetch_exchange_rate(from: "USD", to: "CAD", date: Date.new(2026, 9, 26))

    assert_not response.success?
  end

  test "a pair without a series is an error and makes no request" do
    response = @provider.fetch_exchange_rates(from: "USD", to: "EUR", start_date: Date.new(2026, 9, 1), end_date: Date.new(2026, 9, 2))

    assert_not response.success?
  end

  test "an HTTP error is a failed response" do
    stub_request(:get, VALET).with(query: hash_including({})).to_return(status: 500, body: "")
    @provider.stubs(:client).returns(Faraday.new { |f| f.response :raise_error })

    assert_not @provider.fetch_exchange_rate(from: "USD", to: "CAD", date: Date.new(2026, 9, 25)).success?
  end
end
