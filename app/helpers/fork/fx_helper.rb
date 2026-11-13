# Helpers for showing converted amounts (design §4.6, R4.8).
module Fork::FxHelper
  # The quote for converting `from` into the family's currency today, or nil.
  def fork_fx_quote(from, date: Date.current)
    Fork::Fx.lookup(from: from, to: Current.family.currency, date: date)
  end

  # What hover or tap shows: the native amount, the rate, its source, the
  # observation date and how long it was carried.
  def fork_fx_details(native, quote)
    parts = []
    parts << native.format if native
    return parts.join(" · ") unless quote

    parts << t("fork.fx.rate", rate: number_with_precision(quote.rate, precision: 4, strip_insignificant_zeros: true))
    parts << t("fork.fx.source", source: fork_fx_source_name(quote.source)) if quote.source.present?
    parts << t("fork.fx.observed_on", date: l(quote.observed_on, format: :long))
    parts << t("fork.fx.carried", count: quote.carry_days) if quote.carried?
    parts.join(" · ")
  end

  def fork_fx_source_name(source)
    t("fork.fx.sources.#{source}", default: source.to_s.humanize)
  end
end
