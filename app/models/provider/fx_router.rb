# Routes each currency pair to the right rate source (design §4.6, D9). A CAD
# pair whose other currency has a Bank of Canada series goes to the Bank of
# Canada; every other pair, a Valet error or an empty answer, and the part of a
# range more than 7 days before Valet's first observation go to Frankfurter.
# Select it with EXCHANGE_RATE_PROVIDER=fx_router.
class Provider::FxRouter < Provider
  include ExchangeRateConcept

  Error = Class.new(Provider::Error)

  FRANKFURTER_SOURCE = "frankfurter".freeze

  def initialize(bank_of_canada: Provider::BankOfCanada.new, frankfurter: Provider::Frankfurter.new)
    @bank_of_canada = bank_of_canada
    @frankfurter = frankfurter
  end

  def healthy?
    with_provider_response do
      [ bank_of_canada, frankfurter ].all? { |p| p.healthy?.success? }
    end
  end

  def usage
    with_provider_response do
      UsageData.new(used: nil, limit: nil, utilization: nil, plan: "Free (no key required)")
    end
  end

  def fetch_exchange_rate(from:, to:, date:)
    if routed_to_bank_of_canada?(from, to)
      response = bank_of_canada.fetch_exchange_rate(from: from, to: to, date: date)
      return response if response.success?

      Rails.logger.info("[Provider::FxRouter] Valet had no rate for #{from}/#{to} on #{date}; using Frankfurter")
    end

    from_frankfurter(frankfurter.fetch_exchange_rate(from: from, to: to, date: date))
  end

  def fetch_exchange_rates(from:, to:, start_date:, end_date:)
    unless routed_to_bank_of_canada?(from, to)
      return from_frankfurter(frankfurter.fetch_exchange_rates(from: from, to: to, start_date: start_date, end_date: end_date))
    end

    response = bank_of_canada.fetch_exchange_rates(from: from, to: to, start_date: start_date, end_date: end_date)
    if !response.success? || response.data.empty?
      Rails.logger.info("[Provider::FxRouter] Valet had no rates for #{from}/#{to} between #{start_date} and #{end_date}; using Frankfurter")
      return from_frankfurter(frankfurter.fetch_exchange_rates(from: from, to: to, start_date: start_date, end_date: end_date))
    end

    valet_rates = response.data
    first_date = valet_rates.map(&:date).min
    return response unless start_date < first_date - Provider::BankOfCanada::LOOKBACK_DAYS

    earlier = from_frankfurter(frankfurter.fetch_exchange_rates(from: from, to: to, start_date: start_date, end_date: first_date - 1))
    return response unless earlier.success?

    with_provider_response { (earlier.data + valet_rates).sort_by(&:date) }
  end

  def max_history_days
    nil
  end

  private
    attr_reader :bank_of_canada, :frankfurter

    def routed_to_bank_of_canada?(from, to)
      Provider::BankOfCanada.supports?(from, to)
    end

    # Tags Frankfurter's rates with their source.
    def from_frankfurter(response)
      return response unless response.success?

      data = Array.wrap(response.data).map { |r| sourced(r) }
      with_provider_response { response.data.is_a?(Array) ? data : data.first }
    end

    def sourced(rate)
      Fork::SourcedRate.new(date: rate.date, from: rate.from, to: rate.to, rate: rate.rate, source: FRANKFURTER_SOURCE)
    end
end
