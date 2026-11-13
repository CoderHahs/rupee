# frozen_string_literal: true

# The date a security price was actually observed, so a carried price can be
# shown with its real date (design §4.7, D21). Nullable: rows written before
# this migration are filled by Fork::PriceObservedOnBackfill.
class ForkAddObservedOnToSecurityPrices < ActiveRecord::Migration[8.1]
  def up
    add_column :security_prices, :observed_on, :date

    Security::Price.reset_column_information
    Fork::PriceObservedOnBackfill.run!
  end

  def down
    remove_column :security_prices, :observed_on
  end
end
