# Prepended to PlaidItem::WebhookProcessor (design §4.3). It records the
# connection-health ITEM webhooks and then calls super, so upstream's handling
# of ITEM_LOGIN_REQUIRED and its 200 response are unchanged (R3.7).
module Fork::PlaidWebhookExtension
  def initialize(webhook_body)
    super
    @fork_payload = JSON.parse(webhook_body)
  end

  def process
    record_connection_health
    super
  end

  private
    def record_connection_health
      return unless webhook_type == "ITEM" && plaid_item

      case webhook_code
      when "PENDING_DISCONNECT" then record_pending_disconnect
      when "PENDING_EXPIRATION" then record_pending_expiration
      when "NEW_ACCOUNTS_AVAILABLE" then record_new_accounts
      when "LOGIN_REPAIRED" then record_login_repaired
      when "USER_PERMISSION_REVOKED" then record_permission_revoked
      when "USER_ACCOUNT_REVOKED" then record_account_revoked
      when "ERROR" then record_item_error
      end
    rescue => e
      # Never let health bookkeeping stop upstream's own handling, or the 200.
      Sentry.capture_exception(e)
      DebugLogEntry.capture(
        category: "plaid_webhook",
        level: "error",
        message: "Connection health webhook failed: #{e.class}: #{e.message}",
        source: "Fork::PlaidWebhookExtension",
        provider_key: "plaid",
        family_id: plaid_item.family_id,
        metadata: { webhook_code: webhook_code, plaid_item_id: plaid_item.id }
      )
    end

    def record_pending_disconnect
      reason = @fork_payload["reason"].presence
      disconnect_at = parse_time(@fork_payload["disconnect_time"])

      attributes = { pending_disconnect_reason: reason, pending_disconnect_at: disconnect_at }
      # US and Canadian consent expiry arrives as this reason.
      attributes[:consent_expires_at] = disconnect_at if reason == "INSTITUTION_TOKEN_EXPIRATION" && disconnect_at
      plaid_item.update!(attributes)

      Fork::ConnectionEvents.emit("connection.pending_disconnect", plaid_item, reason: reason, disconnect_at: disconnect_at)
    end

    # Plaid sends this for UK and EU Items only; handled defensively.
    def record_pending_expiration
      expires_at = parse_time(@fork_payload["consent_expiration_time"])
      return unless expires_at

      plaid_item.update!(consent_expires_at: expires_at)
      Fork::ConnectionEvents.emit("connection.consent_expiring", plaid_item, expires_at: expires_at)
    end

    def record_new_accounts
      plaid_item.update!(new_accounts_available_at: Time.current)
      Fork::ConnectionEvents.emit("connection.new_accounts", plaid_item)
    end

    def record_login_repaired
      plaid_item.update!(
        status: :good,
        item_error_code: nil,
        item_error_reason: nil,
        pending_disconnect_reason: nil,
        pending_disconnect_at: nil
      )
    end

    def record_permission_revoked
      plaid_item.update!(revoked_at: Time.current, revoked_reason: "USER_PERMISSION_REVOKED", revoked_kept_at: nil)
      Fork::ConnectionEvents.emit("connection.revoked", plaid_item, scope: "item")
    end

    def record_account_revoked
      account_id = @fork_payload["account_id"].presence
      accounts = plaid_item.plaid_accounts
      accounts = accounts.where(plaid_id: account_id) if account_id
      accounts.update_all(revoked_at: Time.current)

      Fork::ConnectionEvents.emit("connection.revoked", plaid_item, scope: "account", account_id: account_id)
    end

    # Any error other than the login one is stored for the connections page.
    # ITEM_LOGIN_REQUIRED sets upstream's requires_update status in super.
    def record_item_error
      return unless error.is_a?(Hash)

      code = error["error_code"].presence
      return unless code

      login_required = code == "ITEM_LOGIN_REQUIRED"
      newly_login_required = login_required && !plaid_item.requires_update?

      plaid_item.update!(item_error_code: code, item_error_reason: error["error_code_reason"].presence)
      Fork::ConnectionEvents.emit("connection.login_required", plaid_item) if newly_login_required
    end

    def parse_time(value)
      value.present? ? Time.zone.parse(value.to_s) : nil
    rescue ArgumentError
      nil
    end
end
