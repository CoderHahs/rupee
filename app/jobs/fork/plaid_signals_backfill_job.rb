# Backfills the signals for one Item. An Item with a sync in progress is
# requeued for later (design §4.4).
class Fork::PlaidSignalsBackfillJob < ApplicationJob
  queue_as :low_priority
  RETRY_DELAY = 10.minutes

  def perform(plaid_item)
    backfill = Fork::PlaidSignalsBackfill.new(items: PlaidItem.where(id: plaid_item.id))
    backfill.run
    if backfill.report.items_deferred.any?
      self.class.set(wait: RETRY_DELAY).perform_later(plaid_item)
    else
      Rails.logger.info(backfill.report.to_s)
    end
  end
end
