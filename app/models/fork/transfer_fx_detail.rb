# What a cross-currency transfer exchanged, against the reference rate on the
# day (design §4.6, §5.2, R4.9). The spread is in basis points, negative when
# the household got less than the reference rate.
class Fork::TransferFxDetail < ApplicationRecord
  self.table_name = "transfer_fx_details"

  belongs_to :transfer

  # @return [Fork::TransferFxDetail, nil] nil when the currencies match
  def self.build_for(transfer)
    outflow = transfer.outflow_transaction&.entry
    inflow = transfer.inflow_transaction&.entry
    return nil unless outflow && inflow && outflow.currency != inflow.currency

    outflow_amount = outflow.amount.abs
    inflow_amount = inflow.amount.abs
    return nil unless outflow_amount.positive? && inflow_amount.positive?

    implied = inflow_amount / outflow_amount
    detail = new(
      transfer: transfer,
      outflow_amount: outflow_amount, outflow_currency: outflow.currency,
      inflow_amount: inflow_amount, inflow_currency: inflow.currency,
      implied_rate: implied
    )

    quote = reference_quote(outflow.currency, inflow.currency, outflow.date)
    if quote
      detail.reference_rate = quote.rate
      detail.reference_source = quote.source
      detail.reference_observed_on = quote.observed_on
      detail.spread_bps = ((implied / quote.rate - 1) * 10_000).round(1)
    end
    detail
  end

  def self.reference_quote(from, to, date)
    Fork::Fx.lookup(from: from, to: to, date: date)
  rescue StandardError => e
    Rails.logger.warn("[Fork::TransferFxDetail] no reference rate for #{from}/#{to} on #{date}: #{e.message}")
    nil
  end

  # Negative spreads are below the reference rate.
  def below_reference? = spread_bps.to_d.negative?

  # The spread as a percentage, e.g. 0.39 for -38.7 bps.
  def spread_percent = (spread_bps.to_d.abs / 100).round(2)
end
