# frozen_string_literal: true

# One row per card or loan statement (design §4.5, §5.2). The name avoids
# upstream's account_statements table, which holds uploaded statement files.
class ForkCreateLiabilityStatements < ActiveRecord::Migration[8.1]
  def change
    create_table :liability_statements, id: :uuid do |t|
      t.references :account, null: false, type: :uuid, foreign_key: { on_delete: :cascade }
      t.references :recurring_occurrence, type: :uuid, foreign_key: { on_delete: :nullify }
      t.string :source, null: false, default: "plaid"
      t.date :issued_on
      t.date :due_on
      t.decimal :statement_balance, precision: 19, scale: 4
      t.decimal :minimum_due, precision: 19, scale: 4
      t.string :currency, null: false
      t.boolean :is_overdue, null: false, default: false
      t.decimal :last_payment_amount, precision: 19, scale: 4
      t.date :last_payment_on
      t.jsonb :aprs, null: false, default: []
      t.text :fields_missing, array: true, null: false, default: []

      t.timestamps

      t.index %i[account_id issued_on], unique: true, where: "issued_on IS NOT NULL",
              name: "idx_liability_statements_account_issued_on"
      t.index %i[account_id due_on], unique: true, where: "issued_on IS NULL",
              name: "idx_liability_statements_account_due_on"
      t.check_constraint "source IN ('plaid', 'manual')", name: "chk_liability_statements_source"
      t.check_constraint "issued_on IS NOT NULL OR due_on IS NOT NULL", name: "chk_liability_statements_dated"
    end
  end
end
