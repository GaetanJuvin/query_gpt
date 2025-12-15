require "json"

module QueryGPT
  class IntentAgent
    def initialize(llm:)
      @llm = llm
    end

    def select_workspaces(question:, candidates:, dry_run: false)
      return heuristic_select(question, candidates) if dry_run

      prompt = <<~PROMPT
        You are Intent Agent. Given a user question and available workspaces, select the 1 or 2 most relevant workspaces.
        Respond in strict JSON with keys "workspaces" (array of strings) and "reason".
        Available workspaces: #{candidates.join(", ")}
        Question: #{question}
      PROMPT

      response = @llm.chat(messages: [{ role: "user", content: prompt }])
      parse_with_retry(response) do
        heuristic_select(question, candidates)
      end
    end

    private

    def heuristic_select(question, candidates)
      text = question.downcase
      picks = []
      picks << "Mobility" if text.match?(/trip|driver|ride|fare/)
      picks << "Ads" if text.match?(/ad|campaign|click|impression|spend|ctr/)
      picks << "CoreServices" if text.match?(/user|session|signup|cohort|retention/)
      picks = candidates & picks
      picks = candidates.first(1) if picks.empty?
      { "workspaces" => picks.first(2), "reason" => "heuristic" }
    end

    def parse_with_retry(raw)
      parsed = safe_json(raw)
      return parsed if parsed
      repaired_prompt = <<~PROMPT
        Return valid JSON only. You previously responded with invalid JSON:
        #{raw}
      PROMPT
      repaired = @llm.chat(messages: [{ role: "user", content: repaired_prompt }])
      safe_json(repaired) || yield
    end

    def safe_json(raw)
      json_text = raw.is_a?(String) ? raw.strip : raw.to_s
      JSON.parse(json_text)
    rescue JSON::ParserError
      nil
    end
  end
end
