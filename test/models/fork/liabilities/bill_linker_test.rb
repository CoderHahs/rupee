require "test_helper"

class Fork::Liabilities::BillLinkerTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:dylan_family)
    @card = accounts(:credit_card)
    @funding = accounts(:depository)
    travel_to Date.new(2026, 10, 1)
  end

  def record(funding: @funding, **attrs)
    Fork::Liabilities::Recorder.record_manual(
      @card,
      { issued_on: Date.new(2026, 9, 20), due_on: Date.new(2026, 10, 15), statement_balance: 1200, minimum_due: 35 }.merge(attrs),
      funding_account: funding
    )
  end

  def series
    @family.recurring_transactions.find_by!(dedup_scope: "fork-card-#{@card.id}")
  end

  def pay(amount, date)
    create_transaction(account: @card, amount: -amount, date: date, kind: "cc_payment", name: "Payment")
  end

  def allocate(occurrence, amount, date)
    RecurringTransaction::Allocator.new(occurrence).allocate!(amount: amount, paid_on: date)
  end

  test "creates one transfer series per card and one occurrence per statement" do
    statement = record

    assert_equal 1, @family.recurring_transactions.where(destination_account: @card).count
    assert_equal @funding, series.account
    assert_equal "transfer", series.bill_type
    assert_equal "USD", series.currency
    assert_equal 0, series.amount_tolerance_pct

    occurrence = statement.reload.recurring_occurrence
    assert_equal Date.new(2026, 10, 15), occurrence.due_on
    assert_equal 1200, occurrence.expected_amount
    assert_equal 1200, series.amount
  end

  test "recording the same statement twice changes nothing" do
    record
    assert_no_difference -> { RecurringOccurrence.count } do
      assert_no_difference -> { Fork::LiabilityStatement.count } do
        record
      end
    end
  end

  test "section 6.8 states" do
    series_record = record.recurring_occurrence.recurring_transaction
    series_record.update!(notify_days_before: 5)
    occurrence = Fork::LiabilityStatement.last.recurring_occurrence

    travel_to(Date.new(2026, 10, 9)) { assert_equal :upcoming, occurrence.reload.derived_state }
    travel_to(Date.new(2026, 10, 10)) { assert_equal :due, occurrence.reload.derived_state }
    travel_to(Date.new(2026, 10, 18)) { assert_equal :due, occurrence.reload.derived_state }
    travel_to(Date.new(2026, 10, 19)) { assert_equal :overdue, occurrence.reload.derived_state }

    allocate(occurrence, 20, Date.new(2026, 10, 14))
    travel_to(Date.new(2026, 10, 19)) { assert_equal :overdue, occurrence.reload.derived_state }

    allocate(occurrence, 15, Date.new(2026, 10, 14))
    occurrence.reload
    assert occurrence.partially_paid?
    assert_equal 1165, occurrence.remaining_amount
    travel_to(Date.new(2026, 10, 19)) { assert_equal :due, occurrence.reload.derived_state }
  end

  test "payments totalling the balance close the occurrence as paid" do
    occurrence = record.recurring_occurrence
    allocate(occurrence, 1200, Date.new(2026, 10, 14))

    assert_equal "paid", occurrence.reload.status
  end

  test "the next statement closes a minimum-paid occurrence as paid and labels it" do
    first = record.recurring_occurrence
    allocate(first, 35, Date.new(2026, 10, 14))

    record(issued_on: Date.new(2026, 10, 20), due_on: Date.new(2026, 11, 15), statement_balance: 1300, minimum_due: 40)

    first.reload
    assert_equal "paid", first.status
    assert_equal "auto", first.closed_source
    assert first.minimum_paid_balance_carried?
    assert_equal 2, series.recurring_occurrences.where(original_due_on: [ Date.new(2026, 10, 15), Date.new(2026, 11, 15) ]).count
  end

  test "the next statement marks an unpaid occurrence missed" do
    first = record.recurring_occurrence
    allocate(first, 20, Date.new(2026, 10, 14))

    record(issued_on: Date.new(2026, 10, 20), due_on: Date.new(2026, 11, 15), statement_balance: 1300, minimum_due: 40)

    assert_equal "missed", first.reload.status
  end

  test "a moved due date skips the occurrence at the old date" do
    old = record.recurring_occurrence

    statement = record(due_on: Date.new(2026, 10, 18))

    assert_equal "skipped", old.reload.status
    assert_equal Date.new(2026, 10, 18), statement.recurring_occurrence.due_on
    assert_equal 1, Fork::LiabilityStatement.where(account: @card).count
  end

  test "a zero balance creates no occurrence and leaves the series amount alone" do
    record
    amount_before = series.amount

    statement = record(issued_on: Date.new(2026, 10, 20), due_on: Date.new(2026, 11, 15), statement_balance: 0, minimum_due: 0)

    assert_nil statement.recurring_occurrence
    assert_equal amount_before, series.reload.amount
  end

  test "a missing funding account records the statement and asks the member" do
    Transfer.delete_all
    statement = record(funding: nil)

    assert_nil statement.recurring_occurrence
    assert_equal :needs_funding_account, Fork::Liabilities::BillLinker.new(statement).pending_action
    assert_equal 0, @family.recurring_transactions.where(destination_account: @card).count
  end

  test "the funding account is inferred from the card's latest transfer" do
    outflow = create_transaction(account: @funding, amount: 100, date: Date.new(2026, 9, 25), kind: "cc_payment")
    inflow = create_transaction(account: @card, amount: -100, date: Date.new(2026, 9, 25), kind: "funds_movement")
    Transfer.create!(inflow_transaction: inflow.entryable, outflow_transaction: outflow.entryable, status: "confirmed")

    statement = record(funding: nil)

    assert statement.recurring_occurrence
    assert_equal @funding, series.account
  end

  test "an adopted series in another currency only records the statement" do
    @family.recurring_transactions.create!(
      name: "Card", manual: true, account: @funding, destination_account: @card, currency: "EUR",
      amount: 50, expected_day_of_month: 15, anchor_date: Date.new(2026, 10, 15),
      last_occurrence_date: Date.new(2026, 10, 15), next_expected_date: Date.new(2026, 10, 15),
      status: "active", dedup_scope: "x"
    )

    statement = record

    assert_nil statement.recurring_occurrence
    assert_equal :needs_currency, Fork::Liabilities::BillLinker.new(statement).pending_action
  end

  test "a paused series and a disabled family get the statement and no occurrence" do
    record
    series.update!(status: "paused")
    statement = record(issued_on: Date.new(2026, 10, 20), due_on: Date.new(2026, 11, 15))
    assert_nil statement.recurring_occurrence

    series.update!(status: "active")
    @card.family.update!(recurring_transactions_disabled: true)
    statement = record(issued_on: Date.new(2026, 11, 20), due_on: Date.new(2026, 12, 15))
    assert_nil statement.recurring_occurrence
  end

  test "a payment is counted once by the payment matcher" do
    occurrence = record.recurring_occurrence
    payment = pay(35, Date.new(2026, 10, 14))

    2.times { Fork::Liabilities::PaymentMatcher.new(@family).match! }

    assert_equal 1, occurrence.allocations.count
    assert_equal 35, occurrence.reload.confirmed_allocated
    assert_equal [ payment.id ], occurrence.allocations.pluck(:entry_id)
  end

  test "a payment whose funding-side leg is already allocated is skipped" do
    occurrence = record.recurring_occurrence
    outflow = create_transaction(account: @funding, amount: 35, date: Date.new(2026, 10, 14), kind: "cc_payment")
    inflow = create_transaction(account: @card, amount: -35, date: Date.new(2026, 10, 14), kind: "funds_movement")
    Transfer.create!(inflow_transaction: inflow.entryable, outflow_transaction: outflow.entryable, status: "confirmed")
    RecurringTransaction::Allocator.new(occurrence).allocate!(entry: outflow)

    Fork::Liabilities::PaymentMatcher.new(@family).match!

    assert_equal 1, occurrence.allocations.count
  end

  test "refunds and payments outside the window are not matched" do
    occurrence = record.recurring_occurrence
    create_transaction(account: @card, amount: -50, date: Date.new(2026, 10, 12), kind: "standard", name: "Refund")
    pay(35, Date.new(2026, 9, 10))

    Fork::Liabilities::PaymentMatcher.new(@family).match!

    assert_equal 0, occurrence.allocations.count
  end

  test "a payment larger than the remainder is capped at what the bill still owes" do
    occurrence = record(statement_balance: 100).recurring_occurrence
    allocate(occurrence, 90, Date.new(2026, 10, 1))
    pay(30, Date.new(2026, 10, 14))

    Fork::Liabilities::PaymentMatcher.new(@family).match!

    assert_equal 100, occurrence.reload.confirmed_allocated
  end
end
