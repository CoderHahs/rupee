require "test_helper"

class Fork::NetWorthByCurrencyTest < ActiveSupport::TestCase
  setup do
    @family = families(:empty)
    @family.update!(currency: "CAD")
    ExchangeRate.delete_all
    Rails.cache.clear
    ExchangeRate.stubs(:provider).returns(nil)
  end

  teardown { Fork::RequestFx.reset }

  test "assets minus liabilities per currency, converted where a rate exists" do
    @family.accounts.create!(name: "CAD", balance: 1000, currency: "CAD", accountable: Depository.new)
    @family.accounts.create!(name: "USD", balance: 500, currency: "USD", accountable: Depository.new)
    @family.accounts.create!(name: "USD card", balance: 100, currency: "USD", accountable: CreditCard.new)
    @family.accounts.create!(name: "EUR", balance: 50, currency: "EUR", accountable: Depository.new)
    ExchangeRate.create!(from_currency: "USD", to_currency: "CAD", date: Date.current, rate: 1.4, observed_on: Date.current)

    breakdown = Fork::NetWorthByCurrency.new(@family)
    rows = breakdown.rows.index_by(&:currency)

    assert breakdown.multi_currency?
    assert_equal %w[CAD EUR USD], breakdown.rows.map(&:currency).sort
    assert_equal 400, rows["USD"].native.amount
    assert_equal 560, rows["USD"].converted.amount
    assert_not rows["EUR"].converted?
    assert_equal 1000, rows["CAD"].converted.amount
  end
end
