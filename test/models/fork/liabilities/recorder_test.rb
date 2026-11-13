require "test_helper"

class Fork::Liabilities::RecorderTest < ActiveSupport::TestCase
  setup do
    @plaid_account = plaid_accounts(:one)
    @plaid_account.update!(plaid_type: "credit", plaid_subtype: "credit_card")
    @account = @plaid_account.current_account
    @account.update!(accountable: CreditCard.new)
    @family = @account.family
  end

  def payload
    {
      credit: {
        last_statement_issue_date: "2026-09-20", next_payment_due_date: "2026-10-15",
        last_statement_balance: 1200.0, minimum_payment_amount: 35.0, is_overdue: false,
        last_payment_amount: 100.0, last_payment_date: "2026-09-01",
        aprs: [ { apr_type: "balance_transfer_apr", apr_percentage: 0.0 }, { apr_type: "purchase_apr", apr_percentage: 21.5 } ]
      }
    }
  end

  test "records every credit field and every apr, and is idempotent" do
    @plaid_account.update!(raw_liabilities_payload: payload)

    2.times { Fork::Liabilities::Recorder.record_plaid(@plaid_account) }

    statement = Fork::LiabilityStatement.where(account: @account).sole
    assert_equal Date.new(2026, 9, 20), statement.issued_on
    assert_equal 1200, statement.statement_balance
    assert_equal 35, statement.minimum_due
    assert_equal 100, statement.last_payment_amount
    assert_equal 2, statement.aprs.size
    assert_equal 21.5, statement.purchase_apr
    assert_empty statement.fields_missing
  end

  test "fields Plaid did not return are listed, not zeroed" do
    @plaid_account.update!(raw_liabilities_payload: { credit: { next_payment_due_date: "2026-10-15", aprs: [] } })

    Fork::Liabilities::Recorder.record_plaid(@plaid_account)

    statement = Fork::LiabilityStatement.where(account: @account).sole
    assert_nil statement.statement_balance
    assert statement.missing?(:statement_balance)
    assert statement.missing?(:aprs)
    assert_not statement.missing?(:due_on)
  end

  test "a manual statement is never overwritten by a sync" do
    Fork::Liabilities::Recorder.record_manual(@account, { issued_on: Date.new(2026, 9, 20), due_on: Date.new(2026, 10, 15), statement_balance: 999, minimum_due: 30 })
    @plaid_account.update!(raw_liabilities_payload: payload)

    Fork::Liabilities::Recorder.record_plaid(@plaid_account)

    statement = Fork::LiabilityStatement.where(account: @account).sole
    assert statement.from_manual?
    assert_equal 999, statement.statement_balance
  end

  test "mortgages key on the due date and bill the minimum" do
    @account.update!(accountable: Loan.new)
    @plaid_account.update!(plaid_type: "loan", plaid_subtype: "mortgage", raw_liabilities_payload: {
      mortgage: { next_payment_due_date: "2026-11-01", next_monthly_payment: 2100.0, past_due_amount: 0,
                  interest_rate: { percentage: 4.1, type: "fixed" } }
    })

    2.times { Fork::Liabilities::Recorder.record_plaid(@plaid_account) }

    statement = Fork::LiabilityStatement.where(account: @account).sole
    assert_nil statement.issued_on
    assert_equal 2100, statement.minimum_due
    assert statement.missing?(:issued_on)
    assert_not statement.is_overdue?
  end

  test "the prepended processor records a statement after a sync" do
    @plaid_account.update!(raw_liabilities_payload: payload)

    PlaidAccount::Processor.new(@plaid_account).send(:process_liabilities)

    assert_equal 1, Fork::LiabilityStatement.where(account: @account).count
  end
end
