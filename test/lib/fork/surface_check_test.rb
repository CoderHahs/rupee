# frozen_string_literal: true

require "test_helper"
require Rails.root.join("lib/fork/surface_check").to_s

class Fork::SurfaceCheckTest < ActiveSupport::TestCase
  Check = Fork::SurfaceCheck

  test "an edited upstream file must be listed" do
    edited = [ "app/models/user.rb", "app/models/family.rb" ]

    assert_equal [ "app/models/family.rb" ], Check.unlisted_edits(edited, [ "app/models/user.rb" ])
  end

  test "db/schema.rb is checked by regenerating it, not by the list" do
    assert_empty Check.unlisted_edits([ "db/schema.rb" ], [])
  end

  test "a listed file the fork no longer edits is stale" do
    assert_equal [ "app/models/user.rb" ], Check.stale_entries([], [ "app/models/user.rb" ])
  end

  test "upstream adding a file the fork added is a collision" do
    fork_added = [ "app/models/fork/fx.rb", "app/models/provider/bank_of_canada.rb" ]
    upstream_added = [ "app/models/provider/bank_of_canada.rb", "app/models/security/split.rb" ]

    assert_equal [ "app/models/provider/bank_of_canada.rb" ], Check.file_collisions(fork_added, upstream_added)
  end

  test "fork migrations must be named with the fork prefix" do
    added = [
      "db/migrate/20261020100000_fork_create_household_settings.rb",
      "db/migrate/20261020100001_create_card_instances.rb",
      "lib/fork/fx.rb"
    ]

    assert_equal [ "db/migrate/20261020100001_create_card_instances.rb" ], Check.misnamed_migrations(added)
  end

  test "reads tables and columns from the common migration forms" do
    changes = Check.parse_migration(<<~RUBY)
      class ForkExample < ActiveRecord::Migration[8.1]
        def change
          create_table :household_settings, id: :uuid do |t|
            t.references :family, type: :uuid
            t.boolean :ai_enabled
          end

          add_column :exchange_rates, :observed_on, :date
          add_reference :entries, :card_instance, type: :uuid

          change_table :plaid_items do |t|
            t.string :health_status
            t.references :reconnected_by
            t.index :health_status
            t.remove :legacy_flag
          end
        end
      end
    RUBY

    assert_equal Set["household_settings"], changes.tables
    expected = [
      "exchange_rates.observed_on",
      "entries.card_instance_id",
      "plaid_items.health_status",
      "plaid_items.reconnected_by_id"
    ]
    assert_equal expected.to_set, changes.columns
  end

  test "a column both sides add to an upstream table is a collision" do
    fork = Check.migration_changes([ "add_column :exchange_rates, :observed_on, :date\nadd_column :exchange_rates, :source, :string" ])
    upstream = Check.migration_changes([ "add_column \"exchange_rates\", \"source\", :string" ])

    assert_equal Set["exchange_rates.source"], Check.column_collisions(fork, upstream)
  end

  test "columns on a table the fork creates are not collisions" do
    fork = Check.migration_changes([ "create_table :liability_statements do |t|\n  t.date :due_on\nend\nadd_column :liability_statements, :source, :string" ])
    upstream = Check.migration_changes([ "add_column :liability_statements, :source, :string" ])

    assert_empty Check.column_collisions(fork, upstream)
  end

  test "both sides creating the same table is a collision" do
    fork = Check.migration_changes([ "create_table :transfer_fx_details do |t|\nend" ])
    upstream = Check.migration_changes([ "create_table \"transfer_fx_details\", id: :uuid do |t|\nend" ])

    assert_equal Set["transfer_fx_details"], Check.table_collisions(fork, upstream)
  end

  test "the committed list of upstream edits loads" do
    base, listed = Check.load_edits(Rails.root.join(Check::EDITS_PATH))

    assert_match(/\A\h{40}\z/, base)
    assert_includes listed, "config/routes.rb"
    assert_equal listed.uniq, listed
  end
end
