# frozen_string_literal: true

require "test_helper"
require "open3"

# Runs bin/check-fork-surface in a scratch git repository with a small
# upstream history, and checks that each defect class fails it (design §5.1).
# The schema rule needs a database and runs in .github/workflows/fork.yml.
class Fork::CheckForkSurfaceScriptTest < ActiveSupport::TestCase
  setup do
    @dir = Dir.mktmpdir("fork-surface")
    build_repo
  end

  teardown { FileUtils.remove_entry(@dir) }

  test "a fork that keeps to its surface passes" do
    output, status = check

    assert status.success?, output
    assert_match "Fork surface OK: 1 upstream files edited", output
  end

  test "an upstream edit missing from the list fails" do
    append "app/models/family.rb", "# fork change\n"

    assert_fails "app/models/family.rb is an upstream file the fork edits, but config/fork/upstream_edits.yml does not list it"
  end

  test "a listed file the fork no longer edits fails" do
    git "checkout", "base", "--", "app/models/user.rb"

    assert_fails "app/models/user.rb is listed in config/fork/upstream_edits.yml, but the fork no longer edits it"
  end

  test "a file upstream has also added fails" do
    write "app/models/security/split.rb", "class Security::Split; end\n"

    assert_fails "Upstream has added app/models/security/split.rb, which the fork also adds"
  end

  test "a fork migration without the fork prefix fails" do
    write "db/migrate/20261020000000_create_card_instances.rb", "create_table :card_instances do |t|\nend\n"

    assert_fails "db/migrate/20261020000000_create_card_instances.rb is a fork migration, so its name must be <timestamp>_fork_<name>.rb"
  end

  test "a table both sides create fails" do
    write "db/migrate/20261020000000_fork_create_transfer_fx_details.rb", "create_table :transfer_fx_details do |t|\nend\n"

    assert_fails "Upstream and the fork both create the table transfer_fx_details"
  end

  test "a column both sides add to an upstream table fails" do
    write "db/migrate/20261020000000_fork_add_source_to_exchange_rates.rb", "add_column :exchange_rates, :source, :string\n"

    assert_fails "Upstream and the fork both add the column exchange_rates.source"
  end

  test "an LLM lookup that skips the household switch fails" do
    write "app/models/new_feature.rb", "class NewFeature\n  def provider = Provider::Registry.preferred_llm_provider\nend\n"

    assert_fails "app/models/new_feature.rb:2 looks up the LLM provider directly"
  end

  test "a base that is not the merge base with upstream fails" do
    upstream = git("rev-parse", "upstream").strip
    write "config/fork/upstream_edits.yml", { "base" => upstream, "upstream_edits" => [ "app/models/user.rb" ] }.to_yaml

    assert_fails "but config/fork/upstream_edits.yml says #{upstream}"
  end

  private
    # base: upstream's history up to the fork point. upstream: what upstream
    # has added since. main: the fork, with the check and one listed edit.
    def build_repo
      git "init", "-q", "-b", "main"
      write "app/models/user.rb", "class User; end\n"
      write "app/models/family.rb", "class Family; end\n"
      write "db/migrate/20260101000000_create_exchange_rates.rb", "create_table :exchange_rates do |t|\nend\n"
      commit "Upstream base"
      git "tag", "base"

      git "checkout", "-q", "-b", "upstream"
      write "app/models/security/split.rb", "class Security::Split; end\n"
      write "db/migrate/20260201000000_add_source_to_exchange_rates.rb", "add_column :exchange_rates, :source, :string\n"
      write "db/migrate/20260201000001_create_transfer_fx_details.rb", "create_table \"transfer_fx_details\", id: :uuid do |t|\nend\n"
      commit "Upstream changes"

      git "checkout", "-q", "main"
      FileUtils.mkdir_p(File.join(@dir, "bin"))
      FileUtils.mkdir_p(File.join(@dir, "lib/fork"))
      FileUtils.cp(Rails.root.join("bin/check-fork-surface"), File.join(@dir, "bin"))
      FileUtils.cp(Rails.root.join("lib/fork/surface_check.rb"), File.join(@dir, "lib/fork"))
      write "config/fork/upstream_edits.yml", { "base" => git("rev-parse", "base").strip, "upstream_edits" => [ "app/models/user.rb" ] }.to_yaml
      append "app/models/user.rb", "# fork change\n"
      commit "Fork"
    end

    def check
      Bundler.with_unbundled_env do
        Open3.capture2e(RbConfig.ruby, "bin/check-fork-surface", "--upstream", "upstream", chdir: @dir)
      end
    end

    def assert_fails(message)
      output, status = check

      assert_not status.success?, output
      assert_includes output, message
    end

    def git(*args)
      output, status = Open3.capture2e("git", "-c", "user.name=Test", "-c", "user.email=test@example.com", *args, chdir: @dir)
      raise "git #{args.join(' ')} failed: #{output}" unless status.success?

      output
    end

    def commit(message)
      git "add", "-A"
      git "commit", "-q", "-m", message
    end

    def write(path, content)
      full = File.join(@dir, path)
      FileUtils.mkdir_p(File.dirname(full))
      File.write(full, content)
    end

    def append(path, content)
      File.write(File.join(@dir, path), content, mode: "a")
    end
end
