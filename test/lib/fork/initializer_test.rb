# frozen_string_literal: true

require "test_helper"

class Fork::InitializerTest < ActiveSupport::TestCase
  test "the product is named Rupee when PRODUCT_NAME is unset" do
    skip "PRODUCT_NAME is set in this environment" if ENV["PRODUCT_NAME"].present?

    assert_equal "Rupee", Rails.configuration.x.product_name
  end

  test "hosted link urls are filtered from logs" do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    filtered = filter.filter("hosted_link_url" => "https://secure.plaid.com/hl/abc", "currency_code" => "USD")

    assert_equal "[FILTERED]", filtered["hosted_link_url"]
    assert_equal "USD", filtered["currency_code"]
  end

  test "both assistant prompts use the product name instead of Sure" do
    product = Rails.configuration.x.product_name
    static = Assistant::Configurable::STATIC_INSTRUCTIONS
    intro = Assistant.config_for(chats(:intro))[:instructions]

    [ static, intro ].each do |prompt|
      assert_includes prompt, "You are #{product},"
      refute_match(/\bSure\b/, prompt)
    end
  end
end
