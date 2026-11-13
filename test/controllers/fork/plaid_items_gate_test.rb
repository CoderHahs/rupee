require "test_helper"

class Fork::PlaidItemsGateTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:family_admin)
    Fork::PlaidItemLedgerEntry.delete_all
    Fork::PlaidItemBudget.stubs(:enforced?).returns(true)
  end

  def fill_ledger(count)
    count.times { |i| Fork::PlaidItemLedgerEntry.create!(plaid_id: "gate_#{i}", environment: "production") }
  end

  test "new opens Link at 9 Items" do
    fill_ledger(9)
    Family.any_instance.expects(:get_link_token).returns("link-token")

    get new_plaid_item_url(accountable_type: "Depository")

    assert_response :success
    assert_no_match(/Plaid Item limit reached/, response.body)
  end

  test "new explains the budget at 10 Items and does not request a link token" do
    fill_ledger(10)
    Family.any_instance.expects(:get_link_token).never

    get new_plaid_item_url(accountable_type: "Depository")

    assert_response :success
    assert_match(/10 of 10 Plaid Items are used/, response.body)
  end

  test "new explains the budget at 11 Items" do
    fill_ledger(11)
    Family.any_instance.expects(:get_link_token).never

    get new_plaid_item_url

    assert_match(/Plaid Item limit reached/, response.body)
  end

  test "edit is never guarded" do
    fill_ledger(11)
    PlaidItem.any_instance.expects(:get_update_link_token).returns("update-token")

    get edit_plaid_item_url(plaid_items(:one))

    assert_response :success
  end

  test "edit with add_accounts clears the new accounts prompt" do
    item = plaid_items(:one)
    item.update!(new_accounts_available_at: Time.current)
    PlaidItem.any_instance.stubs(:get_update_link_token).returns("update-token")

    get edit_plaid_item_url(item, add_accounts: true)

    assert_nil item.reload.new_accounts_available_at
  end
end
