# Prepended to PlaidAccount::Processor (design §4.3). An account the user
# revoked at the institution is no longer processed; its history stays.
module Fork::RevokedAccountGate
  def process
    return if plaid_account.revoked_at.present?

    super
  end
end
