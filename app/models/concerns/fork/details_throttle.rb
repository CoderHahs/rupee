# Alpha Vantage and EODHD cap requests per day, and details cost a request on
# every import until the security has a name and a logo or website. Asks for
# details at most once every 7 days per security (design §4.7).
module Fork::DetailsThrottle
  INTERVAL = 7.days
  THROTTLED_PROVIDERS = %w[alpha_vantage eodhd].freeze

  def import_provider_details(clear_cache: false)
    return super unless throttled?(clear_cache)

    key = "fork:details_attempt:#{id}"
    return if Rails.cache.exist?(key)

    # Written before super, so a failing request still counts.
    Rails.cache.write(key, true, expires_in: INTERVAL)
    super
  end

  private
    def throttled?(clear_cache)
      return false if clear_cache
      return false unless THROTTLED_PROVIDERS.include?(details_provider_key)

      # Upstream's gate: already has a name and a logo or website.
      !(name.present? && (logo_url.present? || website_url.present?))
    end

    def details_provider_key
      price_provider.presence || price_data_provider&.class&.name&.demodulize&.underscore.to_s
    end
end
