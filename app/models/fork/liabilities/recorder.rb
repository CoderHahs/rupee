# Records one liability_statements row per statement (design §4.5), then asks
# BillLinker to turn it into a bill occurrence. Idempotent: a re-run updates
# the same row, and a row whose source is manual is never overwritten.
class Fork::Liabilities::Recorder
  class << self
    # From a synced Plaid account's raw liabilities payload.
    def record_plaid(plaid_account)
      account = plaid_account.current_account
      return nil if account.nil?

      attrs = extract(plaid_account)
      return nil if attrs.nil?

      record(account, attrs.merge(currency: plaid_account.currency.presence || account.currency), source: "plaid")
    end

    # From the manual entry form (R9.6). Always wins over a Plaid row with the
    # same identity, and keeps its source from then on.
    def record_manual(account, attrs, funding_account: nil, statement: nil)
      attrs = attrs.to_h.symbolize_keys.slice(
        :issued_on, :due_on, :statement_balance, :minimum_due, :last_payment_amount, :last_payment_on, :is_overdue
      )
      attrs[:currency] = account.currency
      record(account, attrs, source: "manual", funding_account: funding_account, manual_edit: true, existing: statement)
    end

    # Plaid's credit, mortgage and student loan payloads, as one shape.
    def extract(plaid_account)
      payload = plaid_account.raw_liabilities_payload.to_h.with_indifferent_access

      if payload[:credit].present?
        credit = payload[:credit]
        {
          issued_on: parse_date(credit[:last_statement_issue_date]),
          due_on: parse_date(credit[:next_payment_due_date]),
          statement_balance: credit[:last_statement_balance],
          minimum_due: credit[:minimum_payment_amount],
          is_overdue: credit[:is_overdue] == true,
          last_payment_amount: credit[:last_payment_amount],
          last_payment_on: parse_date(credit[:last_payment_date]),
          aprs: Array(credit[:aprs]).map { |apr| apr.to_h.stringify_keys }
        }
      elsif payload[:mortgage].present?
        mortgage = payload[:mortgage]
        rate = mortgage[:interest_rate].to_h
        {
          issued_on: nil,
          due_on: parse_date(mortgage[:next_payment_due_date]),
          statement_balance: nil,
          minimum_due: mortgage[:next_monthly_payment],
          is_overdue: mortgage[:past_due_amount].to_d.positive?,
          last_payment_amount: mortgage[:last_payment_amount],
          last_payment_on: parse_date(mortgage[:last_payment_date]),
          aprs: rate[:percentage].nil? ? [] : [ { "apr_type" => "interest_rate", "apr_percentage" => rate[:percentage], "rate_type" => rate[:type] } ]
        }
      elsif payload[:student].present?
        student = payload[:student]
        {
          issued_on: parse_date(student[:last_statement_issue_date]),
          due_on: parse_date(student[:next_payment_due_date]),
          statement_balance: student[:last_statement_balance],
          minimum_due: student[:minimum_payment_amount],
          is_overdue: student[:is_overdue] == true,
          last_payment_amount: student[:last_payment_amount],
          last_payment_on: parse_date(student[:last_payment_date]),
          aprs: student[:interest_rate_percentage].nil? ? [] : [ { "apr_type" => "interest_rate", "apr_percentage" => student[:interest_rate_percentage] } ]
        }
      end
    end

    private
      def record(account, attrs, source:, funding_account: nil, manual_edit: false, existing: nil)
        attrs = attrs.dup
        attrs[:aprs] ||= [] if source == "plaid"
        attrs[:fields_missing] = missing_fields(attrs) if source == "plaid"
        return nil if existing.nil? && attrs[:issued_on].nil? && attrs[:due_on].nil?

        statement = existing || find_existing(account, attrs)

        if statement&.from_manual? && !manual_edit
          return statement
        end

        statement ||= Fork::LiabilityStatement.new(account: account)
        statement.assign_attributes(attrs.merge(source: source))
        statement.fields_missing = [] if source == "manual"
        statement.save!

        Fork::Liabilities::BillLinker.new(statement, funding_account: funding_account).link!
        statement
      rescue ActiveRecord::RecordNotUnique
        # A concurrent sync wrote the same statement; the next run converges.
        nil
      end

      def find_existing(account, attrs)
        scope = Fork::LiabilityStatement.where(account: account)

        if attrs[:issued_on].present?
          scope.find_by(issued_on: attrs[:issued_on])
        else
          scope.find_by(issued_on: nil, due_on: attrs[:due_on])
        end
      end

      def missing_fields(attrs)
        Fork::LiabilityStatement::TRACKED_FIELDS.select do |field|
          value = attrs[field.to_sym]
          field == "aprs" ? value.blank? : value.nil?
        end
      end

      def parse_date(value)
        return value if value.is_a?(Date)
        return nil if value.blank?

        Date.parse(value.to_s)
      rescue ArgumentError
        nil
      end
  end
end
