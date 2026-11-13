require "test_helper"

class Fork::ConnectionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:family_admin)
    @item = plaid_items(:one)
    sign_in @admin
  end

  test "lists connections with the budget and status" do
    @item.update!(status: :requires_update)

    get connections_path

    assert_response :success
    assert_match(/of 10 Plaid Items used/, response.body)
    assert_match(/Test Bank/, response.body)
    assert_match(/Login required/, response.body)
    assert_select "a[href=?]", edit_plaid_item_path(@item)
  end

  test "a revoked Item offers delete and keep, and keep removes the prompt" do
    @item.update!(revoked_at: Time.current, revoked_reason: "USER_PERMISSION_REVOKED")

    get connections_path
    assert_match(/Revoked/, response.body)
    assert_select "a[href=?]", keep_connection_path(@item)

    post keep_connection_path(@item)
    assert_redirected_to connections_path
    assert_not_nil @item.reload.revoked_kept_at
    assert_equal :healthy, Fork::ConnectionHealth.status_for(@item)
    assert_not_includes PlaidItem.syncable, @item
  end

  test "a banner appears on other pages for a connection needing attention" do
    @item.update!(new_accounts_available_at: Time.current)

    get root_path

    assert_match(/has new accounts/, response.body)
  end

  test "a member cannot keep someone else's Item" do
    sign_in users(:family_member)

    post keep_connection_path(@item)

    assert_redirected_to connections_path
    assert_nil @item.reload.revoked_kept_at
  end

  test "the chooser lists brokerage connectors above Plaid for investments" do
    configs = [ { key: "plaid_us" }, { key: "snaptrade" }, { key: "questrade" } ]
    Provider::Factory.stubs(:adapters_for_account_type).returns([])
    stub_adapter = Class.new { define_singleton_method(:connection_configs) { |family:| configs } }
    Provider::Factory.stubs(:adapters_for_account_type).with("Investment").returns([ stub_adapter ])

    ordered = Provider::Factory.connection_configs_for_account_type(account_type: "Investment", family: @admin.family)

    assert_equal %w[snaptrade questrade plaid_us], ordered.map { |c| c[:key] }
  end

  test "the chooser order is unchanged for banks" do
    configs = [ { key: "plaid_us" }, { key: "snaptrade" } ]
    stub_adapter = Class.new { define_singleton_method(:connection_configs) { |family:| configs } }
    Provider::Factory.stubs(:adapters_for_account_type).with("Depository").returns([ stub_adapter ])

    ordered = Provider::Factory.connection_configs_for_account_type(account_type: "Depository", family: @admin.family)

    assert_equal %w[plaid_us snaptrade], ordered.map { |c| c[:key] }
  end
end
