# frozen_string_literal: true

# Rupee's per-family settings (design §5.2). A row is created the first time
# a family's settings are read, so existing families need no backfill.
class ForkCreateHouseholdSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :household_settings, id: :uuid do |t|
      t.references :family, null: false, type: :uuid, index: { unique: true }, foreign_key: { on_delete: :cascade }
      t.boolean :ai_enabled, null: false, default: false
      t.datetime :ai_consented_at
      t.references :ai_consented_by, type: :uuid, foreign_key: { to_table: :users, on_delete: :nullify }
      t.boolean :ai_for_guests, null: false, default: false
      t.datetime :timezone_confirmed_at
      t.boolean :card_benefits_enabled, null: false, default: false
      t.integer :credit_lead_days, null: false, default: 7
      t.decimal :credit_match_threshold, precision: 3, scale: 2, null: false, default: 0.80
      t.decimal :missed_value_threshold, precision: 3, scale: 2, null: false, default: 1.00
      t.datetime :credit_match_watermark_at

      t.timestamps

      t.check_constraint "credit_lead_days BETWEEN 1 AND 60", name: "chk_household_settings_credit_lead_days"
      t.check_constraint "credit_match_threshold BETWEEN 0 AND 1", name: "chk_household_settings_credit_match_threshold"
      t.check_constraint "missed_value_threshold BETWEEN 0 AND 1", name: "chk_household_settings_missed_value_threshold"
    end
  end
end
