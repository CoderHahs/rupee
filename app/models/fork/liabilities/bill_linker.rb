# Turns a liability statement into one occurrence on the card's recurring
# series (design §4.5, decision D7). One series per card, from the funding
# account to the card, in the card's currency.
#
# Returns a symbol saying what happened, so callers and tests can tell a
# linked bill from a statement that was only recorded:
#
#   :linked             the occurrence exists and the statement points at it
#   :zero_balance       nothing is owed, so no occurrence (and the series is untouched)
#   :disabled           the family turned recurring transactions off
#   :no_due_date        the statement carries no due date
#   :record_only        the card's series is paused, ended or inactive
#   :needs_currency     the card's series is in another currency
#   :needs_funding_account  no funding account is known; the member must choose
class Fork::Liabilities::BillLinker
  SCOPE_PREFIX = "fork-card-"
  ZERO_THRESHOLD = BigDecimal("0.01")

  attr_reader :statement, :funding_account

  def self.scope_for(account)
    "#{SCOPE_PREFIX}#{account.id}"
  end

  def self.card_series?(series)
    series.dedup_scope.to_s.start_with?(SCOPE_PREFIX)
  end

  def initialize(statement, funding_account: nil)
    @statement = statement
    @funding_account = funding_account
  end

  def link!
    return :disabled if family.recurring_transactions_disabled?
    return :no_due_date if statement.due_on.nil?

    series = find_series
    return :record_only if series && !series.active?
    return :needs_currency if series && series.currency != account.currency

    if zero_balance?
      retire_own_occurrence!
      close_previous!(series, except: nil) if series
      return :zero_balance
    end

    funding = resolve_funding(series)
    return :needs_funding_account if funding.nil?

    series ||= create_series!(funding)
    update_series!(series, funding)

    release_moved_occurrence!(series)
    occurrence = upsert_occurrence!(series)
    statement.update!(recurring_occurrence: occurrence)
    close_previous!(series, except: occurrence)

    :linked
  end

  # What the member still has to do for this statement, or nil.
  def pending_action
    return nil if statement.recurring_occurrence_id.present? || statement.due_on.nil?
    return nil if family.recurring_transactions_disabled? || zero_balance?

    series = find_series
    return nil if series && !series.active?
    return :needs_currency if series && series.currency != account.currency

    :needs_funding_account if resolve_funding(series).nil?
  end

  private
    def account
      statement.account
    end

    def family
      account.family
    end

    # Cards bill the statement balance, falling back to the minimum when the
    # institution did not provide one. Loans bill the minimum.
    def bill_amount
      if account.credit_card? && statement.statement_balance.present?
        statement.statement_balance
      else
        statement.minimum_due
      end
    end

    def zero_balance?
      amount = bill_amount
      amount.nil? || amount <= ZERO_THRESHOLD
    end

    def find_series
      family.recurring_transactions
            .where(destination_account_id: account.id)
            .where.not(status: "suggested")
            .to_a
            .min_by { |series| [ series.active? ? 0 : 1, self.class.card_series?(series) ? 0 : 1, series.created_at ] }
    end

    # A member's choice always wins over inference.
    def resolve_funding(series)
      return funding_account if funding_account && funding_account.id != account.id && funding_account.family_id == family.id
      return series.account if series&.account

      latest_transfer_source
    end

    def latest_transfer_source
      transfer = Transfer.joins(inflow_transaction: :entry)
                         .where(entries: { account_id: account.id })
                         .order("entries.date DESC")
                         .first
      source = transfer&.outflow_transaction&.entry&.account
      source if source && source.id != account.id && source.family_id == family.id
    end

    def create_series!(funding)
      due = statement.due_on

      family.recurring_transactions.create!(
        name: I18n.t("fork.liabilities.bill_name", name: account.name),
        manual: true,
        bill_type: "transfer",
        account: funding,
        destination_account: account,
        currency: account.currency,
        amount: bill_amount,
        amount_strategy: "last",
        amount_tolerance_pct: 0,
        dedup_scope: self.class.scope_for(account),
        expected_day_of_month: due.day,
        anchor_date: due,
        last_occurrence_date: due,
        next_expected_date: due,
        status: "active"
      )
    end

    def update_series!(series, funding)
      series.account = funding if series.account_id != funding.id
      series.amount = bill_amount
      series.amount_tolerance_pct = 0
      series.save! if series.changed?
    end

    def upsert_occurrence!(series)
      due = statement.due_on

      occurrence = series.recurring_occurrences.find_by(original_due_on: due) ||
        begin
          series.recurring_occurrences.create!(
            family: family, original_due_on: due, due_on: due, currency: account.currency
          )
        rescue ActiveRecord::RecordNotUnique
          series.recurring_occurrences.find_by!(original_due_on: due)
        end

      occurrence.override_amount!(bill_amount) if occurrence.scheduled?
      occurrence
    end

    # Step 5: the due date moved, so the occurrence at the old date goes away.
    # One that already has payments is settled instead of discarded.
    def release_moved_occurrence!(series)
      old = statement.recurring_occurrence
      return if old.nil? || !old.scheduled?
      return if old.recurring_transaction_id != series.id || old.original_due_on == statement.due_on

      if old.allocations.exists?
        settle!(old, statement)
      else
        old.skip!(source: "auto")
      end
    end

    def retire_own_occurrence!
      old = statement.recurring_occurrence
      return if old.nil? || !old.scheduled?

      old.allocations.exists? ? settle!(old, statement) : old.skip!(source: "auto")
    end

    # Step 7: a newer statement closes the earlier open occurrences. Payments
    # that reached the minimum close it as paid (the card page labels that
    # "minimum paid, balance carried"); anything less is missed.
    def close_previous!(_series, except:)
      return if statement.due_on.nil?

      Fork::LiabilityStatement
        .where(account_id: account.id)
        .where.not(id: statement.id)
        .where.not(recurring_occurrence_id: nil)
        .where(due_on: ...statement.due_on)
        .includes(:recurring_occurrence)
        .each do |earlier|
          occurrence = earlier.recurring_occurrence
          next if occurrence.nil? || !occurrence.scheduled? || occurrence.id == except&.id

          settle!(occurrence, earlier)
        end
    end

    def settle!(occurrence, source_statement)
      minimum = source_statement.minimum_due || occurrence.resolved_expected_amount
      paid = occurrence.allocations.confirmed.sum(:allocated_amount)

      if paid >= minimum - RecurringOccurrence::CLOSE_EPSILON
        occurrence.close!("paid", source: "auto")
      else
        occurrence.close!("missed", source: "auto")
      end
    end
end
