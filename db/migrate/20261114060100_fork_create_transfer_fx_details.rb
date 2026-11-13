# frozen_string_literal: true

# The exchange a cross-currency transfer made, against the reference rate on
# the day (design §5.2, R4.9). The reference columns are null without a rate.
class ForkCreateTransferFxDetails < ActiveRecord::Migration[8.1]
  def change
    create_table :transfer_fx_details, id: :uuid do |t|
      t.references :transfer, null: false, type: :uuid, index: { unique: true }, foreign_key: { on_delete: :cascade }
      t.decimal :outflow_amount, precision: 19, scale: 4, null: false
      t.string :outflow_currency, null: false
      t.decimal :inflow_amount, precision: 19, scale: 4, null: false
      t.string :inflow_currency, null: false
      t.decimal :implied_rate, precision: 20, scale: 10, null: false
      t.decimal :reference_rate, precision: 20, scale: 10
      t.string :reference_source
      t.date :reference_observed_on
      t.decimal :spread_bps, precision: 9, scale: 1

      t.timestamps
    end
  end
end
