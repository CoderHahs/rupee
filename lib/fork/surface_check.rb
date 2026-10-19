# frozen_string_literal: true

require "set"
require "yaml"

# The rules behind bin/check-fork-surface, kept free of git and the database
# so each defect class can be tested on its own (design §4.1, §5.1).
#
# The fork stays mergeable by adding files rather than editing upstream ones.
# The check fails when:
#   - an upstream file is edited but not listed in config/fork/upstream_edits.yml,
#     or a listed file is no longer edited;
#   - upstream has added a file at the path of a file the fork added;
#   - a fork migration is not named `<timestamp>_fork_<name>.rb`;
#   - upstream and the fork create the same table, or add the same column to
#     an upstream table;
#   - db/schema.rb differs from upstream's schema plus the fork's migrations
#     (checked by the script, which needs a database);
#   - code in app/ looks up the LLM provider without going through the
#     household AI switch (design §4.10).
module Fork
  module SurfaceCheck
    EDITS_PATH = "config/fork/upstream_edits.yml"

    # Generated from migrations and checked by regenerating it instead.
    GENERATED = [ "db/schema.rb" ].freeze

    FORK_MIGRATION = %r{\Adb/migrate/\d+_fork_\w+\.rb\z}

    # change_table methods that take a column name but add nothing.
    NON_ADDING = %w[remove remove_references remove_belongs_to index remove_index rename change change_default change_null].freeze

    # Lookups that reach an LLM provider directly instead of through
    # Family#permitted_llm_provider.
    LLM_LOOKUP = /\b(?:preferred_llm_provider|for_concept\(:llm\)|get_provider\(:openai\))/

    # Where a direct lookup is allowed, and why.
    LLM_LOOKUP_ALLOWED = [
      "app/models/provider/registry.rb",              # defines the lookup
      "app/models/concerns/fork/family_extension.rb", # permitted_llm_provider itself
      "app/models/family.rb",                         # wrapped by Fork::FamilyAiGate
      "app/models/assistant/provided.rb",             # chat, off through User#ai_available?
      "app/models/ai_health.rb",                      # probes send only synthetic inputs
      "app/models/eval/"                              # the developers' evaluation harness
    ].freeze

    Changes = Struct.new(:tables, :columns) do
      def self.empty = new(Set.new, Set.new)

      def merge(other) = Changes.new(tables | other.tables, columns | other.columns)
    end

    module_function

    def load_edits(path)
      config = YAML.safe_load_file(path)
      [ config.fetch("base"), Array(config.fetch("upstream_edits")) ]
    end

    # Upstream files (present at the merge base) that the fork changed or
    # deleted but has not listed.
    def unlisted_edits(edited, listed)
      edited - listed - GENERATED
    end

    # Listed files the fork no longer edits, so the list stays accurate.
    def stale_entries(edited, listed)
      listed - edited
    end

    def file_collisions(fork_added, upstream_added)
      fork_added & upstream_added
    end

    def misnamed_migrations(fork_added)
      fork_added.select { |path| path.start_with?("db/migrate/") && !path.match?(FORK_MIGRATION) }
    end

    def fork_migration?(path)
      path.match?(FORK_MIGRATION)
    end

    # Tables created and "table.column" pairs added by migration sources.
    # It reads the common forms (create_table, add_column, add_reference and
    # the column methods inside change_table) and is not a Ruby parser.
    def migration_changes(sources)
      sources.reduce(Changes.empty) { |changes, source| changes.merge(parse_migration(source)) }
    end

    def parse_migration(source)
      tables = Set.new
      columns = Set.new
      changing = nil

      source.each_line do |line|
        if (match = line.match(/\bcreate_table\s*\(?\s*[:"'](\w+)/))
          tables << match[1]
          changing = nil
        elsif (match = line.match(/\bchange_table\s*\(?\s*[:"'](\w+)/))
          changing = match[1]
        elsif (match = line.match(/\badd_column\s*\(?\s*[:"'](\w+)["']?\s*,\s*[:"'](\w+)/))
          columns << "#{match[1]}.#{match[2]}"
        elsif (match = line.match(/\badd_(?:reference|belongs_to)\s*\(?\s*[:"'](\w+)["']?\s*,\s*[:"'](\w+)/))
          columns << "#{match[1]}.#{match[2]}_id"
        elsif changing && (match = line.match(/\A\s*t\.(\w+)\s+[:"'](\w+)/))
          next if NON_ADDING.include?(match[1])

          column = %w[references belongs_to].include?(match[1]) ? "#{match[2]}_id" : match[2]
          columns << "#{changing}.#{column}"
        end
      end

      Changes.new(tables, columns)
    end

    # LLM lookups outside the allowed files, as "path:line". Takes
    # [path, line, text] matches; comments are not lookups.
    def ungated_llm_lookups(matches)
      matches.filter_map do |path, line, text|
        next if text.lstrip.start_with?("#") || !text.match?(LLM_LOOKUP)
        next if LLM_LOOKUP_ALLOWED.any? { |allowed| allowed.end_with?("/") ? path.start_with?(allowed) : path == allowed }

        "#{path}:#{line}"
      end
    end

    def table_collisions(fork_changes, upstream_changes)
      fork_changes.tables & upstream_changes.tables
    end

    # Columns both sides add to the same upstream table. Columns on tables
    # the fork creates cannot collide, because the table is the fork's.
    def column_collisions(fork_changes, upstream_changes)
      fork_on_upstream = fork_changes.columns.reject { |pair| fork_changes.tables.include?(pair.split(".").first) }
      fork_on_upstream.to_set & upstream_changes.columns
    end
  end
end
