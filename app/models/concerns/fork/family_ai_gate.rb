# Prepended to Family (design §4.10). These methods live in family.rb, which
# upstream changes often, so the switch wraps them instead of editing them.
module Fork::FamilyAiGate
  def resolved_categorization_provider(&)
    super if household_ai_enabled?
  end

  def shadow_categorization_provider(&)
    super if household_ai_enabled?
  end

  # With AI off only the local Bayes categorizer runs. Upstream hands what it
  # leaves to the LLM categorizer, which raises without a provider.
  def auto_categorize_transactions(transaction_ids)
    return super if household_ai_enabled?

    Family::BayesCategorizer.new(self).classify_and_apply(transaction_ids).modified_count
  end

  # The merchant detector raises without a provider, so with AI off there is
  # nothing to detect.
  def auto_detect_transaction_merchants(transaction_ids)
    return super if household_ai_enabled?

    0
  end

  # Documents go to the provider's vector store. Callers treat nil as a
  # failed upload.
  def upload_document(...)
    super if household_ai_enabled?
  end
end
