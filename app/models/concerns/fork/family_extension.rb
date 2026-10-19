# Fork additions to Family, applied in config/initializers/fork.rb so
# family.rb stays unedited (design §4.1).
module Fork::FamilyExtension
  extend ActiveSupport::Concern

  included do
    has_one :household_setting, class_name: "Fork::HouseholdSetting", dependent: :destroy
  end

  # The family's settings row, created on first read. Two requests racing to
  # create it both end up with the same row.
  def household_settings
    household_setting || create_household_setting!
  rescue ActiveRecord::RecordNotUnique
    reload_household_setting
  end

  # The household AI switch (design §4.10). Reads without creating the row,
  # because jobs and views ask it too; a family with no row has AI off.
  def household_ai_enabled?
    household_setting&.ai_enabled? || false
  end

  # Whether this member may send household data to an AI provider. Guests
  # need the admin's separate say-so, because upstream turns AI on for them.
  def ai_allowed_for?(user)
    return false unless household_ai_enabled?

    !user&.guest? || household_setting.ai_for_guests?
  end

  # The LLM provider this household's data may go to, or nil while the
  # switch is off. Every LLM call site goes through it, and
  # bin/check-fork-surface fails on a new site that does not.
  def permitted_llm_provider
    Provider::Registry.preferred_llm_provider if household_ai_enabled?
  end
end
