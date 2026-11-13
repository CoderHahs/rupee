# Fills security_prices.observed_on for rows written before the column existed
# (design §4.7). A non-provisional row was observed on its own date. A
# provisional row carries the date of the latest earlier non-provisional row of
# the same security and currency, else its own date. Only rows written after
# the migration are exact. Idempotent: it only touches rows with no value.
class Fork::PriceObservedOnBackfill
  Result = Struct.new(:observed_own_date, :carried, :remaining_null, keyword_init: true)

  def self.run!(dry_run: false)
    new(dry_run: dry_run).run!
  end

  def initialize(dry_run: false)
    @dry_run = dry_run
  end

  def run!
    own = Security::Price.where(observed_on: nil, provisional: false)
    carried_scope = Security::Price.where(observed_on: nil, provisional: true)
    result = Result.new(observed_own_date: own.count, carried: carried_scope.count)

    unless @dry_run
      own.update_all("observed_on = date")
      carried_scope.update_all(<<~SQL.squish)
        observed_on = COALESCE(
          (SELECT MAX(earlier.date) FROM security_prices earlier
            WHERE earlier.security_id = security_prices.security_id
              AND earlier.currency = security_prices.currency
              AND earlier.provisional = FALSE
              AND earlier.date < security_prices.date),
          security_prices.date
        )
      SQL
    end

    result.remaining_null = Security::Price.where(observed_on: nil).count
    result
  end
end
