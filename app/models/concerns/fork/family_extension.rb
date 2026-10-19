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
end
