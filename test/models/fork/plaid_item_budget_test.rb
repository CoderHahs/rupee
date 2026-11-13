require "test_helper"

class Fork::PlaidItemBudgetTest < ActiveSupport::TestCase
  setup do
    Fork::PlaidItemLedgerEntry.delete_all
    @family = families(:dylan_family)
  end

  def fill_ledger(count, environment: "production")
    count.times do |i|
      Fork::PlaidItemLedgerEntry.create!(plaid_id: "ledger_#{environment}_#{i}_#{SecureRandom.hex(3)}", environment: environment)
    end
  end

  test "guard at 9 Items lets Link open" do
    fill_ledger(9)
    Fork::PlaidItemBudget.stubs(:enforced?).returns(true)

    assert_equal 9, Fork::PlaidItemBudget.used
    assert_equal 1, Fork::PlaidItemBudget.remaining
    assert_not Fork::PlaidItemBudget.blocked?
  end

  test "guard at 10 Items blocks" do
    fill_ledger(10)
    Fork::PlaidItemBudget.stubs(:enforced?).returns(true)

    assert Fork::PlaidItemBudget.blocked?
    assert_equal 0, Fork::PlaidItemBudget.remaining
  end

  test "guard at 11 Items blocks" do
    fill_ledger(11)
    Fork::PlaidItemBudget.stubs(:enforced?).returns(true)

    assert Fork::PlaidItemBudget.blocked?
    assert_equal 0, Fork::PlaidItemBudget.remaining
  end

  test "guard does nothing outside production" do
    fill_ledger(11)

    assert_not Fork::PlaidItemBudget.enforced?
    assert_not Fork::PlaidItemBudget.blocked?
  end

  test "sandbox rows do not count and the cap and elsewhere count come from the environment" do
    fill_ledger(5, environment: "sandbox")
    fill_ledger(2)

    with_env("PLAID_ITEMS_USED_ELSEWHERE" => "3", "PLAID_ITEM_CAP" => "6") do
      assert_equal 5, Fork::PlaidItemBudget.used
      assert_equal 6, Fork::PlaidItemBudget.cap
    end
  end

  test "an invalid cap falls back to the default" do
    with_env("PLAID_ITEM_CAP" => "lots") do
      assert_equal 10, Fork::PlaidItemBudget.cap
    end
  end

  test "creating an Item writes a ledger row and deleting it keeps the row with removed_at" do
    item = @family.plaid_items.create!(name: "Bank", plaid_id: "item_ledger_1", access_token: "tok")
    entry = Fork::PlaidItemLedgerEntry.find_by!(plaid_id: "item_ledger_1")
    assert_equal @family.id, entry.family_id
    assert_equal item.id, entry.plaid_item_id
    assert_nil entry.removed_at

    PlaidItem.any_instance.stubs(:remove_plaid_item)
    item.destroy!

    assert_not_nil entry.reload.removed_at
  end

  test "the ledger row outlives its family" do
    family = Family.create!(name: "Ledger family", currency: "USD", locale: "en", date_format: "%m-%d-%Y")
    family.plaid_items.create!(name: "Bank", plaid_id: "item_ledger_2", access_token: "tok")
    entry = Fork::PlaidItemLedgerEntry.find_by!(plaid_id: "item_ledger_2")

    PlaidItem.any_instance.stubs(:remove_plaid_item)
    family.destroy!

    assert_nil entry.reload.family_id
  end

  test "backfill writes rows for existing Items once" do
    Fork::PlaidItemLedgerEntry.delete_all
    existing = PlaidItem.count

    assert_equal existing, Fork::PlaidItemBudget.backfill!
    assert_equal existing, Fork::PlaidItemLedgerEntry.count
    assert_equal 0, Fork::PlaidItemBudget.backfill!
  end

  private
    def with_env(vars)
      old = vars.keys.index_with { |k| ENV[k] }
      vars.each { |k, v| ENV[k] = v }
      yield
    ensure
      old.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    end
end
