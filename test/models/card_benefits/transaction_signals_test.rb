require "test_helper"

class CardBenefits::TransactionSignalsTest < ActiveSupport::TestCase
  test "reads stored signals and prefers authorized date" do
    entry = Entry.new(date: Date.new(2026, 11, 5), entryable: Transaction.new(extra: { "plaid" => {
      "merchant_category_code" => "5411", "pfc_primary" => "TRAVEL", "pfc_detailed" => "TRAVEL_FLIGHTS",
      "pfc_confidence_level" => "HIGH", "pfc_version" => "v2", "transaction_code" => "purchase",
      "payment_channel" => "in store", "authorized_date" => "2026-11-03"
    } }))
    s = CardBenefits::TransactionSignals.for(entry)
    assert_equal "5411", s.mcc
    assert_equal "TRAVEL", s.pfc_primary
    assert_equal "TRAVEL_FLIGHTS", s.pfc_detailed
    assert_equal "HIGH", s.pfc_confidence
    assert_equal "v2", s.pfc_version
    assert_equal "purchase", s.transaction_code
    assert_equal "in store", s.payment_channel
    assert_equal Date.new(2026, 11, 3), s.effective_date
  end

  test "returns nil and falls back to the entry date when nothing is stored" do
    s = CardBenefits::TransactionSignals.for(Entry.new(date: Date.new(2026, 11, 5), entryable: Transaction.new))
    assert_nil s.mcc
    assert_nil s.authorized_date
    assert_equal Date.new(2026, 11, 5), s.effective_date
  end

  test "never raises on bad input" do
    assert_nil CardBenefits::TransactionSignals.for(nil).mcc
    bad = Entry.new(entryable: Transaction.new(extra: { "plaid" => { "authorized_date" => "nope" } }))
    assert_nil CardBenefits::TransactionSignals.for(bad).authorized_date
  end
end
