# Replaces ExchangeRate's rate lookups with Fork::Fx, prepended to
# ExchangeRate's singleton class in config/initializers/fork.rb (design §4.6).
module Fork::ExchangeRateLookup
  # Returns an ExchangeRate (an unsaved one for identity and for rates not
  # cached), or nil when no rate is within 7 days of the date.
  def find_or_fetch_rate(from:, to:, date: Date.current, cache: true)
    quote = Fork::Fx.lookup(from: from, to: to, date: date, cache: cache)
    return nil unless quote

    quote.row || ExchangeRate.new(
      from_currency: from, to_currency: to, date: quote.observed_on,
      rate: quote.rate, observed_on: quote.observed_on, source: quote.source
    )
  end

  # Currencies with no rate are left out, so callers contribute 0 for them
  # instead of converting at a rate of 1.
  def rates_for(currencies, to:, date: Date.current)
    Fork::Fx.rates_for(currencies, to: to, date: date)
  end
end
