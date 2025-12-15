module QueryGPT
  class SQLGenerator
    BUSINESS_RULES = <<~RULES
      - Dialect: PostgreSQL.
      - Do not invent tables or columns. Use only provided schemas.
      - Always include explicit column lists, avoid SELECT *.
      - Include sensible date filters if question implies recency.
      - Use partition columns in filters when present.
      - Return two sections: "SQL:" then "Explanation:".
    RULES

    def initialize(llm:)
      @llm = llm
    end

    def generate(question:, enhanced_question:, pruned_schemas:, sql_examples:, workspaces:, dry_run: false)
      return stub_result if dry_run

      prompt = build_prompt(
        question: question,
        enhanced_question: enhanced_question,
        pruned_schemas: pruned_schemas,
        sql_examples: sql_examples,
        workspaces: workspaces
      )

      raw = @llm.chat(messages: [{ role: "system", content: "You are SQL Generator." }, { role: "user", content: prompt }])
      parsed = extract_sql_and_explanation(raw)
      parsed.merge(prompt: prompt, raw: raw)
    end

    def repair(sql:, explanation:, errors:, pruned_schemas:, question:, dry_run: false)
      return { sql: sql, explanation: "#{explanation} (stub repair)" } if dry_run

      repair_prompt = <<~PROMPT
        The previous SQL had issues: #{errors.join("; ")}.
        Fix the SQL. Use only provided schemas. Keep the same intent.
        Schemas:
        #{format_schemas(pruned_schemas)}
        Question: #{question}
        Return the same two sections: SQL: then Explanation:
        Previous SQL:
        #{sql}
      PROMPT
      raw = @llm.chat(messages: [{ role: "user", content: repair_prompt }])
      extract_sql_and_explanation(raw).merge(raw: raw, prompt: repair_prompt)
    end

    private

    def build_prompt(question:, enhanced_question:, pruned_schemas:, sql_examples:, workspaces:)
      <<~PROMPT
        You generate SQL for analytics questions.
        Workspaces: #{workspaces.join(", ")}
        Business rules:
        #{BUSINESS_RULES}

        Schemas (only these are allowed):
        #{format_schemas(pruned_schemas)}

        Few shot SQL examples (they may inspire style and joins):
        #{format_examples(sql_examples)}

        Original question: #{question}
        Enhanced question: #{enhanced_question}

        Produce:
        SQL: <query>
        Explanation: <short explanation of logic and filters>
      PROMPT
    end

    def format_schemas(pruned_schemas)
      pruned_schemas.map do |schema|
        cols = schema.columns.map { |c| c[:name] || c["name"] }
        desc = schema.columns.map { |c| "#{c[:name] || c['name']} (#{c[:type] || c['type']})" }.join(", ")
        info = schema.partition_info ? " partition: #{schema.partition_info}" : ""
        "- #{schema.table_id}#{info}\n  Columns: #{desc}"
      end.join("\n")
    end

    def format_examples(examples)
      return "None" if examples.empty?
      examples.map { |ex| "Example #{ex.id} (#{ex.workspace}): #{ex.description}\n#{ex.sql}" }.join("\n\n")
    end

    def extract_sql_and_explanation(raw)
      text = strip_fences(raw.to_s)
      if text =~ /SQL:\s*(.+?)Explanation:\s*(.+)/m
        sql = Regexp.last_match(1).strip
        expl = Regexp.last_match(2).strip
        { sql: sql, explanation: expl }
      else
        { sql: text.strip, explanation: "LLM did not provide separate explanation." }
      end
    end

    def strip_fences(text)
      text = text.strip
      text = text.sub(/\A```(?:sql)?/i, "")
      text = text.sub(/```+\z/, "")
      text
    end

    def stub_result
      {
        sql: "SELECT city, count(*) AS trips FROM mobility.trips GROUP BY 1 ORDER BY 2 DESC;",
        explanation: "Counts trips by city using stub generator",
        raw: "stub",
        prompt: "stub"
      }
    end
  end
end
