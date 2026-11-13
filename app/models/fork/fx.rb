# Exchange-rate lookup for the fork (design §4.6). It uses the latest
# observation up to 7 days before the date, says how many days it carried it,
# and returns nil rather than a rate of 1 when there is none.
module Fork::Fx
  MAX_CARRY_DAYS = 7
  MISS_TTL = 1.hour

  module_function

  # @return [Fork::FxQuote, nil]
  def lookup(from:, to:, date:, fetch: true, cache: true)
    from, to = from.to_s, to.to_s
    return Fork::FxQuote.new(rate: BigDecimal("1"), source: nil, observed_on: date, carry_days: 0, row: nil) if from == to

    quote = stored_quote(from, to, date)
    return note(quote, from, to, date) if quote
    return miss(from, to, date) unless fetch
    return miss(from, to, date) if Rails.cache.read(miss_key(from, to, date))

    fetched = fetch_and_cache(from, to, date, cache: cache)
    quote = stored_quote(from, to, date) if cache
    quote ||= quote_from_rate(fetched, date) if fetched
    return note(quote, from, to, date) if quote

    Rails.cache.write(miss_key(from, to, date), true, expires_in: MISS_TTL)
    miss(from, to, date)
  end

  # Rates for several currencies at once. A currency with no rate is left out.
  # @return [Hash{String => BigDecimal}]
  def rates_for(currencies, to:, date:)
    currencies = currencies.uniq
    return {} if currencies.empty?

    stored = ExchangeRate
      .where(from_currency: currencies, to_currency: to, date: (date - MAX_CARRY_DAYS)..date)
      .where("rate > 0")
      .where("COALESCE(observed_on, date) >= ?", date - MAX_CARRY_DAYS)
      .to_a
      .group_by(&:from_currency)

    currencies.each_with_object({}) do |currency, result|
      row = stored[currency]&.max_by { |r| [ r.observed_on || r.date, r.date ] }
      quote = row ? note(quote_from_row(row, date), currency, to, date) : lookup(from: currency, to: to, date: date)
      result[currency] = quote.rate if quote
    end
  end

  def stored_quote(from, to, date)
    row = ExchangeRate
      .where(from_currency: from, to_currency: to, date: (date - MAX_CARRY_DAYS)..date)
      .where("rate > 0")
      .where("COALESCE(observed_on, date) >= ?", date - MAX_CARRY_DAYS)
      .order(Arel.sql("COALESCE(observed_on, date) DESC, date DESC"))
      .first
    row && quote_from_row(row, date)
  end

  def quote_from_row(row, date)
    observed = row.observed_on || row.date
    Fork::FxQuote.new(rate: row.rate, source: row.source, observed_on: observed, carry_days: (date - observed).to_i, row: row)
  end

  def quote_from_rate(rate, date)
    return nil if (date - rate.date).to_i > MAX_CARRY_DAYS || rate.date > date

    Fork::FxQuote.new(rate: rate.rate, source: source_of(rate), observed_on: rate.date, carry_days: (date - rate.date).to_i, row: nil)
  end

  def fetch_and_cache(from, to, date, cache:)
    provider = ExchangeRate.provider
    return nil unless provider.present?

    response = provider.fetch_exchange_rate(from: from, to: to, date: date)
    return nil unless response.success?

    rate = response.data
    return rate unless cache && rate.rate.to_f > 0

    begin
      ExchangeRate.find_or_create_by!(from_currency: rate.from, to_currency: rate.to, date: rate.date) do |row|
        row.rate = rate.rate
        row.observed_on = rate.date
        row.source = source_of(rate)
      end
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      # Another process inserted it between our SELECT and INSERT.
    end
    rate
  end

  def source_of(rate)
    (rate.source if rate.respond_to?(:source)).presence ||
      (ENV["EXCHANGE_RATE_PROVIDER"].presence || Setting.exchange_rate_provider).to_s
  end

  def note(quote, from, to, date)
    if quote.carried?
      Fork::RequestFx.instance.record_carry(from: from, to: to, date: date, observed_on: quote.observed_on, carry_days: quote.carry_days)
    end
    quote
  end

  def miss(from, to, date)
    Fork::RequestFx.instance.record_miss(from: from, to: to, date: date)
    nil
  end

  def miss_key(from, to, date)
    "fork:fx_miss:#{from}:#{to}:#{date}"
  end
end
