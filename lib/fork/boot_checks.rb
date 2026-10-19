# frozen_string_literal: true

require_relative "../active_record_encryption_config"

# Production preconditions that Rupee enforces and upstream Sure only warns about.
#
# Without explicit Active Record encryption keys, Sure derives keys from
# SECRET_KEY_BASE but `encryption_ready?` stays false, so every guarded
# `encrypts` is skipped and provider tokens are stored in plaintext.
module Fork
  module BootChecks
    class Error < StandardError; end

    # Published in compose.example.yml and .env.example, so every instance
    # started from either file would share them.
    PUBLISHED_SECRET_KEY_BASES = [
      "a7523c3d0ae56415046ad8abae168d71074a79534a7062258f8d1d51ac2f76d3c3bc86d86b6b0b307df30d9a6a90a2066a3fa9e67c5e6f374dbd7dd4e0778e13",
      "secret-value"
    ].freeze

    module_function

    def problems(env = ENV)
      found = []

      unless ActiveRecordEncryptionConfig.complete_env?(env)
        found << "Active Record encryption keys are missing: #{ActiveRecordEncryptionConfig.missing_env_keys(env).join(', ')}. " \
                 "Generate them with bin/rails db:encryption:init."
      end

      secret_key_base = env["SECRET_KEY_BASE"].to_s.strip
      if secret_key_base.empty?
        found << "SECRET_KEY_BASE is not set."
      elsif PUBLISHED_SECRET_KEY_BASES.include?(secret_key_base)
        found << "SECRET_KEY_BASE is the published example value. Generate one with bin/rails secret."
      end

      found << "APP_DOMAIN is not set, so host authorization has no allowed host." if env["APP_DOMAIN"].to_s.strip.empty?

      found
    end

    # assets:precompile boots production with SECRET_KEY_BASE_DUMMY and no real secrets.
    def skip?(env = ENV)
      !env["SECRET_KEY_BASE_DUMMY"].to_s.strip.empty?
    end

    def verify!(env = ENV)
      return if skip?(env)

      found = problems(env)
      return if found.empty?

      raise Error, "Refusing to boot in production:\n- #{found.join("\n- ")}"
    end

    # APP_DOMAIN plus the tunnel's public host for the webhook routes, when one is set.
    def allowed_hosts(env = ENV)
      [ env["APP_DOMAIN"], env["FORK_PUBLIC_HOST"] ].map { |host| host.to_s.strip }.reject(&:empty?).uniq
    end
  end
end
