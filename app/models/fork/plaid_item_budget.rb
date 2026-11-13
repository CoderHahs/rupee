# The Plaid Item budget (design §4.2). The cap belongs to the Plaid team, not
# to a family, so the count spans every family on the instance.
#
#   used = production ledger rows + PLAID_ITEMS_USED_ELSEWHERE (default 0)
#   cap  = PLAID_ITEM_CAP (default 10)
#
# The guard runs before a link token is issued, in production only. Update
# mode creates no Item and is never guarded.
module Fork::PlaidItemBudget
  DEFAULT_CAP = 10

  module_function

  def cap
    integer_env("PLAID_ITEM_CAP", DEFAULT_CAP)
  end

  def used_elsewhere
    integer_env("PLAID_ITEMS_USED_ELSEWHERE", 0)
  end

  def used
    Fork::PlaidItemLedgerEntry.production.count + used_elsewhere
  end

  def remaining
    [ cap - used, 0 ].max
  end

  def at_cap?
    used >= cap
  end

  # Whether the guard applies at all. Sandbox and development never use up a
  # production slot.
  def enforced?
    Rails.env.production?
  end

  # True when a new Link session must not open.
  def blocked?
    enforced? && at_cap?
  end

  # The environment a new Item is created in, which decides whether its ledger
  # row counts against the cap.
  def environment
    ENV.fetch("PLAID_ENV", "sandbox").to_s == "production" ? "production" : "sandbox"
  end

  def record!(plaid_item)
    Fork::PlaidItemLedgerEntry.find_or_create_by!(plaid_id: plaid_item.plaid_id) do |entry|
      entry.family_id = plaid_item.family_id
      entry.plaid_item_id = plaid_item.id
      entry.institution_id = plaid_item.institution_id
      entry.institution_name = plaid_item.name
      entry.environment = environment
    end
  end

  def mark_removed!(plaid_item)
    Fork::PlaidItemLedgerEntry.where(plaid_id: plaid_item.plaid_id, removed_at: nil)
                              .update_all(removed_at: Time.current)
  end

  # Writes a ledger row for each existing Item that has none. Safe to rerun.
  # Returns the number of rows written.
  def backfill!
    written = 0
    PlaidItem.where.not(plaid_id: Fork::PlaidItemLedgerEntry.select(:plaid_id)).find_each do |item|
      entry = record!(item)
      entry.update_columns(created_at: item.created_at)
      written += 1
    end
    written
  end

  def integer_env(name, default)
    Integer(ENV.fetch(name, default), 10)
  rescue ArgumentError, TypeError
    default
  end
end
