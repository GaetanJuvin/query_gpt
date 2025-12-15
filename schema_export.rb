#!/usr/bin/env ruby
require "optparse"
require "yaml"
require "fileutils"
require "erb"
require "pg"
require "active_record"

# Loads a connector based on config.yml and exports schema into fixtures.

require_relative "lib/query_gpt/connectors/postgres_activerecord"
require_relative "lib/query_gpt/workspace_store"
require_relative "lib/query_gpt/config"

config = QueryGPT::Config.load

options = {
  config_path: File.expand_path("config.yml", __dir__),
  profile: "upskill", # workspace profile key
  rails_env: "development"
}

schema_defaults = config.dig("default", "schema_export") || config["schema_export"] || {}
db_defaults = config["default_db"] || {}
profiles = config["workspaces"] || {}

OptionParser.new do |opts|
  opts.banner = "Usage: bundle exec ruby schema_export.rb [options]"
  opts.on("--config PATH", "Path to config.yml") { |v| options[:config_path] = File.expand_path(v) }
  opts.on("--profile NAME", "Workspace profile key from config.yml (default: upskill)") { |v| options[:profile] = v }
  opts.on("--rails-env NAME", "Rails environment (default: development)") { |v| options[:rails_env] = v }
  opts.on("-h", "--help", "Help") { puts opts; exit 0 }
end.parse!

profile = profiles[options[:profile]] || profiles[options[:profile].to_s]
raise "Profile #{options[:profile]} not found in config.yml workspaces" unless profile

db_config = db_defaults.merge(profile["database"] || {})
schema_export = schema_defaults.merge(profile["schema_export"] || {})

workspace_name = schema_export["workspace"] || profile["workspace"] || "Workspace"
description = schema_export["description"] || schema_defaults["description"] || "Exported from schema"
output_dir = File.expand_path(schema_export["output_dir"] || "lib/query_gpt/fixtures/generated", __dir__)
include_tables = schema_export["include_tables"] || []
exclude_tables = schema_export["exclude_tables"] || %w[schema_migrations ar_internal_metadata __diesel_schema_migrations]

# Establish standalone ActiveRecord connection using provided DB config (no Rails app_root needed)
erb_cfg = ERB.new(db_config.to_yaml).result
db_params = YAML.load(erb_cfg)
ActiveRecord::Base.establish_connection(db_params)

connector = QueryGPT::Connectors::PostgresActiveRecordConnector.new(
  connection: ActiveRecord::Base.connection,
  workspace: workspace_name,
  description: description,
  include_tables: include_tables,
  exclude_tables: exclude_tables
)

data = connector.fetch
QueryGPT::WorkspaceStore.write_fixtures(data, output_dir: output_dir)

puts "Wrote fixtures to #{output_dir}"
puts "- workspaces.yml (#{data[:workspaces].first[:table_ids].size} tables)"
puts "- schemas.yml"
puts "- sql_examples.yml (empty, add examples as needed)"
