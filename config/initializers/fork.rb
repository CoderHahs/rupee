require Rails.root.join("lib/fork/boot_checks").to_s
require Rails.root.join("lib/fork/schedule").to_s

# Rupee's fork-level configuration. Runs after brand.rb and
# filter_parameter_logging.rb, because initializers load in name order.
Rails.application.configure do
  config.x.product_name = ENV.fetch("PRODUCT_NAME", "Rupee")

  # Where the running version's source is published (AGPLv3 section 13).
  config.x.source_url = ENV.fetch("FORK_SOURCE_URL", "https://github.com/CoderHahs/rupee")

  # English strings where upstream names the app "Sure". Later load-path
  # entries win, so this must stay outside config/locales.
  config.i18n.load_path += Dir[Rails.root.join("config/fork/locales/*.yml")]

  # Plaid Hosted Link URLs open a live Link session for whoever holds them.
  config.filter_parameters += [ :hosted_link_url ]

  if Rails.env.production?
    Fork::BootChecks.verify!

    config.hosts.concat(Fork::BootChecks.allowed_hosts)
    # Container health checks call /up by IP, with no matching Host header.
    config.host_authorization = { exclude: ->(request) { request.path == "/up" } }
  end
end

# Fork extensions to upstream classes (design §4.1). to_prepare reruns them
# after each code reload in development.
Rails.application.config.to_prepare do
  Family.include(Fork::FamilyExtension)
  Account.include(Fork::AccountExtension)

  # The Item budget and connection health (design §4.2, §4.3).
  PlaidItem.include(Fork::PlaidItemExtension)
  PlaidItem::WebhookProcessor.prepend(Fork::PlaidWebhookExtension)
  PlaidAccount::Processor.prepend(Fork::RevokedAccountGate)
  PlaidItemsController.prepend(Fork::PlaidItemsGate)
  Provider::Factory.singleton_class.prepend(Fork::ConnectionChooserOrder)

  # Exchange-rate lookups with observation dates and no fallback rate of 1 (design §4.6).
  ExchangeRate.singleton_class.prepend(Fork::ExchangeRateLookup)
  Transfer.include(Fork::TransferExtension)

  # The household AI switch (design §4.10).
  Family.prepend(Fork::FamilyAiGate)
  User.prepend(Fork::UserAiGate)
  McpController.prepend(Fork::McpAiGate)
  ImportsController.prepend(Fork::ImportsAiGate)

  # Liabilities and card bills (design §4.5).
  PlaidAccount::Processor.prepend(Fork::LiabilityProcessing)
  RecurringOccurrence.prepend(Fork::RecurringOccurrenceExtension)
  # Security prices (design §4.7).
  Security::Resolver.prepend(Fork::TsxProviderAssignment)
  Security::Price.include(Fork::PriceObservation)
  Security.prepend(Fork::CurrentPrice)
  Security.prepend(Fork::DetailsThrottle)
  Security::HealthChecker.prepend(Fork::HealthCheckPolicy)
end

# Load the fork's cron jobs when a Sidekiq server boots. See Fork::Schedule.
Sidekiq.configure_server do |config|
  config.on(:startup) do
    names = Fork::Schedule.load!
    Rails.logger.info("[Fork::Schedule] Loaded #{names.size} fork cron jobs")
  rescue => e
    Rails.logger.error("[Fork::Schedule] Failed to load #{Fork::Schedule::PATH}: #{e.message}")
  end
end
