# A security's latest known price with the date it was observed (design §4.7).
module Fork
  PriceQuote = Struct.new(:money, :observed_on, :provider, :as_of, keyword_init: true) do
    # Days between today and the observation. Zero for a price observed today.
    def carry_days
      [ (as_of - observed_on).to_i, 0 ].max
    end

    # A carry of up to this many days renders as an ordinary price (weekends
    # and a holiday); a longer one is labelled with its date.
    NORMAL_CARRY_DAYS = 3

    def stale?
      carry_days > NORMAL_CARRY_DAYS
    end
  end
end
