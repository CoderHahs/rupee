# Allocates card and loan payments to the open bill occurrences that
# BillLinker made (design §4.5). Runs hourly as fork:liability_payment_match.
#
# Candidates are inflows to the card or loan account: the inflow leg of a
# Transfer whose outflow is a card or loan payment, inflows of kind cc_payment
# or loan_payment, and inflows Plaid categorised as a card payment (which
# covers payments from accounts the family has not linked). Refunds and
# statement credits are inflows too and are excluded.
class Fork::Liabilities::PaymentMatcher
  PAYMENT_KINDS = %w[cc_payment loan_payment].freeze
  PFC_PAYMENTS = %w[LOAN_PAYMENTS_CREDIT_CARD_PAYMENT].freeze

  def initialize(family)
    @family = family
  end

  def self.match_all
    Family.find_each.sum do |family|
      next 0 if family.recurring_transactions_disabled?

      new(family).match!
    end
  end

  # Returns the number of allocations written. Idempotent.
  def match!
    written = 0

    open_bills.group_by { |occurrence, _| occurrence.fork_statement.account_id }.each do |account_id, pairs|
      account = Account.find(account_id)
      pairs = pairs.sort_by { |occurrence, _| occurrence.due_on }

      payments_for(account).each do |entry|
        next if already_counted?(entry, pairs.first.first.recurring_transaction)

        pairs.each do |occurrence, statement|
          next unless in_window?(entry, statement)
          next unless occurrence.remaining_amount.positive?

          allocation = RecurringTransaction::Allocator.new(occurrence).allocate!(
            entry: entry, source: "auto_matched", cap_at_remaining: false
          )
          written += 1 if allocation
          occurrence.reload

          break unless entry_capacity_left?(entry)
        end
      rescue RecurringTransaction::Allocator::OverAllocationError, RecurringTransaction::Allocator::MissingRateError
        next
      end
    end

    written
  end

  private
    attr_reader :family

    def open_bills
      RecurringOccurrence
        .where(family_id: family.id, status: "scheduled")
        .joins(:recurring_transaction)
        .where("recurring_transactions.dedup_scope LIKE ?", "#{Fork::Liabilities::BillLinker::SCOPE_PREFIX}%")
        .includes(:recurring_transaction)
        .filter_map do |occurrence|
          statement = occurrence.fork_statement
          [ occurrence, statement ] if statement
        end
    end

    def payments_for(account)
      account.entries
             .where(entryable_type: "Transaction", excluded: false)
             .where("entries.amount < 0")
             .includes(:entryable)
             .order(:date)
             .select { |entry| payment?(entry) && !pending?(entry) }
    end

    def payment?(entry)
      transaction = entry.entryable
      return true if PAYMENT_KINDS.include?(transaction.kind)
      return true if PFC_PAYMENTS.include?(pfc_detailed(entry))

      transfer = Transfer.find_by(inflow_transaction_id: transaction.id)
      transfer.present? && PAYMENT_KINDS.include?(transfer.outflow_transaction&.kind)
    end

    # Plaid's detailed personal finance category, from the Task 4 signals
    # (`extra["plaid"]["pfc_detailed"]`), or the raw category when only that is stored.
    def pfc_detailed(entry)
      CardBenefits::TransactionSignals.for(entry).pfc_detailed ||
        entry.entryable.extra.to_h.dig("plaid", "personal_finance_category", "detailed")
    end

    def pending?(entry)
      entry.entryable.respond_to?(:pending?) && entry.entryable.pending?
    end

    # A payment counts once: skip it when the entry, or the funding-side leg of
    # its transfer, is already allocated to this series.
    def already_counted?(entry, series)
      entry_ids = [ entry.id ]
      transfer = Transfer.find_by(inflow_transaction_id: entry.entryable_id)
      partner = transfer&.outflow_transaction&.entry
      entry_ids << partner.id if partner

      RecurringAllocation
        .joins(:recurring_occurrence)
        .where(recurring_occurrences: { recurring_transaction_id: series.id })
        .where(entry_id: entry_ids)
        .exists?
    end

    def entry_capacity_left?(entry)
      allocated = RecurringAllocation.where(entry: entry).sum("COALESCE(source_amount, allocated_amount)")
      entry.amount.abs > allocated
    end

    # After the issue date and before the next statement's. Loans have no issue
    # date, so the previous due date opens the window.
    def in_window?(entry, statement)
      siblings = Fork::LiabilityStatement.where(account_id: statement.account_id).where.not(id: statement.id)

      if statement.issued_on
        start = statement.issued_on
        finish = siblings.where(issued_on: (statement.issued_on + 1)..).minimum(:issued_on)
      else
        start = siblings.where(due_on: ...statement.due_on).maximum(:due_on) || (statement.due_on - 31)
        finish = siblings.where(issued_on: nil, due_on: (statement.due_on + 1)..).minimum(:due_on)
      end

      entry.date > start && (finish.nil? || entry.date < finish)
    end
end
