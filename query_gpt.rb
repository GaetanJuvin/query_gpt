#!/usr/bin/env ruby
require "bundler/setup"
require "optparse"
require "json"
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
require_relative "lib/query_gpt/config"

config = QueryGPT::Config.load

generated_fixtures = File.expand_path("lib/query_gpt/fixtures/generated", __dir__)
default_fixtures = if config.dig("fixtures_path")
  File.expand_path(config["fixtures_path"], __dir__)
elsif File.directory?(generated_fixtures)
  generated_fixtures
else
  File.expand_path("lib/query_gpt/fixtures", __dir__)
end

options = {
  debug: false,
  dry_run: false,
  tables: [],
  workspace: nil,
  fixtures_path: default_fixtures
}

OptionParser.new do |opts|
  opts.banner = "Usage: bundle exec ruby query_gpt.rb [options] \"question text\""

  opts.on("--question QUESTION", "Natural language question (optional if provided as trailing argument or via STDIN)") { |v| options[:question] = v }
  opts.on("--workspace NAME", "Force workspace (skip intent agent)") { |v| options[:workspace] = v }
  opts.on("--tables x,y", Array, "Force tables (skip table agent)") { |v| options[:tables] = v.map(&:strip) }
  opts.on("--fixtures PATH", "Path to fixtures directory (workspaces.yml, schemas.yml, sql_examples.yml)") { |v| options[:fixtures_path] = File.expand_path(v) }
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

workspace_store = QueryGPT::WorkspaceStore.load_fixtures(root: options[:fixtures_path])

llm = QueryGPT::LLMClient.new(
  api_key: ENV["OPENAI_API_KEY"],
  dry_run: options[:dry_run]
)

vector_store = QueryGPT::VectorStore.new
embeddings = QueryGPT::Embeddings.new(llm: llm, dry_run: options[:dry_run])

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
  evaluator: QueryGPT::Evaluator.new
)

result = pipeline.run(
  question: options[:question],
  forced_workspace: options[:workspace],
  forced_tables: options[:tables],
  debug: options[:debug]
)

puts "\n=== SQL ===\n#{result.generated_sql}"
puts "\n=== Explanation ===\n#{result.explanation}"

if options[:debug]
  puts "\n=== Debug ==="
  puts result.debug.to_json
end
