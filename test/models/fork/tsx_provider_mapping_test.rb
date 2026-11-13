require "test_helper"

# R5.4: TSX Venture (XTSX) maps to .TRV and V, with CAD (design §4.7, D20).
class Fork::TsxProviderMappingTest < ActiveSupport::TestCase
  setup do
    Rails.cache.clear
  end

  test "Alpha Vantage sends .TRV for XTSX and reads it back" do
    av = Provider::AlphaVantage.new("key")

    assert_equal "GPV.TRV", av.send(:to_av_symbol, "GPV", "XTSX")
    assert_equal "XTSX", av.send(:extract_mic_from_symbol, "GPV.TRV")
    assert_equal "GPV", av.send(:strip_av_suffix, "GPV.TRV")
    assert_equal "CAD", av.send(:infer_currency_from_symbol, "GPV.TRV")
  end

  test "Alpha Vantage keeps XTSE on .TRT" do
    av = Provider::AlphaVantage.new("key")

    assert_equal "SHOP.TRT", av.send(:to_av_symbol, "SHOP", "XTSE")
    assert_equal "XTSE", av.send(:extract_mic_from_symbol, "SHOP.TRT")
  end

  test "EODHD sends V for XTSX and prices it in CAD" do
    eodhd = Provider::Eodhd.new("key")

    assert_equal "GPV.V", eodhd.send(:eodhd_symbol, "GPV", "XTSX")
    assert_equal "CAD", eodhd.send(:currency_for, exchange_operating_mic: "XTSX", symbol: "GPV")
    assert_equal "XTSX", Provider::Eodhd::EODHD_EXCHANGE_TO_MIC["V"]
  end
end
