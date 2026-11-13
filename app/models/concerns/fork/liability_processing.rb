# Prepended to PlaidAccount::Processor in fork.rb. After the Liabilities
# processors run, records the statement and links its bill (design §4.5).
# A failure here never stops the sync, as with the processors themselves.
module Fork::LiabilityProcessing
  private
    def process_liabilities
      super
      Fork::Liabilities::Recorder.record_plaid(plaid_account)
    rescue => e
      report_exception(e)
    end
end
