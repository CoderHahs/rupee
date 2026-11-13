# frozen_string_literal: true

# Connection health (design §4.3, §5.5). Every column is nullable with no
# default, so the migration changes only the catalog.
class ForkAddHealthColumnsToPlaidItems < ActiveRecord::Migration[8.1]
  def change
    change_table :plaid_items, bulk: true do |t|
      t.datetime :health_checked_at
      t.datetime :consent_expires_at
      t.string :update_type
      t.string :item_error_code
      t.string :item_error_reason
      t.datetime :last_successful_update_at
      t.string :pending_disconnect_reason
      t.datetime :pending_disconnect_at
      t.datetime :new_accounts_available_at
      t.datetime :revoked_at
      t.string :revoked_reason
      # Set when a member chooses to keep a revoked Item's data as history, so
      # the prompt stops. Not in the design's column list; see the task report.
      t.datetime :revoked_kept_at
    end

    add_column :plaid_accounts, :revoked_at, :datetime
  end
end
