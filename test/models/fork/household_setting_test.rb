require "test_helper"

class Fork::HouseholdSettingTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
  end

  test "a family's settings are created on first read with the design defaults" do
    family = Family.create!(name: "New", currency: "USD")
    assert_nil Fork::HouseholdSetting.find_by(family: family)

    settings = family.household_settings

    assert settings.persisted?
    assert_not settings.ai_enabled?
    assert_not settings.ai_for_guests?
    assert_not settings.card_benefits_enabled?
    assert_not settings.timezone_confirmed?
    assert_equal 7, settings.credit_lead_days
    assert_equal BigDecimal("0.80"), settings.credit_match_threshold
    assert_equal BigDecimal("1.00"), settings.missed_value_threshold
  end

  test "later reads return the same row" do
    first = @family.household_settings

    assert_no_difference "Fork::HouseholdSetting.count" do
      assert_equal first, Family.find(@family.id).household_settings
    end
  end

  test "credit lead days must be between 1 and 60" do
    settings = @family.household_settings

    settings.credit_lead_days = 0
    assert_not settings.valid?

    settings.credit_lead_days = 61
    assert_not settings.valid?

    settings.credit_lead_days = 60
    assert settings.valid?
  end

  test "thresholds must be between 0 and 1" do
    settings = @family.household_settings

    settings.credit_match_threshold = 1.5
    assert_not settings.valid?

    settings.credit_match_threshold = 0.5
    settings.missed_value_threshold = -0.1
    assert_not settings.valid?
  end

  test "the database enforces the ranges too" do
    @family.household_settings

    assert_raises(ActiveRecord::StatementInvalid) do
      Fork::HouseholdSetting.where(family: @family).update_all(credit_lead_days: 0)
    end
  end

  test "deleting the family deletes its settings" do
    family = Family.create!(name: "Settings deletion", currency: "USD")
    settings = family.household_settings

    assert family.destroy
    assert_not Fork::HouseholdSetting.exists?(settings.id)
  end

  test "the database removes the settings when the family row is deleted directly" do
    family = Family.create!(name: "Settings cascade", currency: "USD")
    settings = family.household_settings

    Family.where(id: family.id).delete_all

    assert_not Fork::HouseholdSetting.exists?(settings.id)
  end
end
