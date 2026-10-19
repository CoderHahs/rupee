require "test_helper"

# The household AI switch (design §4.10). Fixture households have it on, so
# each test here turns it off first.
class Fork::AiSwitchTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
    @settings = @family.household_settings
    @provider = mock("llm_provider")
    Provider::Registry.stubs(:preferred_llm_provider).returns(@provider)
  end

  test "the permitted provider follows the switch" do
    assert_equal @provider, @family.permitted_llm_provider

    turn_off

    assert_nil @family.permitted_llm_provider
  end

  test "a family without a settings row has AI off" do
    family = Family.create!(name: "New", currency: "USD")

    assert_not family.household_ai_enabled?
    assert_nil family.permitted_llm_provider
    assert_nil Fork::HouseholdSetting.find_by(family: family)
  end

  test "categorization offers no provider with the switch off" do
    turn_off

    assert_nil @family.resolved_categorization_provider
    assert_nil @family.shadow_categorization_provider
  end

  test "auto-categorization runs only the local categorizer with the switch off" do
    turn_off
    result = Family::BayesCategorizer::Result.new(categorized_ids: [ "a" ], modified_count: 1)
    Family::BayesCategorizer.any_instance.expects(:classify_and_apply).with([ "a", "b" ]).returns(result)
    Family::AutoCategorizer.expects(:new).never

    assert_equal 1, @family.auto_categorize_transactions([ "a", "b" ])
  end

  test "merchant detection does nothing with the switch off" do
    turn_off
    Family::AutoMerchantDetector.expects(:new).never

    assert_equal 0, @family.auto_detect_transaction_merchants([ "a" ])
  end

  test "documents are not uploaded with the switch off" do
    turn_off
    VectorStore.expects(:adapter).never
    VectorStore::Registry.expects(:adapter).never

    assert_nil @family.upload_document(file_content: "x", filename: "notes.txt")
  end

  test "members lose AI with the switch off" do
    member = users(:family_member)
    member.update!(ai_enabled: true)
    assert member.ai_enabled?

    turn_off

    assert_not member.reload.ai_enabled?
    assert_not member.ai_available?
  end

  test "guests need the admin's separate say-so" do
    family = families(:empty)
    guest = users(:intro_user)
    assert guest.guest?

    family.household_settings.update!(ai_for_guests: false)
    assert_not guest.reload.ai_available?
    assert users(:new_email).reload.ai_available?

    family.household_settings.update!(ai_for_guests: true)
    assert guest.reload.ai_available?
  end

  test "no LLM provider is looked up with the switch off" do
    turn_off
    Provider::Registry.unstub(:preferred_llm_provider)
    Provider::Registry.expects(:preferred_llm_provider).never

    assert_equal({ enhanced: 0, deduplicated: 0 }, ProviderMerchant::Enhancer.new(@family).enhance)

    assert_raises(RecurringTransaction::AiSetupSuggester::Error) do
      RecurringTransaction::AiSetupSuggester.new(@family, user: users(:family_admin)).suggest_from_entries([])
    end

    assert_raises(Provider::Error) { imports(:pdf_with_rows).process_with_ai }
    assert_raises(Provider::Error) { imports(:pdf_with_rows).extract_transactions }

    assert_not Rule.new(family: @family, resource_type: "transaction").action_executors.any? { |executor| executor.is_a?(Rule::ActionExecutor::AutoDetectMerchants) }
  end

  private
    def turn_off
      @settings.update!(ai_enabled: false)
      @family.reload
    end
end
