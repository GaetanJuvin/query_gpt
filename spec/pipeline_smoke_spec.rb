require_relative "spec_helper"

RSpec.describe QueryGPT::Pipeline do
  let(:store) { QueryGPT::WorkspaceStore.load_fixtures(root: File.expand_path("../lib/query_gpt/fixtures", __dir__)) }
  let(:llm) { QueryGPT::LLMClient.new(api_key: "stub", dry_run: true) }
  let(:vector_store) { QueryGPT::VectorStore.new }
  let(:embeddings) { QueryGPT::Embeddings.new(llm: llm, dry_run: true) }

  let(:pipeline) do
    described_class.new(
      workspace_store: store,
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
  end

  it "runs end to end in dry run mode" do
    result = pipeline.run(
      question: "How many trips were completed yesterday in Seattle?",
      debug: true
    )

    expect(result.generated_sql).to include("SELECT")
    expect(result.pruned_schemas).not_to be_empty
    expect(result.explanation).not_to be_nil
  end
end
