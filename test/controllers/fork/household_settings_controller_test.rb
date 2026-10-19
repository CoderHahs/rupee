require "test_helper"

class Fork::HouseholdSettingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:family_admin)
    @family = @admin.family
  end

  test "an admin sees the household page" do
    sign_in @admin

    get settings_household_path

    assert_response :success
    assert_select "select[name='household[timezone]']"
  end

  test "members cannot open the household page" do
    sign_in users(:family_member)

    get settings_household_path

    assert_redirected_to accounts_path
  end

  test "members cannot confirm the time zone" do
    sign_in users(:family_member)

    patch settings_household_path, params: { household: { timezone: "America/New_York" } }

    assert_redirected_to accounts_path
    assert_not @family.household_settings.timezone_confirmed?
  end

  test "confirming sets the family's time zone and records the confirmation" do
    sign_in @admin

    freeze_time do
      patch settings_household_path, params: { household: { timezone: "America/New_York" } }

      assert_redirected_to settings_household_path
      assert_equal "America/New_York", @family.reload.timezone
      assert_equal Time.current, @family.household_settings.timezone_confirmed_at
    end
  end

  test "a blank time zone is not confirmed" do
    sign_in @admin

    patch settings_household_path, params: { household: { timezone: "" } }

    assert_response :unprocessable_entity
    assert_not @family.household_settings.timezone_confirmed?
  end

  test "an unknown time zone is not confirmed" do
    sign_in @admin
    original = @family.timezone

    patch settings_household_path, params: { household: { timezone: "Mars/Olympus_Mons" } }

    assert_response :unprocessable_entity
    assert_equal original.to_s, @family.reload.timezone.to_s
    assert_not @family.household_settings.timezone_confirmed?
  end

  test "admins see the time zone banner until the time zone is confirmed" do
    sign_in @admin

    get root_path
    assert_select "a[href='#{settings_household_path}']", text: "Confirm time zone"

    @family.household_settings.update!(timezone_confirmed_at: Time.current)

    get root_path
    assert_select "a[href='#{settings_household_path}']", text: "Confirm time zone", count: 0
  end

  test "members do not see the time zone banner" do
    sign_in users(:family_member)

    get root_path

    assert_select "a[href='#{settings_household_path}']", count: 0
  end
end
