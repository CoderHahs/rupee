# One card or loan statement (design §4.5), recorded from Plaid Liabilities or
# entered by hand. Fork::Liabilities::Recorder writes it and
# Fork::Liabilities::BillLinker turns it into a bill occurrence.
class Fork::LiabilityStatement < ApplicationRecord
  self.table_name = "liability_statements"

  include Monetizable

  # Fields Plaid may leave out. The UI shows "not provided by the institution"
  # for each one that is listed in fields_missing, never zero (R9.5).
  TRACKED_FIELDS = %w[issued_on due_on statement_balance minimum_due last_payment_amount last_payment_on aprs].freeze

  belongs_to :account
  belongs_to :recurring_occurrence, optional: true

  monetize :statement_balance, :minimum_due, :last_payment_amount

  enum :source, { plaid: "plaid", manual: "manual" }, prefix: :from

  validates :currency, presence: true
  validates :statement_balance, :minimum_due, :last_payment_amount, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validate :dated

  scope :newest_first, -> { order(Arel.sql("COALESCE(liability_statements.issued_on, liability_statements.due_on) DESC")) }

  def missing?(field)
    fields_missing.include?(field.to_s)
  end

  # The headline APR: the purchase APR entry, never the first one (R9.2).
  def purchase_apr
    entry = Array(aprs).find { |apr| apr["apr_type"] == "purchase_apr" }
    entry && entry["apr_percentage"]
  end

  private
    def dated
      errors.add(:due_on, :blank) if issued_on.blank? && due_on.blank?
    end
end
