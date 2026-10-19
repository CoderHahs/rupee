require "test_helper"

# The household AI switch at the MCP endpoint and the imports page
# (design §4.10).
class Fork::AiSwitchGatesTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:family_admin)
    @admin.family.household_settings.update!(ai_enabled: false)
  end

  test "MCP answers every method with -32010 while the switch is off" do
    token = "test-mcp-token-#{SecureRandom.hex(8)}"

    with_env_overrides("MCP_API_TOKEN" => token, "MCP_USER_EMAIL" => @admin.email) do # pipelock:ignore
      %w[initialize tools/list tools/call].each do |method|
        post "/mcp", params: { jsonrpc: "2.0", id: 1, method: method, params: {} }.to_json,
             headers: { "Content-Type" => "application/json", "Authorization" => "Bearer #{token}" }

        assert_response :ok
        error = JSON.parse(response.body)["error"]
        assert_equal Fork::McpAiGate::AI_OFF, error["code"], method
        assert_equal I18n.t("fork.mcp.ai_off"), error["message"]
      end
    end
  end

  test "MCP works again once the switch is on" do
    @admin.family.household_settings.update!(ai_enabled: true)
    token = "test-mcp-token-#{SecureRandom.hex(8)}"

    with_env_overrides("MCP_API_TOKEN" => token, "MCP_USER_EMAIL" => @admin.email) do # pipelock:ignore
      post "/mcp", params: { jsonrpc: "2.0", id: 1, method: "initialize", params: {} }.to_json,
           headers: { "Content-Type" => "application/json", "Authorization" => "Bearer #{token}" }
    end

    assert_response :ok
    assert JSON.parse(response.body)["result"].present?
  end

  test "PDF imports are refused while the switch is off" do
    sign_in @admin

    assert_no_difference [ "Import.count", "AccountStatement.count" ] do
      post imports_url, params: {
        import: { import_file: file_fixture_upload("imports/sample_bank_statement.pdf", "application/pdf") }
      }
    end

    assert_redirected_to new_import_url
    assert_equal I18n.t("fork.imports.ai_off"), flash[:alert]
  end

  test "document imports are refused while the switch is off" do
    sign_in @admin
    Family.any_instance.expects(:upload_document).never

    post imports_url, params: {
      import: { type: "DocumentImport", import_file: file_fixture_upload("imports/valid.csv", "text/csv") }
    }

    assert_redirected_to new_import_url
    assert_equal I18n.t("fork.imports.ai_off"), flash[:alert]
  end
end
