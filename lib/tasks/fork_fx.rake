namespace :fork do
  desc "Re-import each stored currency pair once with observation dates and sources (design §4.6); prints changed rows and the largest change per pair"
  task fx_backfill: :environment do
    provider = ExchangeRate.provider
    abort "No exchange rate provider configured; set EXCHANGE_RATE_PROVIDER=fx_router" unless provider

    pairs = ExchangeRate.distinct.pluck(:from_currency, :to_currency)
    # One direction per pair: CAD as the quote when present, else the sorted order.
    directions = pairs.map { |from, to| to == "CAD" || (from != "CAD" && from < to) ? [ from, to ] : [ to, from ] }.uniq

    directions.each do |from, to|
      earliest = ExchangeRate.where(from_currency: [ from, to ], to_currency: [ from, to ]).minimum(:date)
      next unless earliest

      before = ExchangeRate.where(from_currency: from, to_currency: to).pluck(:date, :rate).to_h
      ExchangeRate.import_provider_rates(from: from, to: to, start_date: earliest, end_date: Date.current, clear_cache: true)
      after = ExchangeRate.where(from_currency: from, to_currency: to).pluck(:date, :rate).to_h

      changes = after.filter_map do |date, rate|
        old = before[date]
        next unless old && old.nonzero?
        ((rate - old) / old).abs
      end.select(&:nonzero?)
      puts "#{from}/#{to}: #{changes.size} changed rows, largest change #{(changes.max.to_f * 100).round(3)}%"
    end
  end

  desc "Fail when an exchange rate has no observation date or a carry longer than the date allows"
  task fx_check_invariants: :environment do
    missing = ExchangeRate.where(observed_on: nil).count
    future = ExchangeRate.where("observed_on > date").count
    abort "#{missing} exchange rates have no observed_on; run fork:fx_backfill" if missing.positive?
    abort "#{future} exchange rates are observed after their date" if future.positive?
    puts "Exchange rate invariants hold"
  end
end
