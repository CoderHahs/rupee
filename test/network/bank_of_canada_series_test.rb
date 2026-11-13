require "test_helper"

# Runs only in the nightly job (.github/workflows/fork-nightly.yml), outside
# WebMock: a renamed Valet series must fail the build instead of turning into
# missing rates (design §8).
class BankOfCanadaSeriesTest < ActiveSupport::TestCase
  setup do
    skip "network tests run nightly with FORK_NETWORK_TESTS=1" unless ENV["FORK_NETWORK_TESTS"] == "1"
    WebMock.allow_net_connect!
    VCR.turn_off!(ignore_cassettes: true)
  end

  teardown do
    VCR.turn_on!
    WebMock.disable_net_connect!(allow_localhost: true)
  end

  test "Valet's FX_RATES_DAILY group still has the 27 series the router maps" do
    body = JSON.parse(Faraday.get("https://www.bankofcanada.ca/valet/groups/FX_RATES_DAILY/json").body)
    series = (body["seriesDetail"] || body.dig("groupDetail", "seriesDetail") || {}).keys

    expected = Provider::BankOfCanada::CURRENCIES.map { |c| "FX#{c}CAD" }
    assert_empty expected - series, "series removed from Valet"
  end

  test "Frankfurter answers" do
    assert Provider::Frankfurter.new.healthy?.success?
  end
end
