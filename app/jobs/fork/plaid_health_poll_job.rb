class Fork::PlaidHealthPollJob < ApplicationJob
  queue_as :scheduled

  def perform
    Fork::PlaidHealthPoll.run
  end
end
