# Assigns bare TSX and TSXV tickers to a provider that can price them
# (design §4.7, D20). Prepended to Security::Resolver.
#
# Yahoo adds no suffix to a bare TSX ticker, so it would price `T` as AT&T.
# Alpha Vantage (`.TRT`, `.TRV`) and EODHD (`TO`, `V`) can price them.
# FORK_TSX_PRICE_PROVIDER (alpha_vantage or eodhd, default alpha_vantage)
# names the preferred one. There is no automatic fallback between them.
module Fork::TsxProviderAssignment
  TSX_MICS = %w[XTSE XTSX].freeze
  TSX_PROVIDERS = %w[alpha_vantage eodhd].freeze
  DEFAULT_PROVIDER = "alpha_vantage"

  # The preferred TSX provider, from the environment.
  def self.configured_provider
    value = ENV["FORK_TSX_PRICE_PROVIDER"].to_s.strip.downcase
    TSX_PROVIDERS.include?(value) ? value : DEFAULT_PROVIDER
  end

  private
    def find_or_create_provider_match!(match)
      return super unless fork_tsx_candidate?(match)

      chosen = fork_tsx_provider_for(match)
      return super if chosen.blank? || chosen == match.price_provider.to_s

      super(fork_copy_with_provider(match, chosen))
    end

    # No explicit provider (a search pick or remap wins), a TSX or TSXV
    # listing, and a bare ticker. Dotted tickers such as T.TO are upstream's.
    def fork_tsx_candidate?(match)
      price_provider.blank? &&
        TSX_MICS.include?(Security.canonical_exchange_operating_mic(match.exchange_operating_mic).to_s.upcase) &&
        !match.ticker.to_s.include?(".")
    end

    def fork_tsx_provider_for(match)
      existing = Security.find_by_ticker_and_exchange(
        ticker: match.ticker,
        exchange_operating_mic: match.exchange_operating_mic
      )
      if existing && TSX_PROVIDERS.include?(existing.price_provider.to_s) &&
         Security.provider_for(existing.price_provider)
        return existing.price_provider
      end

      configured = Fork::TsxProviderAssignment.configured_provider
      Security.provider_for(configured) ? configured : match.price_provider.presence
    end

    def fork_copy_with_provider(match, provider)
      copy = match.dup
      copy.price_provider = provider
      copy
    end
end
