require "test_helper"

class Fork::SecurityCurrentPriceTest < ActiveSupport::TestCase
  setup do
    Rails.cache.clear
    @security = Security.create!(ticker: "CUR#{SecureRandom.hex(3)}", price_provider: "alpha_vantage")
  end

  test "today's stored row is used with no request" do
    Security::Price.create!(security: @security, date: Date.current, price: 12, currency: "CAD")
    @security.expects(:find_or_fetch_price).never

    quote = @security.current_price_quote

    assert_equal Money.new(12, "CAD"), @security.current_price
    assert_equal 0, quote.carry_days
    refute quote.stale?
  end

  test "falls back to the latest stored row, labelled with its observation date" do
    Security::Price.create!(security: @security, date: 20.days.ago.to_date, price: 9, currency: "CAD")
    Security::Price.create!(security: @security, date: 10.days.ago.to_date, price: 11, currency: "CAD")
    @security.stubs(:find_or_fetch_price).returns(nil)

    quote = @security.current_price_quote

    assert_equal Money.new(11, "CAD"), quote.money
    assert_equal 10.days.ago.to_date, quote.observed_on
    assert_equal 10, quote.carry_days
    assert quote.stale?
  end

  test "a security with no rows has no quote" do
    @security.stubs(:find_or_fetch_price).returns(nil)

    assert_nil @security.current_price_quote
    assert_nil @security.current_price
  end

  test "the provider is asked at most once an hour" do
    Security::Price.create!(security: @security, date: 4.days.ago.to_date, price: 9, currency: "CAD")
    with_memory_cache do
      @security.expects(:find_or_fetch_price).once.returns(nil)
      @security.current_price_quote

      again = Security.find(@security.id)
      again.expects(:find_or_fetch_price).never
      assert_equal Money.new(9, "CAD"), again.current_price
    end
  end

  test "price label renders the last price date for a long carry and no-price text" do
    Security::Price.create!(security: @security, date: 30.days.ago.to_date, price: 9, currency: "CAD")
    @security.stubs(:find_or_fetch_price).returns(nil)

    html = ApplicationController.render(partial: "fork/price_label", locals: { security: @security })
    assert_includes html, I18n.t("fork.price_label.last_price", date: I18n.l(30.days.ago.to_date, format: :long))

    empty = Security.create!(ticker: "EMP#{SecureRandom.hex(3)}")
    empty.stubs(:find_or_fetch_price).returns(nil)
    html = ApplicationController.render(partial: "fork/price_label", locals: { security: empty })
    assert_includes html, I18n.t("fork.price_label.none")
  end

  private
    def with_memory_cache
      old = Rails.cache
      Rails.cache = ActiveSupport::Cache::MemoryStore.new
      yield
    ensure
      Rails.cache = old
    end
end
