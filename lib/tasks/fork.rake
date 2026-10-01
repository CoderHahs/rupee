namespace :fork do
  desc "Regenerate config/fork/locales/en.yml, the English strings renamed from Sure to Rupee"
  task :locales do
    require Rails.root.join("lib/fork/branding").to_s

    path = Rails.root.join(Fork::Branding::OVERRIDES_PATH)
    FileUtils.mkdir_p(path.dirname)
    path.write(Fork::Branding.render(Rails.root.to_s, "Rupee"))
    puts "Wrote #{Fork::Branding.renamed_strings(Rails.root.to_s, 'Rupee').size} strings to #{Fork::Branding::OVERRIDES_PATH}"
  end
end
