require "test_helper"

class Fork::HouseholdAisControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:family_admin)
    @settings = @admin.family.household_settings
    @settings.update!(ai_enabled: false, ai_consented_at: nil, ai_for_guests: false)
    Provider::Openai.stubs(:configured?).returns(true)
    Provider::Anthropic.stubs(:configured?).returns(true)
  end

  test "an admin sees what Rupee sends and the consent form" do
    sign_in @admin

    get settings_household_ai_path

    assert_response :success
    assert_select "li", text: I18n.t("fork.household_ais.show.sends.statements")
    assert_select "select[name='household_ai[provider]'] option", 2
    assert_select "input[name='household_ai[consent]']"
  end

  test "members cannot open or change the AI settings" do
    sign_in users(:family_member)

    get settings_household_ai_path
    assert_redirected_to accounts_path

    patch settings_household_ai_path, params: { household_ai: { provider: "openai", consent: "1" } }
    assert_redirected_to accounts_path
    assert_not @settings.reload.ai_enabled?
  end

  test "turning Rupee on records the consent and the provider" do
    sign_in @admin

    with_env_overrides("LLM_PROVIDER" => nil) do
      patch settings_household_ai_path, params: { household_ai: { provider: "anthropic", consent: "1", ai_for_guests: "1" } }
    end

    assert_redirected_to settings_household_ai_path
    @settings.reload
    assert @settings.ai_enabled?
    assert @settings.ai_for_guests?
    assert_equal @admin, @settings.ai_consented_by
    assert_in_delta Time.current, @settings.ai_consented_at, 5.seconds
    assert_equal "anthropic", Setting.llm_provider
  ensure
    Setting.llm_provider = "openai"
  end

  test "Rupee stays off without consent" do
    sign_in @admin

    patch settings_household_ai_path, params: { household_ai: { provider: "openai", consent: "0" } }

    assert_response :unprocessable_entity
    assert_not @settings.reload.ai_enabled?
    assert_nil @settings.ai_consented_at
  end

  test "Rupee stays off with a provider that is not set up" do
    Provider::Anthropic.stubs(:configured?).returns(false)
    sign_in @admin

    with_env_overrides("LLM_PROVIDER" => nil) do
      patch settings_household_ai_path, params: { household_ai: { provider: "anthropic", consent: "1" } }
    end

    assert_response :unprocessable_entity
    assert_not @settings.reload.ai_enabled?
  end

  test "without a configured provider the page says so instead of offering consent" do
    Provider::Openai.stubs(:configured?).returns(false)
    Provider::Anthropic.stubs(:configured?).returns(false)
    sign_in @admin

    get settings_household_ai_path

    assert_response :success
    assert_select "input[name='household_ai[consent]']", 0
    assert_includes response.body, I18n.t("fork.household_ais.show.no_provider_title")
  end

  test "turning Rupee off keeps the record of consent" do
    @settings.update!(ai_enabled: true, ai_consented_at: 1.day.ago, ai_consented_by: @admin)
    sign_in @admin

    delete settings_household_ai_path

    assert_redirected_to settings_household_ai_path
    assert_not @settings.reload.ai_enabled?
    assert_not_nil @settings.ai_consented_at
  end

  test "the dashboard invites an admin to set up Rupee until someone decides" do
    sign_in @admin

    get root_path
    assert_select "a[href='#{settings_household_ai_path}']", text: I18n.t("fork.banners.ai_setup_action")

    @settings.update!(ai_consented_at: Time.current)
    get root_path
    assert_select "a[href='#{settings_household_ai_path}']", count: 0
  end

  test "members are not invited to set up Rupee" do
    sign_in users(:family_member)

    get root_path

    assert_select "a[href='#{settings_household_ai_path}']", count: 0
  end
end
