# Connection events (design §4.10). The notification tables belong to task 17,
# so for now an event is an ActiveSupport::Notifications message and a log
# line. Task 17 subscribes to "fork.connection_event" and writes
# notification_events rows from it; callers do not change.
#
# Types: connection.consent_expiring, connection.pending_disconnect,
# connection.login_required, connection.new_accounts, connection.revoked.
module Fork::ConnectionEvents
  NAME = "fork.connection_event"

  TYPES = %w[
    connection.consent_expiring
    connection.pending_disconnect
    connection.login_required
    connection.new_accounts
    connection.revoked
  ].freeze

  module_function

  def emit(type, plaid_item, **details)
    raise ArgumentError, "unknown connection event #{type}" unless TYPES.include?(type)

    payload = { type: type, plaid_item_id: plaid_item.id, family_id: plaid_item.family_id, owner_id: plaid_item.owner_id }.merge(details)
    Rails.logger.info("[Fork::ConnectionEvents] #{type} item=#{plaid_item.id}")
    ActiveSupport::Notifications.instrument(NAME, payload)
    payload
  end
end
