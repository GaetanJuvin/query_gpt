require "json"

module QueryGPT
  class ColumnPruneAgent
    def initialize(llm:)
      @llm = llm
    end

    def prune(question:, table_schema:, target_columns: 15, dry_run: false)
      return heuristic_prune(question, table_schema, target_columns) if dry_run

      prompt = <<~PROMPT
        You are Column Prune Agent. Given a question and table schema, choose the most relevant columns.
        Respond in strict JSON with keys "table_id", "keep_columns" (array of column names), and "reason".
        Table: #{table_schema.table_id}
        Columns: #{table_schema.columns.map { |c| c[:name] || c["name"] }.join(", ")}
        Question: #{question}
        Keep at most #{target_columns} columns.
      PROMPT
      raw = @llm.chat(messages: [{ role: "user", content: prompt }])
      parse_with_retry(raw, table_schema, target_columns) do
        heuristic_prune(question, table_schema, target_columns)
      end
    end

    private

    def heuristic_prune(question, table_schema, target)
      keywords = question.downcase.split(/\W+/)
      cols = table_schema.columns.map { |c| c[:name] || c["name"] }
      matched = cols.select { |c| keywords.any? { |k| c.include?(k) } }
      keep = (matched.empty? ? cols.first(target) : matched.first(target))
      {
        "table_id" => table_schema.table_id,
        "keep_columns" => keep.first(target),
        "reason" => "heuristic"
      }
    end

    def parse_with_retry(raw, table_schema, target_columns)
      parsed = safe_json(raw)
      return parsed if parsed
      repaired = @llm.chat(messages: [{ role: "user", content: "Return valid JSON only with table_id and keep_columns. Invalid response: #{raw}" }])
      safe_json(repaired) || {
        "table_id" => table_schema.table_id,
        "keep_columns" => table_schema.columns.map { |c| c[:name] || c["name"] }.first(target_columns),
        "reason" => "fallback"
      }
    end

    def safe_json(raw)
      JSON.parse(raw.to_s)
    rescue JSON::ParserError
      nil
    end
  end
end
