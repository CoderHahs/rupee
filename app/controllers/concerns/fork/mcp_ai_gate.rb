# Prepended to McpController (design §4.10). MCP hands the family's data to
# an outside AI client, so the household switch covers it. The code is in
# JSON-RPC's server-error range; -32001 is avoided because the MCP
# TypeScript SDK reads it as a request timeout.
module Fork::McpAiGate
  AI_OFF = -32010

  private
    def dispatch_jsonrpc(request_id, method, params)
      return super if mcp_user&.family&.ai_allowed_for?(mcp_user)

      render_jsonrpc_error(request_id, AI_OFF, I18n.t("fork.mcp.ai_off"))
      nil
    end
end
