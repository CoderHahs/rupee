# Carries and misses met while serving one request or job. Fork::Fx records
# them and the fork/banners partial reads them (design §4.6).
class Fork::RequestFx < ActiveSupport::CurrentAttributes
  Carry = Data.define(:from, :to, :date, :observed_on, :carry_days)
  Miss = Data.define(:from, :to, :date)

  # Carries longer than this get a banner; shorter ones, which weekends and
  # long weekends produce, get only the amount marker.
  BANNER_CARRY_DAYS = 3

  attribute :carries, :misses

  def carries = (super || (self.carries = {}))
  def misses = (super || (self.misses = {}))

  def record_carry(from:, to:, date:, observed_on:, carry_days:)
    carries[[ from, to, date ]] = Carry.new(from: from, to: to, date: date, observed_on: observed_on, carry_days: carry_days)
  end

  def record_miss(from:, to:, date:)
    misses[[ from, to, date ]] = Miss.new(from: from, to: to, date: date)
  end

  def banner_carries
    carries.values.select { |c| c.carry_days > BANNER_CARRY_DAYS }
  end
end
