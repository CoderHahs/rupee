require "test_helper"

class Fork::PlaidWebhooksTest < ActionDispatch::IntegrationTest
  setup do
    @item = plaid_items(:one)
    @body = { webhook_type: "ITEM", webhook_code: "USER_PERMISSION_REVOKED", item_id: @item.plaid_id }.to_json
  end

  test "a bad signature is rejected and nothing is recorded" do
    provider = mock
    provider.stubs(:validate_webhook!).raises(JWT::DecodeError.new("bad signature"))
    Provider::Registry.stubs(:plaid_provider_for_region).with(:us).returns(provider)

    post webhooks_plaid_url, params: @body, headers: { "CONTENT_TYPE" => "application/json", "Plaid-Verification" => "bad" }

    assert_response :bad_request
    assert_nil @item.reload.revoked_at
  end

  test "a verified revocation is recorded and answered with 200" do
    provider = mock
    provider.stubs(:validate_webhook!)
    Provider::Registry.stubs(:plaid_provider_for_region).with(:us).returns(provider)

    post webhooks_plaid_url, params: @body, headers: { "CONTENT_TYPE" => "application/json", "Plaid-Verification" => "ok" }

    assert_response :ok
    assert_not_nil @item.reload.revoked_at
  end
end
