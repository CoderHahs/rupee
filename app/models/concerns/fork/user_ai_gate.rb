# Prepended to User (design §4.10). ai_enabled? reads this, so with the
# household switch off chat, the API chat endpoints and insight narration are
# off for every member, and for guests unless an admin allows them.
module Fork::UserAiGate
  def ai_available?
    return false unless family&.ai_allowed_for?(self)

    super
  end
end
