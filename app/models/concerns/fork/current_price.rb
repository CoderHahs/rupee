# Security#current_price_quote and a current_price that falls back to the
# latest stored row (design §4.7, D21).
module Fork::CurrentPrice
  REFRESH_INTERVAL = 1.hour

  # Memoized Fork::PriceQuote, or nil for a security with no stored rows.
  def current_price_quote
    return @current_price_quote if defined?(@current_price_quote)

    @current_price_quote = build_current_price_quote
  end

  def current_price
    current_price_quote&.money
  end

  private
    def build_current_price_quote
      row = prices.find_by(date: Date.current)
      row ||= fork_refresh_price
      row ||= prices.where("price > 0").order(date: :desc, updated_at: :desc).first
      return nil if row.nil?

      Fork::PriceQuote.new(
        money: Money.new(row.price, row.currency),
        observed_on: row.observed_on || row.date,
        provider: price_provider,
        as_of: Date.current
      )
    end

    # Upstream's fetch, at most once an hour per security whatever the outcome.
    def fork_refresh_price
      key = "fork:price_refresh:#{id}"
      return nil if Rails.cache.exist?(key)

      Rails.cache.write(key, true, expires_in: REFRESH_INTERVAL)
      find_or_fetch_price
    end
end
