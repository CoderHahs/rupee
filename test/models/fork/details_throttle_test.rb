require "test_helper"

class Fork::DetailsThrottleTest < ActiveSupport::TestCase
  include ProviderTestHelper

  setup do
    @old_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    @security = Security.create!(ticker: "DET#{SecureRandom.hex(3)}", price_provider: "alpha_vantage")
    @provider = mock
    Security.any_instance.stubs(:price_data_provider).returns(@provider)
  end

  teardown { Rails.cache = @old_cache }

  test "details are fetched at most once a week for a throttled provider" do
    @provider.expects(:fetch_security_info).once
      .returns(provider_error_response(StandardError.new("no details")))

    3.times { @security.import_provider_details }
  end

  test "details are fetched again after a week" do
    @provider.expects(:fetch_security_info).twice
      .returns(provider_error_response(StandardError.new("no details")))

    @security.import_provider_details
    travel 8.days do
      Rails.cache.cleanup
      @security.import_provider_details
    end
  end

  test "clear_cache and other providers are not throttled" do
    @provider.expects(:fetch_security_info).times(2)
      .returns(provider_error_response(StandardError.new("no details")))
    @security.import_provider_details(clear_cache: true)
    @security.import_provider_details(clear_cache: true)

    other = Security.create!(ticker: "OTH#{SecureRandom.hex(3)}", price_provider: "twelve_data")
    @provider.expects(:fetch_security_info).times(2)
      .returns(provider_error_response(StandardError.new("no details")))
    2.times { other.import_provider_details }
  end
end
