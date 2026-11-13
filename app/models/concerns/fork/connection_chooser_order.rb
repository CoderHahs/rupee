# Prepended to Provider::Factory's singleton (design §4.2, open question 16).
# The account-add chooser lists the brokerage connectors, SnapTrade and
# Questrade, above Plaid, because Plaid Items are reserved for banks and
# cards. The order is otherwise unchanged.
module Fork::ConnectionChooserOrder
  BROKERAGE_KEYS = %w[snaptrade questrade].freeze

  def connection_configs_for_account_type(account_type:, family:)
    configs = super
    return configs unless account_type.to_s == "Investment"

    configs.each_with_index.sort_by { |config, index| [ BROKERAGE_KEYS.include?(config[:key].to_s) ? 0 : 1, index ] }.map(&:first)
  end
end
