# frozen_string_literal: true

require "test_helper"

class Fork::BootChecksTest < ActiveSupport::TestCase
  def healthy_env
    {
      "ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY" => "primary",
      "ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY" => "deterministic",
      "ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT" => "salt",
      "SECRET_KEY_BASE" => "a" * 128,
      "APP_DOMAIN" => "rupee.example.test"
    }
  end

  test "a fully configured environment passes" do
    assert_empty Fork::BootChecks.problems(healthy_env)
    assert_nothing_raised { Fork::BootChecks.verify!(healthy_env) }
  end

  test "missing encryption keys refuse to boot and name every missing key" do
    env = healthy_env.except("ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY", "ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT")

    error = assert_raises(Fork::BootChecks::Error) { Fork::BootChecks.verify!(env) }
    assert_includes error.message, "ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"
    assert_includes error.message, "ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"
    refute_includes error.message, "ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY"
  end

  test "blank encryption keys count as missing" do
    env = healthy_env.merge("ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY" => "  ")

    assert_equal 1, Fork::BootChecks.problems(env).size
  end

  test "an unset secret key base refuses to boot" do
    problems = Fork::BootChecks.problems(healthy_env.except("SECRET_KEY_BASE"))

    assert_equal [ "SECRET_KEY_BASE is not set." ], problems
  end

  test "each published example secret key base refuses to boot" do
    Fork::BootChecks::PUBLISHED_SECRET_KEY_BASES.each do |published|
      problems = Fork::BootChecks.problems(healthy_env.merge("SECRET_KEY_BASE" => published))

      assert_equal 1, problems.size, "expected #{published[0, 8]}... to be refused"
      assert_match(/published example value/, problems.first)
    end
  end

  test "the compose example secret key base is in the published list" do
    compose = Rails.root.join("compose.example.yml").read
    published = compose[/SECRET_KEY_BASE: \$\{SECRET_KEY_BASE:-([0-9a-f]+)\}/, 1]

    assert published, "compose.example.yml no longer sets a default SECRET_KEY_BASE"
    assert_includes Fork::BootChecks::PUBLISHED_SECRET_KEY_BASES, published
  end

  test "a missing app domain refuses to boot" do
    problems = Fork::BootChecks.problems(healthy_env.merge("APP_DOMAIN" => ""))

    assert_equal 1, problems.size
    assert_match(/APP_DOMAIN/, problems.first)
  end

  test "all problems are reported at once" do
    assert_equal 3, Fork::BootChecks.problems({}).size
  end

  test "asset precompilation skips the checks" do
    assert_nothing_raised { Fork::BootChecks.verify!("SECRET_KEY_BASE_DUMMY" => "1") }
  end

  test "allowed hosts are the app domain and the public tunnel host" do
    env = healthy_env.merge("FORK_PUBLIC_HOST" => " hooks.example.test ")

    assert_equal [ "rupee.example.test", "hooks.example.test" ], Fork::BootChecks.allowed_hosts(env)
    assert_equal [ "rupee.example.test" ], Fork::BootChecks.allowed_hosts(healthy_env)
  end
end
