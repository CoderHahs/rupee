# Rupee's routes, drawn from config/routes.rb with `draw :fork`. Fork
# controllers live in app/controllers/fork/, and fork API controllers in
# app/controllers/api/ext/v1/.

scope :settings, as: :settings do
  resource :household, only: %i[show update], controller: "fork/household_settings"
end
