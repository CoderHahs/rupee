require "test_helper"
require "ostruct"

class Fork::PlaidHealthPollTest < ActiveSupport::TestCase
  setup do
    @item = plaid_items(:one)
    @now = Time.utc(2026, 11, 14, 12)
    @events = []
    @subscriber = ActiveSupport::Notifications.subscribe(Fork::ConnectionEvents::NAME) { |*args| @events << args.last }
  end

  teardown { ActiveSupport::Notifications.unsubscribe(@subscriber) }

  def stub_get_item(item_attrs, status: nil)
    provider = mock
    provider.stubs(:get_item).returns(OpenStruct.new(item: OpenStruct.new(item_attrs), status: status))
    PlaidItem.any_instance.stubs(:plaid_provider).returns(provider)
  end

  test "stores consent expiry, update type and last successful update" do
    stub_get_item(
      { update_type: "background", consent_expiration_time: Time.utc(2027, 3, 1), error: nil },
      status: OpenStruct.new(transactions: OpenStruct.new(last_successful_update: Time.utc(2026, 11, 14, 6)))
    )

    Fork::PlaidHealthPoll.new(now: @now).poll(@item)

    @item.reload
    assert_equal "background", @item.update_type
    assert_equal Time.utc(2027, 3, 1), @item.consent_expires_at
    assert_equal Time.utc(2026, 11, 14, 6), @item.last_successful_update_at
    assert_equal @now, @item.health_checked_at
    assert_empty @events
  end

  test "ITEM_LOGIN_REQUIRED sets requires_update and emits one event" do
    stub_get_item({ update_type: "background", consent_expiration_time: nil,
                    error: OpenStruct.new(error_code: "ITEM_LOGIN_REQUIRED", error_code_reason: "OAUTH_STATE_ID_EXPIRED") })

    Fork::PlaidHealthPoll.new(now: @now).poll(@item)

    assert @item.reload.requires_update?
    assert_equal "ITEM_LOGIN_REQUIRED", @item.item_error_code
    assert_equal [ "connection.login_required" ], @events.map { |e| e[:type] }
  end

  test "consent ending within 14 days emits an event" do
    stub_get_item({ update_type: "background", consent_expiration_time: @now + 10.days, error: nil })

    Fork::PlaidHealthPoll.new(now: @now).poll(@item)

    assert_equal [ "connection.consent_expiring" ], @events.map { |e| e[:type] }
    assert_equal :consent_expiring, Fork::ConnectionHealth.status_for(@item.reload, now: @now)
  end

  test "a failing Item is counted and does not stop the run" do
    provider = mock
    provider.stubs(:get_item).raises(StandardError, "boom")
    PlaidItem.any_instance.stubs(:plaid_provider).returns(provider)

    result = Fork::PlaidHealthPoll.run(now: @now)

    assert_equal PlaidItem.active.count, result[:failed]
    assert_equal 0, result[:checked]
  end

  test "revoked Items are not polled" do
    @item.update!(revoked_at: 1.day.ago)
    PlaidItem.any_instance.expects(:plaid_provider).never

    Fork::PlaidHealthPoll.run(now: @now)
  end

  test "the job is scheduled as fork:plaid_health_poll" do
    entries = Fork::Schedule.read(Rails.root.join(Fork::Schedule::PATH))

    assert_equal "Fork::PlaidHealthPollJob", entries.fetch("fork:plaid_health_poll")["class"]
  end
end
