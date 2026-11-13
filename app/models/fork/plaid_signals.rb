# The transaction signals Rupee keeps from Plaid beyond what upstream stores
# (design §4.4): MCC, personal finance category and authorized_date. The
# importer and the backfill both build the keys here so they cannot drift.
module Fork::PlaidSignals
  KEYS = %w[
    merchant_category_code
    pfc_primary
    pfc_detailed
    pfc_confidence_level
    pfc_version
    authorized_date
  ].freeze

  # Plaid's default can change under the app (D6), so the version is always sent.
  # v2 is what Sure's category taxonomy follows (open question 21); the ENV
  # override exists for the case the live check disagrees.
  DEFAULT_PFC_VERSION = "v2".freeze

  def self.pfc_version
    ENV["PLAID_PFC_VERSION"].presence || DEFAULT_PFC_VERSION
  end

  # @param plaid_transaction [Hash, nil] one Plaid transaction with string or symbol keys
  # @return [Hash{String=>Object}] the signal keys Plaid sent; absent values are left out
  def self.extract(plaid_transaction)
    return {} unless plaid_transaction.respond_to?(:to_h)

    txn = plaid_transaction.to_h.with_indifferent_access
    pfc = txn[:personal_finance_category]
    pfc = {} unless pfc.respond_to?(:to_h)
    pfc = pfc.to_h.with_indifferent_access

    signals = {
      "merchant_category_code" => txn[:merchant_category_code].presence&.to_s,
      "pfc_primary" => pfc[:primary].presence,
      "pfc_detailed" => pfc[:detailed].presence,
      "pfc_confidence_level" => pfc[:confidence_level].presence,
      "authorized_date" => txn[:authorized_date].presence&.to_s
    }.compact
    signals["pfc_version"] = pfc_version if signals.keys.any? { |k| k.start_with?("pfc_") }
    signals
  end
end
