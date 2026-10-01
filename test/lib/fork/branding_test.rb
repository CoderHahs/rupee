# frozen_string_literal: true

require "test_helper"
require Rails.root.join("lib/fork/branding").to_s

class Fork::BrandingTest < ActiveSupport::TestCase
  test "the committed overrides match upstream's current English strings" do
    expected = Fork::Branding.render(Rails.root.to_s, "Rupee")
    actual = Rails.root.join(Fork::Branding::OVERRIDES_PATH).read

    assert_equal expected, actual, "Upstream English strings changed. Run bin/rails fork:locales and commit the result."
  end

  test "no English string the app resolves names Sure, apart from the kept keys" do
    upstream = Fork::Branding.upstream_strings(Rails.root.to_s)
    assert_operator upstream.size, :>, 50, "the scan found too few strings to be reading the locale files"

    leaks = (upstream.keys - Fork::Branding::KEEP_KEYS).select do |key|
      I18n.t(key.delete_prefix("en."), locale: :en).to_s.match?(Fork::Branding::UPSTREAM_NAME)
    end

    assert_empty leaks
  end

  test "kept keys still name Sure, so the keep list holds no stale entries" do
    Fork::Branding::KEEP_KEYS.each do |key|
      assert_match Fork::Branding::UPSTREAM_NAME, I18n.t(key.delete_prefix("en."), locale: :en), key
    end
  end

  test "lowercase sure is left alone" do
    assert_equal "Make sure Rupee works", "Make sure Sure works".gsub(Fork::Branding::UPSTREAM_NAME, "Rupee")
  end
end
