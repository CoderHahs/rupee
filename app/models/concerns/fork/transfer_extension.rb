# Fork additions to Transfer, applied in config/initializers/fork.rb so
# transfer.rb stays unedited (design §4.1).
module Fork::TransferExtension
  extend ActiveSupport::Concern

  included do
    has_one :fx_detail, class_name: "Fork::TransferFxDetail", dependent: :destroy
    after_create :record_fx_details
  end

  private
    # A cross-currency transfer records both amounts, the implied rate and the
    # spread against the reference rate (R4.9). Failing to record never fails
    # the transfer.
    def record_fx_details
      Fork::TransferFxDetail.build_for(self)&.save!
    rescue StandardError => e
      Rails.logger.error("[Fork::TransferExtension] could not record FX details for transfer #{id}: #{e.message}")
    end
end
