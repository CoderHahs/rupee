# The answer to Fork::Fx.lookup: a rate, where it came from, the day it was
# observed and how many days it was carried (design §4.6). `row` is the stored
# ExchangeRate, or nil for identity and for rates fetched without caching.
Fork::FxQuote = Data.define(:rate, :source, :observed_on, :carry_days, :row) do
  def carried? = carry_days.positive?
end
