# Prepended to RecurringOccurrence in fork.rb (design §4.5, §6.8).
#
# Upstream's derived_state turns an open occurrence overdue once its due date
# plus grace has passed, whatever was paid. A card bill whose payments reach
# the statement minimum is not overdue: it stays due while the balance carries.
module Fork::RecurringOccurrenceExtension
  def derived_state
    state = super
    return state unless state == :overdue && fork_card_bill?

    minimum = fork_statement&.minimum_due
    return :due if minimum.present? && minimum.positive? && confirmed_allocated >= minimum - RecurringOccurrence::CLOSE_EPSILON

    state
  end

  def fork_card_bill?
    Fork::Liabilities::BillLinker.card_series?(recurring_transaction)
  end

  def fork_statement
    return @fork_statement if defined?(@fork_statement)

    @fork_statement = Fork::LiabilityStatement.find_by(recurring_occurrence_id: id)
  end

  # Closed as paid by the next statement although only the minimum arrived.
  def minimum_paid_balance_carried?
    fork_card_bill? && paid? && closed_source == "auto" &&
      confirmed_allocated < resolved_expected_amount - RecurringOccurrence::CLOSE_EPSILON
  end
end
