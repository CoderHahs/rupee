require Rails.root.join("lib/fork/boot_checks").to_s

# Rupee's fork-level configuration. Runs after brand.rb and
# filter_parameter_logging.rb, because initializers load in name order.
Rails.application.configure do
  config.x.product_name = ENV.fetch("PRODUCT_NAME", "Rupee")

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
