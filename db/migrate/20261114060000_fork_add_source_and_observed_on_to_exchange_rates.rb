# frozen_string_literal: true

# Where each exchange rate came from and the day it was observed (design §4.6).
# Existing rows count as observed on their own date until `fork:fx_backfill`
# re-imports each pair; rows the importer carried forward over weekends look
# observed until then.
class ForkAddSourceAndObservedOnToExchangeRates < ActiveRecord::Migration[8.1]
  def up
    add_column :exchange_rates, :source, :string
    add_column :exchange_rates, :observed_on, :date

    execute "UPDATE exchange_rates SET observed_on = date WHERE observed_on IS NULL"
  end

  def down
    remove_column :exchange_rates, :observed_on
    remove_column :exchange_rates, :source
  end
end
