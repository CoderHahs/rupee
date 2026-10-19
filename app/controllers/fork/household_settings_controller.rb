# Settings > Household: Rupee's per-family settings (design §4.10).
class Fork::HouseholdSettingsController < ApplicationController
  layout "settings"

  before_action :require_admin!
  before_action :set_household_settings

  def show
  end

  # Confirms the family's time zone (R18.10). Period ends, reminder times and
  # bill states depend on it, so an admin must confirm it once.
  def update
    timezone = params.dig(:household, :timezone).presence

    if timezone.nil?
      flash.now[:alert] = t(".timezone_required")
      return render :show, status: :unprocessable_entity
    end

    Current.family.transaction do
      Current.family.update!(timezone: timezone)
      @household_settings.update!(timezone_confirmed_at: Time.current)
    end

    redirect_to settings_household_path, notice: t(".timezone_confirmed")
  rescue ActiveRecord::RecordInvalid
    flash.now[:alert] = t(".timezone_invalid")
    render :show, status: :unprocessable_entity
  end

  private
    def set_household_settings
      @household_settings = Current.family.household_settings
    end
end
