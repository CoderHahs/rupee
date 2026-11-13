# Hourly: allocates card and loan payments to the open card bills (design §4.5).
class Fork::LiabilityPaymentMatchJob < ApplicationJob
  queue_as :scheduled
  sidekiq_options lock: :until_executed, on_conflict: :log

  def perform
    Fork::Liabilities::PaymentMatcher.match_all
  end
end
