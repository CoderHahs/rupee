# Text for a Fork::PriceQuote where markup is not possible, such as an
# <option> label (design §4.7).
module Fork::PriceLabelHelper
  def fork_price_text(quote)
    return t("fork.price_label.none") if quote.nil?

    text = format_money(quote.money)
    text += " (#{t('fork.price_label.last_price', date: l(quote.observed_on, format: :long))})" if quote.stale?
    text
  end
end
