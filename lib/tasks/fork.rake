namespace :fork do
  desc "Regenerate config/fork/locales/en.yml, the English strings renamed from Sure to Rupee"
  task :locales do
    require Rails.root.join("lib/fork/branding").to_s

    path = Rails.root.join(Fork::Branding::OVERRIDES_PATH)
    FileUtils.mkdir_p(path.dirname)
    path.write(Fork::Branding.render(Rails.root.to_s, "Rupee"))
    puts "Wrote #{Fork::Branding.renamed_strings(Rails.root.to_s, 'Rupee').size} strings to #{Fork::Branding::OVERRIDES_PATH}"
  end

  desc "Allocate card and loan payments to the open card bills (design 4.5)"
  task liability_payment_match: :environment do
    puts "Allocated #{Fork::Liabilities::PaymentMatcher.match_all} payments"
  end
end
