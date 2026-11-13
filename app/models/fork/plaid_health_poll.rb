# Polls Plaid for every Item's health (design §4.3, R3.1): the error, the
# consent expiry, the update type and the last successful update. It is the
# backstop for webhooks that never arrive.
class Fork::PlaidHealthPoll
  CONSENT_LEAD = 14.days

  def self.run(now: Time.current)
    new(now: now).run
  end

  def initialize(now: Time.current)
    @now = now
  end

  # Returns { checked:, failed: }.
  def run
    result = { checked: 0, failed: 0 }

    PlaidItem.active.where(revoked_at: nil).find_each do |item|
      poll(item)
      result[:checked] += 1
    rescue => e
      result[:failed] += 1
      report_failure(item, e)
    end

    result
  end

  def poll(item)
    response = item.plaid_provider.get_item(item.access_token)
    plaid_item = response.item
    error = plaid_item.respond_to?(:error) ? plaid_item.error : nil
    transactions_status = response.respond_to?(:status) ? response.status&.transactions : nil

    attributes = {
      health_checked_at: now,
      update_type: plaid_item.update_type.presence,
      consent_expires_at: to_time(plaid_item.consent_expiration_time),
      item_error_code: error&.error_code.presence,
      item_error_reason: error.respond_to?(:error_code_reason) ? error.error_code_reason.presence : nil
    }
    last_update = to_time(transactions_status&.last_successful_update)
    attributes[:last_successful_update_at] = last_update if last_update
    attributes[:status] = :requires_update if error&.error_code == "ITEM_LOGIN_REQUIRED"

    was_requires_update = item.requires_update?
    item.update!(attributes)

    Fork::ConnectionEvents.emit("connection.login_required", item) if item.requires_update? && !was_requires_update
    emit_consent_expiring(item)
    item
  end

  private
    attr_reader :now

    def emit_consent_expiring(item)
      return unless item.consent_expires_at && item.consent_expires_at <= now + CONSENT_LEAD

      Fork::ConnectionEvents.emit("connection.consent_expiring", item, expires_at: item.consent_expires_at)
    end

    def to_time(value)
      return nil if value.blank?

      value.respond_to?(:to_time) ? value.to_time : Time.zone.parse(value.to_s)
    end

    def report_failure(item, error)
      Sentry.capture_exception(error)
      DebugLogEntry.capture(
        category: "plaid_health_poll",
        level: "error",
        message: "Plaid health poll failed: #{error.class}: #{error.message}",
        source: "Fork::PlaidHealthPoll",
        provider_key: "plaid",
        family_id: item.family_id,
        metadata: { plaid_item_id: item.id }
      )
    end
end
