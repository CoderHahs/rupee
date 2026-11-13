# The Bank of Canada's Valet API (https://www.bankofcanada.ca/valet/docs).
# No key is needed. The FX_RATES_DAILY group publishes one indicative rate per
# business day, by 16:30 ET, as foreign currency to CAD. Only CAD pairs whose
# other currency is one of the pinned series are served (design §4.6, D9).
class Provider::BankOfCanada < Provider
  include ExchangeRateConcept, RateLimitable
  extend SslConfigurable

  Error = Class.new(Provider::Error)
  RateLimitError = Class.new(Error)

  SOURCE = "bank_of_canada".freeze
  BASE_URL = "https://www.bankofcanada.ca/valet".freeze

  # The 27 series of FX_RATES_DAILY, each named FX<CUR>CAD. A nightly network
  # test compares this list with the group, so a renamed series fails the build
  # instead of turning into missing rates.
  CURRENCIES = %w[
    AUD BRL CHF CNY EUR GBP HKD IDR INR JPY KRW MXN MYR NOK NZD PEN PLN RUB
    SAR SEK SGD THB TRY TWD USD VND ZAR
  ].freeze

  # A single-date request looks back this many days for the latest observation.
  LOOKBACK_DAYS = 7

  MIN_REQUEST_INTERVAL = 0.15

  def self.supports?(from, to)
    from, to = from.to_s.upcase, to.to_s.upcase
    (to == "CAD" && CURRENCIES.include?(from)) || (from == "CAD" && CURRENCIES.include?(to))
  end

  def healthy?
    with_provider_response do
      body = get_json("/series/FXUSDCAD/json")
      raise Error, "Valet returned no series detail" unless body.is_a?(Hash) && body["seriesDetail"].present?
      true
    end
  end

  def usage
    with_provider_response do
      UsageData.new(used: nil, limit: nil, utilization: nil, plan: "Free (no key required)")
    end
  end

  # The latest observation on or before `date`, under its own date, or an
  # error when the 7 days ending on `date` hold none.
  def fetch_exchange_rate(from:, to:, date:)
    with_provider_response do
      from, to = normalize(from), normalize(to)
      next Rate.new(date: date, from: from, to: to, rate: 1.0) if from == to

      rates = observations(from, to, date - LOOKBACK_DAYS, date)
      raise Error, "No Bank of Canada observation for #{from}/#{to} in the 7 days ending #{date}" if rates.empty?

      rates.max_by(&:date)
    end
  end

  # Business days only, so the importer's gapfill covers weekends and holidays.
  def fetch_exchange_rates(from:, to:, start_date:, end_date:)
    with_provider_response do
      from, to = normalize(from), normalize(to)
      if from == to
        (start_date..end_date).map { |d| Rate.new(date: d, from: from, to: to, rate: 1.0) }
      else
        observations(from, to, start_date, end_date)
      end
    end
  end

  def max_history_days
    nil
  end

  private
    def normalize(code)
      code.to_s.upcase.gsub(/[^A-Z]/, "")
    end

    def observations(from, to, start_date, end_date)
      raise Error, "No Bank of Canada series for #{from}/#{to}" unless self.class.supports?(from, to)

      foreign = to == "CAD" ? from : to
      series = "FX#{foreign}CAD"
      body = get_json("/observations/#{series}/json", "start_date" => start_date.to_s, "end_date" => end_date.to_s)
      raise Error, "Unexpected Valet response shape" unless body.is_a?(Hash) && body["observations"].is_a?(Array)

      body["observations"].filter_map do |obs|
        value = obs.dig(series, "v")
        next if value.blank?

        value = BigDecimal(value.to_s)
        next unless value > 0

        rate = to == "CAD" ? value : (BigDecimal("1") / value).round(12)
        Fork::SourcedRate.new(date: Date.parse(obs["d"].to_s), from: from, to: to, rate: rate, source: SOURCE)
      end.sort_by(&:date)
    rescue Date::Error, ArgumentError => e
      raise Error, "Invalid Valet observation: #{e.message}"
    end

    def base_url
      ENV["BANK_OF_CANADA_URL"].presence || BASE_URL
    end

    def get_json(path, params = {})
      throttle_request
      response = client.get("#{base_url}#{path}") do |req|
        params.each { |k, v| req.params[k] = v }
      end
      JSON.parse(response.body)
    rescue JSON::ParserError => e
      raise Error, "Invalid Valet response: #{e.message}"
    end

    def client
      @client ||= Faraday.new(url: base_url, ssl: self.class.faraday_ssl_options) do |faraday|
        faraday.options.open_timeout = 5
        faraday.options.timeout      = 20

        faraday.request(:retry, {
          max: 3,
          interval: 0.5,
          interval_randomness: 0.5,
          backoff_factor: 2,
          exceptions: Faraday::Retry::Middleware::DEFAULT_EXCEPTIONS + [ Faraday::ConnectionFailed ]
        })

        faraday.response :raise_error
        faraday.headers["Accept"] = "application/json"
      end
    end
end
