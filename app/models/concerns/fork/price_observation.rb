# Sets Security::Price#observed_on on every ordinary save (design §4.7).
# The importer upserts, which skips callbacks, and sets the column itself.
module Fork::PriceObservation
  extend ActiveSupport::Concern

  included do
    before_save :fork_set_observed_on
  end

  private
    # Blank, or the price changed: the price was observed on the row's date.
    # `||=` alone would leave a corrected price with an old observation date.
    def fork_set_observed_on
      self.observed_on = date if observed_on.blank? || will_save_change_to_price?
    end
end
