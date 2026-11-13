class PlaidAccount::Liabilities::CreditProcessor
  def initialize(plaid_account)
    @plaid_account = plaid_account
  end

  def process
    return unless credit_data.present?

    # enrich_attributes honours attribute locks and can clear a value. The
    # headline APR is the purchase APR; Plaid does not order aprs, so the first
    # entry may be a balance transfer rate (R9.2).
    account.accountable.enrich_attributes(
      {
        minimum_payment: credit_data.dig("minimum_payment_amount"),
        apr: purchase_apr
      },
      source: "plaid"
    )
  end

  private
    attr_reader :plaid_account

    def purchase_apr
      aprs = Array(credit_data["aprs"])
      aprs.find { |apr| apr["apr_type"] == "purchase_apr" }&.dig("apr_percentage")
    end

    def account
      plaid_account.current_account
    end

    def credit_data
      plaid_account.raw_liabilities_payload["credit"]
    end
end
