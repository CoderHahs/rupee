# Settings > Household > Rupee: where an admin turns the household AI switch
# on with recorded consent, or off again (design §4.10, §4.12).
class Fork::HouseholdAisController < ApplicationController
  layout "settings"

  before_action :require_admin!
  before_action :set_household_settings

  def show
    @choice = Fork::AiProviderChoice.new
  end

  # Consent names the provider and who agreed, so turning Rupee on always
  # records both.
  def update
    @choice = Fork::AiProviderChoice.new
    consent = params.dig(:household_ai, :consent) == "1"
    provider = params.dig(:household_ai, :provider).to_s

    unless consent
      flash.now[:alert] = t(".consent_required")
      return render :show, status: :unprocessable_entity
    end

    unless @choice.available?(provider)
      flash.now[:alert] = t(".provider_unavailable")
      return render :show, status: :unprocessable_entity
    end

    Fork::HouseholdSetting.transaction do
      @choice.choose!(provider)
      @household_settings.update!(
        ai_enabled: true,
        ai_consented_at: Time.current,
        ai_consented_by: Current.user,
        ai_for_guests: params.dig(:household_ai, :ai_for_guests) == "1"
      )
    end

    redirect_to settings_household_ai_path, notice: t(".turned_on")
  end

  # Turning Rupee off keeps the record of the last consent.
  def destroy
    @household_settings.update!(ai_enabled: false)
    redirect_to settings_household_ai_path, notice: t(".turned_off")
  end

  private
    def set_household_settings
      @household_settings = Current.family.household_settings
    end
end
