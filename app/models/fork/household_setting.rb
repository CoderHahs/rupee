# Rupee's per-family settings (design §5.2): the AI switch and its consent,
# the time-zone confirmation, and the card-benefit thresholds.
#
# Read them through Family#household_settings, which creates the row on first
# read so existing families need no backfill.
class Fork::HouseholdSetting < ApplicationRecord
  self.table_name = "household_settings"

  belongs_to :family
  belongs_to :ai_consented_by, class_name: "User", optional: true

  validates :credit_lead_days, numericality: { only_integer: true, in: 1..60 }
  validates :credit_match_threshold, :missed_value_threshold, numericality: { in: 0..1 }

  def timezone_confirmed?
    timezone_confirmed_at.present?
  end
end
