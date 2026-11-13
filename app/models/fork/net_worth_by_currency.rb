# Net worth by native currency (design §4.6, R4.10): for each currency, assets
# minus liabilities in that currency, then the amount in the family's currency.
# A currency with no rate within 7 days has no converted amount.
class Fork::NetWorthByCurrency
  Row = Data.define(:currency, :native, :converted, :quote) do
    def converted? = !converted.nil?
  end

  def initialize(family, accounts: nil)
    @family = family
    @accounts = accounts || family.accounts.visible
  end

  def rows
    @rows ||= accounts.to_a.reject { |a| a.respond_to?(:exclude_from_reports?) && a.exclude_from_reports? }
      .group_by(&:currency)
      .map { |currency, list| build_row(currency, list) }
      .sort_by { |r| [ r.currency == family.currency ? 0 : 1, r.currency ] }
  end

  # Worth showing only when the household holds more than one currency.
  def multi_currency? = rows.size > 1

  private
    attr_reader :family, :accounts

    def build_row(currency, list)
      amount = list.sum(BigDecimal("0")) { |a| a.asset? ? a.balance : -a.balance }
      native = Money.new(amount, currency)
      return Row.new(currency: currency, native: native, converted: native, quote: nil) if currency == family.currency

      quote = Fork::Fx.lookup(from: currency, to: family.currency, date: Date.current)
      Row.new(currency: currency, native: native, converted: quote && Money.new(amount * quote.rate, family.currency), quote: quote)
    end
end
