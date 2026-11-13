require "test_helper"

class Fork::PlaidWebhookExtensionTest < ActiveSupport::TestCase
  setup do
    @item = plaid_items(:one)
    @events = []
    @subscriber = ActiveSupport::Notifications.subscribe(Fork::ConnectionEvents::NAME) { |*args| @events << args.last }
  end

  teardown do
    ActiveSupport::Notifications.unsubscribe(@subscriber)
  end

  def process(code, extra = {})
    body = { webhook_type: "ITEM", webhook_code: code, item_id: @item.plaid_id }.merge(extra).to_json
    PlaidItem::WebhookProcessor.new(body).process
    @item.reload
  end

  test "PENDING_DISCONNECT stores the reason and time and emits an event" do
    process("PENDING_DISCONNECT", reason: "INSTITUTION_MIGRATION", disconnect_time: "2026-12-01T00:00:00Z")

    assert_equal "INSTITUTION_MIGRATION", @item.pending_disconnect_reason
    assert_equal Time.utc(2026, 12, 1), @item.pending_disconnect_at
    assert_nil @item.consent_expires_at
    assert_equal [ "connection.pending_disconnect" ], @events.map { |e| e[:type] }
    assert_equal :pending_disconnect, Fork::ConnectionHealth.status_for(@item, now: Time.utc(2026, 11, 20))
  end

  test "PENDING_DISCONNECT for token expiration also sets the consent expiry" do
    process("PENDING_DISCONNECT", reason: "INSTITUTION_TOKEN_EXPIRATION", disconnect_time: "2026-12-01T00:00:00Z")

    assert_equal Time.utc(2026, 12, 1), @item.consent_expires_at
  end

  test "PENDING_EXPIRATION stores the consent expiry" do
    process("PENDING_EXPIRATION", consent_expiration_time: "2026-12-15T00:00:00Z")

    assert_equal Time.utc(2026, 12, 15), @item.consent_expires_at
    assert_equal [ "connection.consent_expiring" ], @events.map { |e| e[:type] }
  end

  test "NEW_ACCOUNTS_AVAILABLE sets the timestamp and emits an event" do
    process("NEW_ACCOUNTS_AVAILABLE")

    assert_not_nil @item.new_accounts_available_at
    assert_equal :new_accounts, Fork::ConnectionHealth.status_for(@item)
    assert_equal [ "connection.new_accounts" ], @events.map { |e| e[:type] }
  end

  test "LOGIN_REPAIRED restores good status and clears errors" do
    @item.update!(status: :requires_update, item_error_code: "ITEM_LOGIN_REQUIRED", item_error_reason: "x",
                  pending_disconnect_at: 1.day.from_now, pending_disconnect_reason: "y")

    process("LOGIN_REPAIRED")

    assert @item.good?
    assert_nil @item.item_error_code
    assert_nil @item.item_error_reason
    assert_nil @item.pending_disconnect_at
  end

  test "USER_PERMISSION_REVOKED revokes the Item and removes it from syncable" do
    assert_includes PlaidItem.syncable, @item

    process("USER_PERMISSION_REVOKED")

    assert_not_nil @item.revoked_at
    assert_equal "USER_PERMISSION_REVOKED", @item.revoked_reason
    assert_not_includes PlaidItem.syncable, @item
    assert_equal :revoked, Fork::ConnectionHealth.status_for(@item)
    assert_equal [ "connection.revoked" ], @events.map { |e| e[:type] }
  end

  test "USER_ACCOUNT_REVOKED revokes only the named account and the processor skips it" do
    revoked = @item.plaid_accounts.create!(name: "A", plaid_id: "acc_revoked", plaid_type: "depository", currency: "USD", current_balance: 1)
    other = @item.plaid_accounts.create!(name: "B", plaid_id: "acc_other", plaid_type: "depository", currency: "USD", current_balance: 1)

    process("USER_ACCOUNT_REVOKED", account_id: "acc_revoked")

    assert_not_nil revoked.reload.revoked_at
    assert_nil other.reload.revoked_at
    assert_includes PlaidItem.syncable, @item

    PlaidAccount::Processor.any_instance.expects(:process_account!).never
    PlaidAccount::Processor.new(revoked).process
  end

  test "ERROR with another code stores it and leaves status alone" do
    process("ERROR", error: { error_code: "INTERNAL_SERVER_ERROR", error_code_reason: "boom" })

    assert_equal "INTERNAL_SERVER_ERROR", @item.item_error_code
    assert_equal "boom", @item.item_error_reason
    assert @item.good?
    assert_equal :sync_error, Fork::ConnectionHealth.status_for(@item)
  end

  test "ERROR with ITEM_LOGIN_REQUIRED keeps upstream's requires_update handling" do
    process("ERROR", error: { error_code: "ITEM_LOGIN_REQUIRED" })

    assert @item.requires_update?
    assert_equal "ITEM_LOGIN_REQUIRED", @item.item_error_code
    assert_equal [ "connection.login_required" ], @events.map { |e| e[:type] }
  end

  test "an unhandled code changes nothing and does not raise" do
    assert_nothing_raised { process("SOMETHING_NEW") }

    assert_empty @events
    assert_nil @item.revoked_at
    assert @item.good?
  end

  test "an unknown Item does not raise" do
    body = { webhook_type: "ITEM", webhook_code: "USER_PERMISSION_REVOKED", item_id: "missing" }.to_json

    assert_nothing_raised { PlaidItem::WebhookProcessor.new(body).process }
  end
end
