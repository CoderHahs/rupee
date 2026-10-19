require "test_helper"

class Provider::PlaidForkTest < ActiveSupport::TestCase
  setup do
    with_env_overrides("PLAID_CLIENT_ID" => "foo", "PLAID_SECRET" => "bar") do
      Provider::PlaidAdapter.reload_configuration
    end
    @plaid = Provider::PlaidSandbox.new
  end

  teardown do
    Provider::PlaidAdapter.reload_configuration
  end

  test "Link shows the product name" do
    request = mock
    Plaid::LinkTokenCreateRequest.expects(:new).with { |params| params[:client_name] == Rails.configuration.x.product_name }.returns(request)
    @plaid.client.expects(:link_token_create).with(request).returns("response")

    @plaid.get_link_token(user_id: "test-user-id", webhooks_url: "https://example.com/webhooks", redirect_url: "http://localhost:3000/accounts")
  end
end
