# Fills MCC, PFC and authorized_date on transactions imported before the gem
# upgrade (design §4.4, R6.5). It reads each Item's whole history from Plaid
# with a fresh cursor and writes only the signal keys onto matching entries.
#
# It never touches `plaid_items.next_cursor`, so the regular sync carries on
# from its own cursor, and it never goes through the importer: no callbacks,
# rules, transfer matching or categorization run, and no entry is created,
# deleted or re-categorized (`update_columns` on the transaction's `extra`).
class Fork::PlaidSignalsBackfill
  # Fill-rate row key: the institution, its Plaid region and the currency.
  Cell = Struct.new(:institution, :region, :currency, :total, :filled, keyword_init: true)

  class Report
    attr_reader :cells, :items_done, :items_deferred, :items_failed,
                :updated, :unchanged, :unmatched, :rolled_back_accounts

    def initialize
      @cells = {}
      @items_done = 0
      @items_deferred = []
      @items_failed = []
      @updated = 0
      @unchanged = 0
      @unmatched = 0
      @rolled_back_accounts = []
    end

    def record_fill(item, plaid_transaction)
      currency = plaid_transaction["iso_currency_code"].presence || plaid_transaction["unofficial_currency_code"].presence
      key = [ item.name, item.plaid_region, currency ]
      cell = (@cells[key] ||= Cell.new(institution: item.name, region: item.plaid_region, currency: currency,
                                       total: 0, filled: Hash.new(0)))
      cell.total += 1
      signals = Fork::PlaidSignals.extract(plaid_transaction)
      Fork::PlaidSignals::KEYS.each { |k| cell.filled[k] += 1 if signals.key?(k) }
    end

    def item_done! = @items_done += 1
    def defer(item) = @items_deferred << item.id
    def fail(item, error) = @items_failed << { item_id: item.id, error: error.class.name }
    def count(updated: 0, unchanged: 0, unmatched: 0)
      @updated += updated
      @unchanged += unchanged
      @unmatched += unmatched
    end

    def rolled_back!(account) = @rolled_back_accounts << account.id

    # @return [Array<Hash>] one row per institution, region and currency, with
    #   the percentage of transactions that carried each key
    def fill_rates
      cells.values.map do |cell|
        {
          institution: cell.institution,
          region: cell.region,
          currency: cell.currency,
          transactions: cell.total,
          rates: Fork::PlaidSignals::KEYS.index_with { |k| (cell.filled[k] * 100.0 / cell.total).round(1) }
        }
      end
    end

    def to_s
      lines = [
        "Plaid signals backfill: #{items_done} items done, #{items_deferred.size} deferred, #{items_failed.size} failed",
        "Entries updated #{updated}, already filled #{unchanged}, Plaid transactions with no entry #{unmatched}"
      ]
      lines << "Accounts rolled back (count or sum changed): #{rolled_back_accounts.join(', ')}" if rolled_back_accounts.any?
      lines << "Fill rate by institution, region and currency (percent of transactions):"
      fill_rates.each do |row|
        rates = row[:rates].map { |k, v| "#{k}=#{v}" }.join(" ")
        lines << "  #{row[:institution]} / #{row[:region]} / #{row[:currency] || 'n/a'} (#{row[:transactions]}): #{rates}"
      end
      lines.join("\n")
    end
  end

  def initialize(items: PlaidItem.active, report: Report.new)
    @items = items
    @report = report
  end

  attr_reader :report

  # Runs every Item, one at a time. An Item that is syncing is deferred and
  # listed in the report so the caller can requeue it.
  def run
    @items.find_each { |item| backfill_item(item) }
    report
  end

  # @return [Symbol] :done, :deferred or :failed
  def backfill_item(item)
    return report.defer(item).then { :deferred } if item.syncing?

    transactions = fetch(item)
    by_account = transactions.group_by { |t| t["account_id"] }

    item.plaid_accounts.each do |plaid_account|
      account = plaid_account.current_account
      account_transactions = by_account.delete(plaid_account.plaid_id) || []
      account_transactions.each { |t| report.record_fill(item, t) }
      next if account.nil?

      write_account(account, account_transactions)
    end
    by_account.each_value { |list| list.each { |t| report.record_fill(item, t) }; report.count(unmatched: list.size) }

    report.item_done!
    :done
  rescue StandardError => e
    report.fail(item, e)
    DebugLogEntry.capture(
      category: "provider_sync",
      level: "warn",
      message: "Plaid signals backfill failed for an Item",
      source: self.class.name,
      provider_key: "plaid",
      family: item.family,
      metadata: { error_class: e.class.name }
    )
    :failed
  end

  private
    def fetch(item)
      response = item.plaid_provider.get_transactions(item.access_token, next_cursor: nil)
      (response.added + response.modified).map { |t| JSON.parse(t.to_json) }
    end

    # One database transaction per account: the entry count and amount sum are
    # taken before and after, and any change undoes that account's writes.
    def write_account(account, plaid_transactions)
      return if plaid_transactions.empty?

      counts = { updated: 0, unchanged: 0, unmatched: 0 }
      Account.transaction do
        before = fingerprint(account)
        entries = account.entries.where(source: PlaidEntry::Processor::SOURCE, entryable_type: "Transaction",
                                        external_id: plaid_transactions.map { |t| t["transaction_id"] })
                         .includes(:entryable).index_by(&:external_id)

        plaid_transactions.each do |plaid_transaction|
          entry = entries[plaid_transaction["transaction_id"]]
          if entry.nil?
            counts[:unmatched] += 1
          elsif merge_signals(entry.entryable, Fork::PlaidSignals.extract(plaid_transaction))
            counts[:updated] += 1
          else
            counts[:unchanged] += 1
          end
        end

        if fingerprint(account) != before
          report.rolled_back!(account)
          raise ActiveRecord::Rollback
        end
        report.count(**counts)
      end
    end

    def fingerprint(account)
      [ account.entries.count, account.entries.sum(:amount) ]
    end

    # @return [Boolean] whether anything was written
    def merge_signals(transaction, signals)
      return false if signals.empty?

      extra = transaction.extra.is_a?(Hash) ? transaction.extra : {}
      plaid = extra["plaid"].is_a?(Hash) ? extra["plaid"] : {}
      merged = plaid.merge(signals)
      return false if merged == plaid

      transaction.update_columns(extra: extra.merge("plaid" => merged))
      true
    end
end
