require "test_helper"

# With the household AI switch off, no LLM provider is contacted, even with
# real OpenAI and Anthropic keys configured (R13.3, task 2.7).
class Fork::NoLlmContactTest < ActiveSupport::TestCase
  LLM_HOSTS = %r{\Ahttps://(api\.openai\.com|api\.anthropic\.com)/}

  setup do
    @family = families(:dylan_family)
    @admin = users(:family_admin)
    @llm = stub_request(:any, LLM_HOSTS).to_return(status: 500)
  end

  test "the keys are real, so the switch is what keeps the providers away" do
    with_llm_keys do
      assert_kind_of Provider::Openai, @family.permitted_llm_provider
    end
  end

  test "no LLM host is contacted with the switch off" do
    @family.household_settings.update!(ai_enabled: false)
    @family.reload

    with_llm_keys do
      assert_nil @family.permitted_llm_provider
      assert_not @admin.reload.ai_enabled?

      transaction_ids = Transaction.joins(entry: :account).where(accounts: { family_id: @family.id }).limit(5).pluck(:id)
      assert transaction_ids.any?

      @family.auto_categorize_transactions(transaction_ids)
      @family.auto_detect_transaction_merchants(transaction_ids)
      ProviderMerchant::Enhancer.new(@family).enhance
      assert_nil @family.upload_document(file_content: "statement", filename: "statement.txt")
      Insight::BodyWriter.new(@family).write(generated_insight)

      assert_raises(RecurringTransaction::AiSetupSuggester::Error) do
        RecurringTransaction::AiSetupSuggester.new(@family, user: @admin).suggest_from_entries([])
      end
      assert_raises(Provider::Error) { imports(:pdf_with_rows).process_with_ai }
      assert_raises(Provider::Error) { imports(:pdf_with_rows).extract_transactions }
    end

    assert_not_requested @llm
  end

  private
    def with_llm_keys(&block)
      with_env_overrides(
        "OPENAI_ACCESS_TOKEN" => "sk-test-openai", # pipelock:ignore
        "ANTHROPIC_ACCESS_TOKEN" => "sk-ant-test", # pipelock:ignore
        "OPENAI_URI_BASE" => nil,
        "ANTHROPIC_BASE_URL" => nil,
        "LLM_PROVIDER" => "openai",
        &block
      )
    end

    def generated_insight
      Insight::Generator::GeneratedInsight.new(
        insight_type: "idle_cash",
        priority: "low",
        title: "Idle cash in Emergency fund",
        template_key: "idle_cash",
        facts: { account: "Emergency fund", balance: "$28,400.00", idle_days: 60 },
        metadata: { account_id: "acct", balance: 28_400.0 },
        currency: "USD",
        period_start: nil,
        period_end: nil,
        dedup_key: "idle_cash:acct:2026-07"
      )
    end
end
