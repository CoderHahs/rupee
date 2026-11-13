# /connections: every provider connection with its status and next action,
# plus the Plaid Item budget (design §4.3, R3.8).
class Fork::ConnectionsController < ApplicationController
  before_action :set_plaid_item, only: :keep

  def index
    @budget = { used: Fork::PlaidItemBudget.used, cap: Fork::PlaidItemBudget.cap }
    @rows = connection_rows
  end

  # Keep a revoked Item's accounts and history; it stays out of `syncable`.
  def keep
    @plaid_item.update!(revoked_kept_at: Time.current)
    redirect_back_or_to connections_path, notice: t(".kept")
  end

  private
    def set_plaid_item
      @plaid_item = Current.family.plaid_items.find(params[:id])
      redirect_to connections_path, alert: t("fork.connections.not_allowed") unless @plaid_item.manageable_by?(Current.user)
    end

    def connection_rows
      plaid_items = Current.family.plaid_items.includes(:plaid_accounts).index_by(&:id)

      ProviderConnectionStatus.for_family(Current.family).filter_map do |row|
        if row[:provider] == "plaid"
          item = plaid_items[row[:id]]
          next unless item&.manageable_by?(Current.user) || item&.owned_by?(Current.user)

          row.merge(plaid_item: item, health: Fork::ConnectionHealth.status_for(item), last_success_at: item.last_successful_update_at || row.dig(:sync, :last_synced_at))
        else
          next unless Current.user.admin?

          row.merge(plaid_item: nil, health: generic_health(row), last_success_at: row.dig(:sync, :last_synced_at))
        end
      end
    end

    def generic_health(row)
      return :login_required if row[:requires_update]
      return :sync_error if row[:status].to_s.in?(%w[error failed])

      :healthy
    end
end
