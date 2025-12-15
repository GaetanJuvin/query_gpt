require "json"

module QueryGPT
  class TableAgent
    def initialize(llm:)
      @llm = llm
    end

    def propose_tables(question:, candidate_tables:, top_k: 3, dry_run: false)
      return heuristic(candidate_tables, top_k, question) if dry_run

      prompt = <<~PROMPT
        You are Table Agent. Given a question and candidate tables, pick up to #{top_k} tables that best answer it.
        Respond in strict JSON with keys "tables" (array of table ids) and "reason".
        Question: #{question}
        Candidate tables: #{candidate_tables.join(", ")}
      PROMPT
      raw = @llm.chat(messages: [{ role: "user", content: prompt }])
      res = parse_with_retry(raw, candidate_tables, question, top_k) do
        heuristic(candidate_tables, top_k, question)
      end
      res["tables"] = Array(res["tables"]) & candidate_tables
      res
    end

    private

    def heuristic(candidate_tables, top_k, question)
      tokens = question.downcase.split(/\W+/)
      scored = candidate_tables.map do |t|
        score = tokens.count { |tok| t.downcase.include?(tok) }
        [score, t]
      end
      ordered = scored.sort_by { |score, t| [-score, t] }.map(&:last)
      picks = ordered.reject { |t| t.start_with?("__") }.first(top_k)
      picks = candidate_tables.first(top_k) if picks.empty?
      { "tables" => picks, "reason" => "heuristic" }
    end

    def parse_with_retry(raw, candidate_tables, question, top_k)
      parsed = safe_json(raw)
      return parsed if parsed
      repaired = @llm.chat(messages: [{ role: "user", content: "Return valid JSON only for tables and reason. Invalid response: #{raw}" }])
      safe_json(repaired) || heuristic(candidate_tables, top_k, question).merge("reason" => "fallback")
    end

    def safe_json(raw)
      JSON.parse(raw.to_s)
    rescue JSON::ParserError
      nil
    end
  end
end
