# Changes to Security::HealthChecker (design §4.7). run_check, with its Sentry
# rescue and its last_health_check_at ensure, stays upstream's.
#
# - Probe a 7-day window, not the exact date of today, which Twelve Data, EODHD
#   and Tiingo cannot serve.
# - Skip Alpha Vantage and EODHD: their daily quota is shared with imports.
# - Record no verdict without a provider or on a rate limit.
# - Keep prices when a security goes offline.
module Fork::HealthCheckPolicy
  PROBE_WINDOW_DAYS = 7
  SKIPPED_PROVIDERS = [ Provider::AlphaVantage, Provider::Eodhd ].freeze

  private
    def latest_provider_price
      @fork_no_verdict = false

      if provider.blank?
        @fork_no_verdict = true
        return nil
      end
      return true if SKIPPED_PROVIDERS.any? { |klass| provider.is_a?(klass) }

      end_date = Date.current
      response = provider.fetch_security_prices(
        symbol: security.ticker,
        exchange_operating_mic: security.exchange_operating_mic,
        start_date: end_date - PROBE_WINDOW_DAYS.days,
        end_date: end_date
      )

      unless response.success?
        @fork_no_verdict = rate_limited?(response.error)
        return nil
      end

      response.data.any? { |p| p.price.to_f > 0 } || nil
    end

    def handle_failure
      return if @fork_no_verdict

      super
    end

    # Offline as upstream does, but the prices stay (R5.5).
    def convert_to_offline_security!
      security.update!(
        offline: true,
        offline_reason: "health_check_failed",
        failed_fetch_count: Security::HealthChecker::MAX_CONSECUTIVE_FAILURES + 1,
        failed_fetch_at: Time.current
      )
    end

    def rate_limited?(error)
      error.class.name.to_s.end_with?("::RateLimitError") || error.class.name.to_s == "RateLimitError"
    end
end
