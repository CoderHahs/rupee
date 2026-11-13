require "test_helper"

class Fork::PlaidSignalsBackfillTest < ActiveSupport::TestCase
  setup do
    @plaid_account = plaid_accounts(:one)
    @item = @plaid_account.plaid_item
    @account = @plaid_account.current_account || accounts(:depository).tap { |a| a.update_columns(plaid_account_id: @plaid_account.id) }
    @entry = create_entry("txn_1", 25)
    @other = create_entry("txn_2", 40)
    @plaid_txn = {
      "transaction_id" => "txn_1", "account_id" => @plaid_account.plaid_id, "iso_currency_code" => "USD",
      "merchant_category_code" => "5411", "authorized_date" => "2026-11-01",
      "personal_finance_category" => { "primary" => "FOOD_AND_DRINK", "detailed" => "FOOD_AND_DRINK_GROCERIES", "confidence_level" => "HIGH" }
    }
    @unmatched = { "transaction_id" => "gone", "account_id" => @plaid_account.plaid_id, "iso_currency_code" => "USD" }
  end

  test "merges signals without changing counts or sums and runs no callbacks" do
    stub_plaid([ @plaid_txn, @unmatched ])
    count, sum = @account.entries.count, @account.entries.sum(:amount)
    Entry.any_instance.expects(:save).never
    Account.any_instance.expects(:sync_later).never
    cursor = @item.next_cursor

    report = Fork::PlaidSignalsBackfill.new(items: PlaidItem.where(id: @item.id)).run

    assert_equal [ count, sum ], [ @account.entries.count, @account.entries.sum(:amount) ]
    assert_equal 1, report.updated
    assert_equal 1, report.unmatched
    plaid = @entry.entryable.reload.extra["plaid"]
    assert_equal "5411", plaid["merchant_category_code"]
    assert_equal "FOOD_AND_DRINK", plaid["pfc_primary"]
    assert_equal "2026-11-01", plaid["authorized_date"]
    assert_equal Fork::PlaidSignals.pfc_version, plaid["pfc_version"]
    assert_equal "keep", plaid["original_description"]
    assert_equal cursor, @item.reload.next_cursor
    assert_nil @other.entryable.reload.extra["plaid"]
  end

  test "fill rate report" do
    stub_plaid([ @plaid_txn, @unmatched ])
    report = Fork::PlaidSignalsBackfill.new(items: PlaidItem.where(id: @item.id)).run
    row = report.fill_rates.first
    assert_equal 2, row[:transactions]
    assert_equal 50.0, row[:rates]["merchant_category_code"]
    assert_includes report.to_s, "Fill rate"
  end

  test "defers an item that is syncing" do
    PlaidItem.any_instance.stubs(:syncing?).returns(true)
    PlaidItem.any_instance.expects(:plaid_provider).never
    report = Fork::PlaidSignalsBackfill.new(items: PlaidItem.where(id: @item.id)).run
    assert_equal [ @item.id ], report.items_deferred
  end

  test "rolls back an account whose count or sum changed" do
    stub_plaid([ @plaid_txn ])
    Fork::PlaidSignalsBackfill.any_instance.stubs(:fingerprint).returns([ 1, 1 ], [ 2, 1 ])
    report = Fork::PlaidSignalsBackfill.new(items: PlaidItem.where(id: @item.id)).run
    assert_equal [ @account.id ], report.rolled_back_accounts
    assert_equal "keep", @entry.entryable.reload.extra["plaid"]["original_description"]
    assert_nil @entry.entryable.extra["plaid"]["pfc_primary"]
  end

  private
    def stub_plaid(txns)
      response = Provider::Plaid::TransactionSyncResponse.new(added: txns, modified: [], removed: [], cursor: "c")
      provider = mock("plaid")
      provider.stubs(:get_transactions).returns(response)
      PlaidItem.any_instance.stubs(:plaid_provider).returns(provider)
    end

    def create_entry(external_id, amount)
      txn = Transaction.new(extra: { "plaid" => { "original_description" => "keep" } })
      txn = Transaction.new if external_id == "txn_2"
      @account.entries.create!(name: external_id, date: Date.current, amount: amount, currency: "USD",
                               external_id: external_id, source: "plaid", entryable: txn)
    end
end
