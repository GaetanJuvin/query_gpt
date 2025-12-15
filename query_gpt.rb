#!/usr/bin/env ruby
require "bundler/setup"
require "optparse"
require "json"
require "erb"
require_relative "lib/query_gpt/pipeline"
require_relative "lib/query_gpt/llm_client"
require_relative "lib/query_gpt/vector_store"
require_relative "lib/query_gpt/workspace_store"
require_relative "lib/query_gpt/intent_agent"
require_relative "lib/query_gpt/table_agent"
require_relative "lib/query_gpt/column_prune_agent"
require_relative "lib/query_gpt/prompt_enhancer"
require_relative "lib/query_gpt/sql_generator"
require_relative "lib/query_gpt/evaluator"
require_relative "lib/query_gpt/embeddings"
require_relative "lib/query_gpt/query_executor"
require_relative "lib/query_gpt/config"

config = QueryGPT::Config.load

options = {
  debug: false,
  dry_run: false,
  tables: [],
  workspace: nil,
  fixtures_path: nil,
  profile: nil
}

OptionParser.new do |opts|
  opts.banner = "Usage: bundle exec ruby query_gpt.rb [options] \"question text\""

  opts.on("--question QUESTION", "Natural language question (optional if provided as trailing argument or via STDIN)") { |v| options[:question] = v }
  opts.on("--workspace NAME", "Force workspace (skip intent agent)") { |v| options[:workspace] = v }
  opts.on("--tables x,y", Array, "Force tables (skip table agent)") { |v| options[:tables] = v.map(&:strip) }
  opts.on("--fixtures PATH", "Path to fixtures directory (workspaces.yml, schemas.yml, sql_examples.yml)") { |v| options[:fixtures_path] = File.expand_path(v) }
  opts.on("--profile NAME", "Profile key from config.yml for DB and defaults (default: upskill)") { |v| options[:profile] = v }
  opts.on("--debug", "Print intermediate artifacts") { options[:debug] = true }
  opts.on("--dry-run", "Use deterministic stubs, no network") { options[:dry_run] = true }
  opts.on("-h", "--help", "Help") { puts opts; exit 0 }
end.parse!

if options[:question].nil?
  trailing = ARGV.shift
  options[:question] = trailing if trailing
end

if options[:question].nil? && !STDIN.tty? && !STDIN.closed?
  options[:question] = STDIN.read.strip
end

abort "Please provide a question (argument, --question, or STDIN)" if options[:question].to_s.strip.empty?

profiles = config["workspaces"] || {}
profile_cfg = if options[:profile]
  profiles[options[:profile]] || profiles[options[:profile].to_s] || {}
else
  {}
end
schema_defaults = config.dig("default", "schema_export") || {}
db_defaults = config["default_db"] || {}
db_cfg = if options[:profile]
  db_defaults.merge(profile_cfg["database"] || {})
else
  nil
end

fixtures_path = options[:fixtures_path] ||
  config["fixtures_path"] ||
  profile_cfg.dig("schema_export", "output_dir") ||
  schema_defaults["output_dir"] ||
  File.expand_path("lib/query_gpt/fixtures/generated", __dir__)
fixtures_path = File.expand_path(fixtures_path, __dir__)

workspace_store = QueryGPT::WorkspaceStore.load_fixtures(root: fixtures_path)

llm = QueryGPT::LLMClient.new(
  api_key: ENV["OPENAI_API_KEY"],
  dry_run: options[:dry_run]
)

vector_store = QueryGPT::VectorStore.new
embeddings = QueryGPT::Embeddings.new(llm: llm, dry_run: options[:dry_run])

logger = if options[:debug]
  proc { |msg| puts "[debug] #{msg}" }
else
  nil
end

pipeline = QueryGPT::Pipeline.new(
  workspace_store: workspace_store,
  llm: llm,
  vector_store: vector_store,
  embeddings: embeddings,
  intent_agent: QueryGPT::IntentAgent.new(llm: llm),
  table_agent: QueryGPT::TableAgent.new(llm: llm),
  column_prune_agent: QueryGPT::ColumnPruneAgent.new(llm: llm),
  prompt_enhancer: QueryGPT::PromptEnhancer.new(llm: llm),
  sql_generator: QueryGPT::SQLGenerator.new(llm: llm),
  evaluator: QueryGPT::Evaluator.new,
  logger: logger
)

result = pipeline.run(
  question: options[:question],
  forced_workspace: options[:workspace],
  forced_tables: options[:tables],
  debug: options[:debug]
)

puts "\n=== SQL ===\n#{result.generated_sql}"
puts "\n=== Explanation ===\n#{result.explanation}"

if !options[:dry_run]
  if db_cfg.nil? || db_cfg.empty? || !(db_cfg["url"] || db_cfg["database"] || db_cfg["dbname"])
    puts "\n(No DB config found. Provide --profile with database settings in config.yml or use --dry-run. Skipping execution.)"
  else
    erb_cfg = ERB.new(db_cfg.to_yaml).result
    db_params = YAML.safe_load(erb_cfg)
    executor = QueryGPT::QueryExecutor.new(db_config: db_params, logger: logger)
    exec_result = executor.run(result.generated_sql)
    puts "\n=== Results (#{exec_result[:rows].size} rows) ==="
    puts exec_result[:columns].join("\t")
    exec_result[:rows].each do |row|
      puts row.map { |v| v.nil? ? "NULL" : v }.join("\t")
    end
  end
else
  puts "\n(Dry run: SQL not executed)"
end

if options[:debug]
  puts "\n=== Debug ==="
  puts result.debug.to_json
end
