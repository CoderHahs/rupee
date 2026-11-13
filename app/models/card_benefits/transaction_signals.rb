# Read-only view over the Plaid signals stored on an entry's transaction
# (`extra["plaid"]`, design §4.4). Every reader returns nil for a missing value
# and nothing here raises, so "not provided" and "not synced yet" look the same.
module CardBenefits
  class TransactionSignals
    def self.for(entry)
      new(entry)
    end

    def initialize(entry)
      @entry = entry
    end

    def mcc = value("merchant_category_code")
    def pfc_primary = value("pfc_primary")
    def pfc_detailed = value("pfc_detailed")
    def pfc_confidence = value("pfc_confidence_level")
    def pfc_version = value("pfc_version")
    def transaction_code = value("transaction_code")
    def payment_channel = value("payment_channel")

    # @return [Date, nil] the day the purchase was authorized, when Plaid sent it
    def authorized_date
      raw = value("authorized_date")
      return nil if raw.nil?

      Date.iso8601(raw.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    # Issuers count a purchase on the day it was made, not the day it posted.
    # @return [Date, nil]
    def effective_date
      authorized_date || entry_date
    end

    private
      def plaid
        extra = @entry&.entryable.respond_to?(:extra) ? @entry.entryable.extra : nil
        plaid = extra.is_a?(Hash) ? extra["plaid"] : nil
        plaid.is_a?(Hash) ? plaid : {}
      rescue StandardError
        {}
      end

      def value(key)
        plaid[key].presence
      end

      def entry_date
        date = @entry&.date
        date.is_a?(Date) ? date : nil
      rescue StandardError
        nil
      end
  end
end
