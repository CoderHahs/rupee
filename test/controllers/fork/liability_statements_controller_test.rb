require "test_helper"

class Fork::LiabilityStatementsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:family_admin)
    @card = accounts(:credit_card)
  end

  test "index renders and shows not provided instead of zero" do
    Fork::LiabilityStatement.create!(account: @card, due_on: Date.current, currency: "USD", fields_missing: %w[statement_balance])

    get account_liability_statements_path(@card)

    assert_response :success
    assert_match I18n.t("fork.liability_statements.index.not_provided"), response.body
  end

  test "manual entry creates a statement and edit updates it" do
    assert_difference -> { Fork::LiabilityStatement.count }, 1 do
      post account_liability_statements_path(@card), params: { fork_liability_statement: {
        issued_on: "2026-09-20", due_on: "2026-10-15", statement_balance: "1200", minimum_due: "35",
        funding_account_id: accounts(:depository).id
      } }
    end
    assert_redirected_to account_liability_statements_path(@card)

    statement = Fork::LiabilityStatement.last
    assert statement.from_manual?
    assert statement.recurring_occurrence

    get edit_account_liability_statement_path(@card, statement)
    assert_response :success

    patch account_liability_statement_path(@card, statement), params: { fork_liability_statement: { minimum_due: "40" } }
    assert_redirected_to account_liability_statements_path(@card), response.body[0, 600]
    assert_equal 40, statement.reload.minimum_due
  end

  test "an invalid statement re-renders the form" do
    post account_liability_statements_path(@card), params: { fork_liability_statement: { statement_balance: "-5", due_on: "2026-10-15" } }
    assert_response :unprocessable_entity
  end

  test "other families' accounts are not found" do
    get account_liability_statements_path(accounts(:depository))
    assert_response :not_found
  end
end
