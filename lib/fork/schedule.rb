# frozen_string_literal: true

require "yaml"

# Loads Rupee's cron jobs from config/fork_schedule.yml into sidekiq-cron.
#
# Upstream's loader (sidekiq-cron reading config/schedule.yml) removes only
# jobs whose source is "schedule", so the fork's jobs, saved as "dynamic",
# survive it. In return this loader touches only jobs named `fork:*`: it
# creates or updates each listed job and removes any other `fork:*` job.
module Fork
  module Schedule
    class Error < StandardError; end

    PREFIX = "fork:"
    PATH = "config/fork_schedule.yml"

    module_function

    # Returns the job names that were loaded.
    def load!(path = Rails.root.join(PATH), jobs: Sidekiq::Cron::Job)
      entries = read(path)

      entries.each do |name, attributes|
        job = jobs.new(attributes.merge("name" => name))
        raise Error, "#{name}: #{job.errors.join(', ')}" unless job.save
      end

      jobs.all.each do |job|
        job.destroy if job.name.to_s.start_with?(PREFIX) && !entries.key?(job.name)
      end

      entries.keys
    end

    def read(path)
      entries = YAML.safe_load_file(path) || {}
      raise Error, "#{path} must be a mapping of job names to jobs" unless entries.is_a?(Hash)

      entries.each do |name, attributes|
        raise Error, "#{name} must start with #{PREFIX}" unless name.to_s.start_with?(PREFIX)
        raise Error, "#{name} must be a mapping" unless attributes.is_a?(Hash)
        raise Error, "#{name} must not set a source" if attributes.key?("source")
      end

      entries
    end
  end
end
