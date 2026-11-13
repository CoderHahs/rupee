require "test_helper"

class PlaidAccount::Liabilities::CreditProcessorTest < ActiveSupport::TestCase
  setup do
    @plaid_account = plaid_accounts(:one)
    @plaid_account.update!(
      plaid_type: "credit",
      plaid_subtype: "credit_card"
    )

    @plaid_account.current_account.update!(
      accountable: CreditCard.new,
    )
  end

  test "updates credit card minimum payment and APR from Plaid data" do
    @plaid_account.update!(raw_liabilities_payload: {
      credit: {
        minimum_payment_amount: 100,
        aprs: [ { apr_type: "purchase_apr", apr_percentage: 15.0 } ]
      }
    })

    processor = PlaidAccount::Liabilities::CreditProcessor.new(@plaid_account)
    processor.process

    assert_equal 100, @plaid_account.current_account.credit_card.minimum_payment
    assert_equal 15.0, @plaid_account.current_account.credit_card.apr
  end

  test "does nothing when liability data absent" do
    @plaid_account.update!(raw_liabilities_payload: {})
    processor = PlaidAccount::Liabilities::CreditProcessor.new(@plaid_account)
    processor.process

    assert_nil @plaid_account.current_account.credit_card.minimum_payment
    assert_nil @plaid_account.current_account.credit_card.apr
  end

  test "the headline APR is the purchase APR, not the first entry" do
    @plaid_account.update!(raw_liabilities_payload: {
      credit: {
        minimum_payment_amount: 100,
        aprs: [
          { apr_type: "balance_transfer_apr", apr_percentage: 0.0 },
          { apr_type: "purchase_apr", apr_percentage: 21.5 }
        ]
      }
    })

    PlaidAccount::Liabilities::CreditProcessor.new(@plaid_account).process

    assert_equal 21.5, @plaid_account.current_account.credit_card.apr
  end

  test "the APR is cleared when no purchase APR exists" do
    @plaid_account.current_account.credit_card.update!(apr: 18.0)
    @plaid_account.update!(raw_liabilities_payload: {
      credit: { minimum_payment_amount: 100, aprs: [ { apr_type: "cash_apr", apr_percentage: 25.0 } ] }
    })

    PlaidAccount::Liabilities::CreditProcessor.new(@plaid_account).process

    assert_nil @plaid_account.current_account.credit_card.apr
  end

  test "a locked APR is not overwritten" do
    card = @plaid_account.current_account.credit_card
    card.update!(apr: 9.9)
    card.lock_attr!(:apr)
    @plaid_account.update!(raw_liabilities_payload: {
      credit: { aprs: [ { apr_type: "purchase_apr", apr_percentage: 30.0 } ] }
    })

    PlaidAccount::Liabilities::CreditProcessor.new(@plaid_account).process

    assert_equal 9.9, card.reload.apr
  end
end
