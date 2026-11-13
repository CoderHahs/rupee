require "test_helper"
require "ostruct"

class Fork::SecurityPriceObservationTest < ActiveSupport::TestCase
  include ProviderTestHelper

  setup do
    @security = Security.create!(ticker: "OBS#{SecureRandom.hex(3)}")
  end

  test "a saved price is observed on its own date" do
    price = Security::Price.create!(security: @security, date: 3.days.ago.to_date, price: 10, currency: "CAD")

    assert_equal price.date, price.observed_on
  end

  test "a corrected price gets a new observation date, an unchanged one keeps its own" do
    price = Security::Price.create!(security: @security, date: Date.current, price: 10, currency: "CAD")
    price.update_column(:observed_on, 5.days.ago.to_date)

    price.update!(provisional: true)
    assert_equal 5.days.ago.to_date, price.observed_on

    price.update!(price: 11)
    assert_equal Date.current, price.observed_on
  end

  test "the importer writes observed_on and a carried row keeps the carried date" do
    friday = Date.current.prev_occurring(:friday)
    sunday = friday + 2
    provider = mock
    provider.stubs(:fetch_security_prices).returns(provider_success_response([
      OpenStruct.new(date: friday, price: 20, currency: "CAD")
    ]))

    Security::Price::Importer.new(
      security: @security, security_provider: provider, start_date: friday, end_date: [ sunday, Date.current ].min
    ).import_provider_prices

    rows = @security.prices.order(:date)
    assert rows.any?
    assert rows.none? { |r| r.observed_on.nil? }
    assert_equal friday, rows.first.observed_on
    assert rows.all? { |r| r.observed_on == friday }
  end

  test "the backfill leaves no null observed_on" do
    old = Security::Price.create!(security: @security, date: 10.days.ago.to_date, price: 5, currency: "CAD")
    carried = Security::Price.create!(security: @security, date: 8.days.ago.to_date, price: 5, currency: "CAD", provisional: true)
    orphan = Security::Price.create!(security: @security, date: 2.days.ago.to_date, price: 6, currency: "USD", provisional: true)
    Security::Price.where(id: [ old.id, carried.id, orphan.id ]).update_all(observed_on: nil)

    dry = Fork::PriceObservedOnBackfill.run!(dry_run: true)
    assert_operator dry.remaining_null, :>=, 3

    result = Fork::PriceObservedOnBackfill.run!

    assert_equal 0, result.remaining_null
    assert_equal 0, Security::Price.where(observed_on: nil).count
    assert_equal old.date, old.reload.observed_on
    assert_equal old.date, carried.reload.observed_on
    assert_equal orphan.date, orphan.reload.observed_on
  end
end
