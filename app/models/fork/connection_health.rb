# One status per connection, highest priority first, with the next action to
# show (design §4.3).
module Fork::ConnectionHealth
  STATUSES = %i[revoked pending_disconnect login_required consent_expiring new_accounts sync_error healthy].freeze
  CONSENT_WARNING_WINDOW = 14.days

  module_function

  def status_for(item, now: Time.current)
    return :revoked if item.revoked_at.present? && item.revoked_kept_at.nil?
    return :pending_disconnect if item.pending_disconnect_at.present? && item.pending_disconnect_at >= now
    return :login_required if item.requires_update?
    return :consent_expiring if item.consent_expires_at.present? && item.consent_expires_at <= now + CONSENT_WARNING_WINDOW
    return :new_accounts if item.new_accounts_available_at.present?
    return :sync_error if item.item_error_code.present?

    :healthy
  end

  # Plaid Items the family should be told about, for the banners.
  def attention_items(family, now: Time.current)
    family.plaid_items.active.ordered.includes(:plaid_accounts).filter_map do |item|
      status = status_for(item, now: now)
      [ item, status ] unless status == :healthy
    end
  end
end
