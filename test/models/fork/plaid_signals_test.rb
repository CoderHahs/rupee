require "test_helper"

class Fork::PlaidSignalsTest < ActiveSupport::TestCase
  setup { @plaid_account = plaid_accounts(:one) }

  test "stores MCC, PFC and authorized date in plaid extra" do
      plaid_transaction = {
        "transaction_id" => "sig1", "merchant_name" => "Shop", "amount" => 5, "date" => Date.current,
        "iso_currency_code" => "USD", "merchant_category_code" => "5411", "authorized_date" => "2026-11-01",
        "personal_finance_category" => { "primary" => "FOOD_AND_DRINK", "detailed" => "FOOD_AND_DRINK_GROCERIES", "confidence_level" => "HIGH" }
      }
      entry = PlaidEntry::Processor.new(plaid_transaction, plaid_account: @plaid_account, category_matcher: stub(match: nil)).process
      plaid = entry.entryable.reload.extra["plaid"]
      assert_equal "5411", plaid["merchant_category_code"]
      assert_equal "FOOD_AND_DRINK_GROCERIES", plaid["pfc_detailed"]
      assert_equal "HIGH", plaid["pfc_confidence_level"]
      assert_equal "2026-11-01", plaid["authorized_date"]
      assert_equal Fork::PlaidSignals.pfc_version, plaid["pfc_version"]
    end

  test "extract leaves out absent values" do
    assert_equal({}, Fork::PlaidSignals.extract({ "transaction_id" => "x" }))
    assert_equal({ "merchant_category_code" => "5411" }, Fork::PlaidSignals.extract({ "merchant_category_code" => 5411 }))
  end
end
