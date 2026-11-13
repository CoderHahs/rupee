# frozen_string_literal: true

# One row per Plaid Item ever created, so the Item budget counts slots that
# stay used after an Item is deleted (design §4.2, §5.2). family_id is
# nullified and plaid_item_id carries no foreign key, so a row outlives both
# the Item and the family.
class ForkCreatePlaidItemLedgerEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :plaid_item_ledger_entries, id: :uuid do |t|
      t.references :family, type: :uuid, foreign_key: { on_delete: :nullify }
      t.uuid :plaid_item_id
      t.string :plaid_id, null: false
      t.string :institution_id
      t.string :institution_name
      t.string :environment, null: false, default: "production"
      t.datetime :created_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
      t.datetime :removed_at

      t.index :plaid_id, unique: true
      t.index :plaid_item_id
      t.check_constraint "environment IN ('sandbox', 'production')", name: "chk_plaid_item_ledger_entries_environment"
    end
  end
end
