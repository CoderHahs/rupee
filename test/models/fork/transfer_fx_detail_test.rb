require "test_helper"

class Fork::TransferFxDetailTest < ActiveSupport::TestCase
  DATE = Date.new(2026, 9, 25)

  setup do
    @family = families(:dylan_family)
    @cad = @family.accounts.create!(name: "CAD chequing", balance: 5000, currency: "CAD", accountable: Depository.new)
    @usd = @family.accounts.create!(name: "USD chequing", balance: 100, currency: "USD", accountable: Depository.new)
    ExchangeRate.delete_all
    Rails.cache.clear
    ExchangeRate.stubs(:provider).returns(nil)
  end

  def transfer_with(rate: nil)
    if rate
      ExchangeRate.create!(from_currency: "CAD", to_currency: "USD", date: DATE, rate: (BigDecimal("1") / rate).round(12), observed_on: DATE, source: "bank_of_canada")
    end
    outflow = Transaction.new(kind: "funds_movement")
    inflow = Transaction.new(kind: "funds_movement")
    outflow.build_entry(account: @cad, name: "Out", date: DATE, amount: 1420, currency: "CAD")
    inflow.build_entry(account: @usd, name: "In", date: DATE, amount: -1000, currency: "USD")
    Transfer.create!(outflow_transaction: outflow, inflow_transaction: inflow, amount: 1000)
  end

  test "6.2: records the implied rate, the reference and a spread of -38.7 bps" do
    detail = transfer_with(rate: BigDecimal("1.4145")).fx_detail

    assert_equal "CAD", detail.outflow_currency
    assert_equal "USD", detail.inflow_currency
    assert_equal 1420, detail.outflow_amount
    assert_equal 1000, detail.inflow_amount
    assert_in_delta 0.704225, detail.implied_rate, 1e-6
    assert_in_delta 0.706964, detail.reference_rate, 1e-6
    assert_equal "bank_of_canada", detail.reference_source
    assert_equal DATE, detail.reference_observed_on
    assert_equal BigDecimal("-38.7"), detail.spread_bps
    assert detail.below_reference?
    assert_equal BigDecimal("0.39"), detail.spread_percent
  end

  test "without a reference rate the spread is not provided" do
    detail = transfer_with.fx_detail

    assert_in_delta 0.704225, detail.implied_rate, 1e-6
    assert_nil detail.reference_rate
    assert_nil detail.spread_bps
  end

  test "a same-currency transfer records nothing" do
    other = @family.accounts.create!(name: "More CAD", balance: 100, currency: "CAD", accountable: Depository.new)
    outflow = Transaction.new(kind: "funds_movement")
    inflow = Transaction.new(kind: "funds_movement")
    outflow.build_entry(account: @cad, name: "Out", date: DATE, amount: 100, currency: "CAD")
    inflow.build_entry(account: other, name: "In", date: DATE, amount: -100, currency: "CAD")

    assert_no_difference "Fork::TransferFxDetail.count" do
      Transfer.create!(outflow_transaction: outflow, inflow_transaction: inflow, amount: 100)
    end
  end

  test "the details go when the transfer goes" do
    transfer = transfer_with(rate: BigDecimal("1.4145"))

    assert_difference "Fork::TransferFxDetail.count", -1 do
      transfer.destroy!
    end
  end
end
