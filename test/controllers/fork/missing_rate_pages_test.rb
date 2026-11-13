require "test_helper"

# A household with a EUR account and no EUR rates renders every page with no
# error, no rate of 1, a banner, and the amount left out of totals (design §8).
class Fork::MissingRatePagesTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
    @family = @user.family
    ExchangeRate.delete_all
    Rails.cache.clear
    ExchangeRate.stubs(:provider).returns(nil)
    @eur = @family.accounts.create!(name: "Euro savings", balance: 1000, currency: "EUR", accountable: Depository.new)
  end

  PAGES = %i[
    root_path accounts_path transactions_path budgets_path reports_path
    recurring_transactions_path imports_path categories_path
    merchants_path tags_path rules_path
  ].freeze

  test "every page renders and the banner names the missing pair" do
    PAGES.each do |name|
      next unless respond_to?(name)

      get public_send(name)
      assert_includes [ 200, 302 ], response.status, "#{name} returned #{response.status}"
    end

    get account_path(@eur)
    assert_response :ok

    get root_path
    assert_response :ok
    assert_match "EUR amounts on #{Date.current} are left out of totals", response.body
    assert_match I18n.t("fork.fx.not_converted"), response.body
  end

  test "the account's balance is left out of the family total instead of counting at a rate of 1" do
    balance_sheet = @family.balance_sheet

    assert_equal 0, balance_sheet.send(:account_totals).asset_accounts.find { |a| a.id == @eur.id }.converted_balance
  end

  test "a carried rate within 3 days shows the marker but no banner" do
    ExchangeRate.create!(from_currency: "EUR", to_currency: @family.currency, date: Date.current - 2, rate: 1.1, observed_on: Date.current - 2, source: "frankfurter")

    get root_path

    assert_response :ok
    assert_no_match "left out of totals", response.body
    assert_select "[data-fx-carry-days='2']"
  end
end
