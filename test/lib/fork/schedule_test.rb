# frozen_string_literal: true

require "test_helper"

class Fork::ScheduleTest < ActiveSupport::TestCase
  # Stands in for Sidekiq::Cron::Job, keeping saved jobs in memory.
  class FakeJobs
    Job = Struct.new(:store, :attributes) do
      def name = attributes["name"]
      def errors = attributes["cron"].present? ? [] : [ "'cron' must be set" ]

      def save
        return false if errors.any?

        store[name] = attributes
        true
      end

      def destroy = store.delete(name)
    end

    attr_reader :store

    def initialize(names = [])
      @store = names.index_with { |name| { "name" => name } }
    end

    def new(attributes) = Job.new(store, attributes)
    def all = store.values.map { |attributes| Job.new(store, attributes) }
  end

  setup do
    @dir = Dir.mktmpdir
    @path = File.join(@dir, "fork_schedule.yml")
  end

  teardown { FileUtils.remove_entry(@dir) }

  test "creates each listed job" do
    write("fork:health_poll" => { "cron" => "15 6 * * *", "class" => "Fork::HealthPollJob", "queue" => "scheduled" })
    jobs = FakeJobs.new

    assert_equal [ "fork:health_poll" ], Fork::Schedule.load!(@path, jobs: jobs)
    assert_equal "15 6 * * *", jobs.store["fork:health_poll"]["cron"]
    assert_equal "Fork::HealthPollJob", jobs.store["fork:health_poll"]["class"]
  end

  test "removes fork jobs that are no longer listed and leaves upstream jobs alone" do
    write("fork:kept" => { "cron" => "0 * * * *", "class" => "Fork::KeptJob" })
    jobs = FakeJobs.new([ "fork:kept", "fork:dropped", "sync_all_accounts", "import_market_data" ])

    Fork::Schedule.load!(@path, jobs: jobs)

    assert_equal [ "fork:kept", "sync_all_accounts", "import_market_data" ].sort, jobs.store.keys.sort
  end

  test "an empty schedule removes every fork job" do
    write({})
    jobs = FakeJobs.new([ "fork:dropped", "sync_all_accounts" ])

    assert_equal [], Fork::Schedule.load!(@path, jobs: jobs)
    assert_equal [ "sync_all_accounts" ], jobs.store.keys
  end

  test "refuses a job without the fork prefix" do
    write("health_poll" => { "cron" => "15 6 * * *", "class" => "Fork::HealthPollJob" })

    error = assert_raises(Fork::Schedule::Error) { Fork::Schedule.load!(@path, jobs: FakeJobs.new) }
    assert_match "must start with fork:", error.message
  end

  test "refuses a job that sets its own source" do
    write("fork:health_poll" => { "cron" => "15 6 * * *", "class" => "Fork::HealthPollJob", "source" => "schedule" })

    assert_raises(Fork::Schedule::Error) { Fork::Schedule.load!(@path, jobs: FakeJobs.new) }
  end

  test "raises when sidekiq-cron rejects a job" do
    write("fork:health_poll" => { "class" => "Fork::HealthPollJob" })

    error = assert_raises(Fork::Schedule::Error) { Fork::Schedule.load!(@path, jobs: FakeJobs.new) }
    assert_match "'cron' must be set", error.message
  end

  test "the committed schedule is valid and names existing job classes" do
    entries = Fork::Schedule.read(Rails.root.join(Fork::Schedule::PATH))
    assert_kind_of Hash, entries

    entries.each do |name, attributes|
      job = Sidekiq::Cron::Job.new(attributes.merge("name" => name, "fetch_missing_args" => false))
      assert job.valid?, "#{name}: #{job.errors.join(', ')}"
      assert attributes["class"].safe_constantize, "#{name}: #{attributes['class']} does not exist"
    end
  end

  private
    def write(entries)
      File.write(@path, entries.to_yaml)
    end
end
