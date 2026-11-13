# One row per Plaid Item ever created (design §4.2). Deleting an Item sets
# removed_at and keeps the row, because the slot stays used on the Plaid team.
class Fork::PlaidItemLedgerEntry < ApplicationRecord
  self.table_name = "plaid_item_ledger_entries"

  ENVIRONMENTS = %w[sandbox production].freeze

  belongs_to :family, optional: true

  validates :plaid_id, presence: true, uniqueness: true
  validates :environment, inclusion: { in: ENVIRONMENTS }

  scope :production, -> { where(environment: "production") }
  scope :removed, -> { where.not(removed_at: nil) }
end
