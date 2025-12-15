require "json"
require_relative "types"

module QueryGPT
  class Pipeline
    DEFAULT_EXAMPLE_K = 5

    def initialize(workspace_store:, llm:, vector_store:, embeddings:, intent_agent:, table_agent:, column_prune_agent:, prompt_enhancer:, sql_generator:, evaluator:)
      @workspace_store = workspace_store
      @llm = llm
      @vector_store = vector_store
      @embeddings = embeddings
      @intent_agent = intent_agent
      @table_agent = table_agent
      @column_prune_agent = column_prune_agent
      @prompt_enhancer = prompt_enhancer
      @sql_generator = sql_generator
      @evaluator = evaluator
    end

    def run(question:, forced_workspace: nil, forced_tables: [], debug: false)
      debug_info = {}

      enhanced = @prompt_enhancer.enhance(question: question, dry_run: dry_run?)
      debug_info[:enhanced_question] = enhanced

      selected_workspaces = pick_workspaces(question, forced_workspace, debug_info)
      candidate_tables = @workspace_store.tables_for(selected_workspaces).map(&:table_id)

      proposed_tables = pick_tables(question, forced_tables, candidate_tables, debug_info)
      confirmed_tables = proposed_tables

      pruned_schemas = prune_tables(question, confirmed_tables, debug_info)

      examples = select_examples(question, selected_workspaces, debug_info)

      gen_result = @sql_generator.generate(
        question: question,
        enhanced_question: enhanced[:expanded],
        pruned_schemas: pruned_schemas,
        sql_examples: examples,
        workspaces: selected_workspaces,
        dry_run: dry_run?
      )
      debug_info[:sql_generation] = { prompt: gen_result[:prompt], raw: gen_result[:raw] }

      eval_result = @evaluator.evaluate(sql: gen_result[:sql], pruned_schemas: pruned_schemas)
      debug_info[:evaluation] = eval_result

      if !eval_result[:valid] && !dry_run?
        repaired = @sql_generator.repair(
          sql: gen_result[:sql],
          explanation: gen_result[:explanation],
          errors: eval_result[:errors],
          pruned_schemas: pruned_schemas,
          question: question,
          dry_run: dry_run?
        )
        gen_result[:sql] = repaired[:sql]
        gen_result[:explanation] = repaired[:explanation]
        debug_info[:repair] = { prompt: repaired[:prompt], raw: repaired[:raw] }
      end

      PipelineResult.new(
        intent: debug_info[:intent],
        selected_workspaces: selected_workspaces,
        proposed_tables: proposed_tables,
        confirmed_tables: confirmed_tables,
        pruned_schemas: pruned_schemas,
        generated_sql: gen_result[:sql],
        explanation: gen_result[:explanation],
        debug: debug_info
      )
    end

    private

    def dry_run?
      @llm.respond_to?(:dry_run) && @llm.dry_run
    end

    def pick_workspaces(question, forced_workspace, debug_info)
      if forced_workspace
        [forced_workspace]
      else
        intent = @intent_agent.select_workspaces(
          question: question,
          candidates: @workspace_store.workspace_names,
          dry_run: dry_run?
        )
        debug_info[:intent] = intent
        chosen = intent.fetch("workspaces", [])
        chosen = @workspace_store.workspace_names.first(1) if chosen.empty?
        chosen
      end
    end

    def pick_tables(question, forced_tables, candidate_tables, debug_info)
      return forced_tables unless forced_tables.empty?

      res = @table_agent.propose_tables(
        question: question,
        candidate_tables: candidate_tables,
        top_k: 3,
        dry_run: dry_run?
      )
      debug_info[:table_agent] = res
      tables = res.fetch("tables", [])
      tables = candidate_tables.first(3) if tables.empty?
      tables
    end

    def prune_tables(question, confirmed_tables, debug_info)
      confirmed_tables.map do |table_id|
        schema = @workspace_store.table_by_id(table_id)
        next unless schema
        res = @column_prune_agent.prune(
          question: question,
          table_schema: schema,
          target_columns: 15,
          dry_run: dry_run?
        )
        debug_info[:column_prune] ||= []
        debug_info[:column_prune] << res
        keep = res["keep_columns"]
        filtered_cols = schema.columns.select do |c|
          keep.include?(c[:name] || c["name"])
        end
        TableSchema.new(
          table_id: schema.table_id,
          description: schema.description,
          columns: filtered_cols,
          partition_info: schema.partition_info
        )
      end.compact
    end

    def select_examples(question, workspaces, debug_info)
      examples = @workspace_store.sql_examples_for(workspaces)
      return examples if examples.empty?

      texts = examples.map { |ex| ex.description }
      vectors = @embeddings.embed_texts([question] + texts)
      query_vector = vectors.first
      example_vectors = vectors.drop(1)
      examples.zip(example_vectors).each do |ex, vec|
        @vector_store.add(id: ex.id, vector: vec, metadata: ex)
      end
      top = @vector_store.query(query_vector, top_k: DEFAULT_EXAMPLE_K).map { |hit| hit[:metadata] }
      debug_info[:few_shot_examples] = top.map(&:id)
      top
    end
  end
end
