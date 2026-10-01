# frozen_string_literal: true

require "test_helper"

class Fork::IdentityTest < ActiveSupport::TestCase
  test "authenticator apps label the account with the product name" do
    user = users(:family_admin)
    user.setup_mfa!

    assert_includes CGI.unescape(user.provisioning_uri), "issuer=#{Rails.configuration.x.product_name}"
    refute_includes user.provisioning_uri, "Sure"
  end

  test "passkey prompts show the product name" do
    host = Class.new { include WebauthnRelyingParty; public :webauthn_relying_party }.new

    assert_equal Rails.configuration.x.product_name, host.webauthn_relying_party.name
  end
end
