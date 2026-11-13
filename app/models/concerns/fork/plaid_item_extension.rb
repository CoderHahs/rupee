# Fork additions to PlaidItem, applied in config/initializers/fork.rb so
# plaid_item.rb stays unedited (design §4.1): the Item ledger (§4.2) and the
# connection health columns (§4.3).
module Fork::PlaidItemExtension
  extend ActiveSupport::Concern

  included do
    has_one :ledger_entry, class_name: "Fork::PlaidItemLedgerEntry", foreign_key: :plaid_item_id, inverse_of: false

    # A revoked Item stops syncing (R3.6). The scope is redefined here because
    # upstream defines it as `active` alone.
    scope :syncable, -> { active.where(revoked_at: nil) }
    scope :revoked, -> { where.not(revoked_at: nil) }

    after_create :record_in_item_ledger
    after_update :sync_item_ledger_institution, if: -> { saved_change_to_institution_id? || saved_change_to_name? }
    after_destroy :mark_item_ledger_removed
  end

  def revoked?
    revoked_at.present?
  end

  # Fork::ConnectionHealth's status for this Item.
  def connection_status
    Fork::ConnectionHealth.status_for(self)
  end

  def revoked_plaid_accounts
    plaid_accounts.where.not(revoked_at: nil)
  end

  private
    def record_in_item_ledger
      Fork::PlaidItemBudget.record!(self)
    end

    def sync_item_ledger_institution
      Fork::PlaidItemLedgerEntry.where(plaid_id: plaid_id).update_all(
        institution_id: institution_id,
        institution_name: name
      )
    end

    def mark_item_ledger_removed
      Fork::PlaidItemBudget.mark_removed!(self)
    end
end
