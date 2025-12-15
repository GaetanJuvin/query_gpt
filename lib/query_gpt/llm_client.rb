require "json"
require "faraday"

module QueryGPT
  class LLMClient
    DEFAULT_CHAT_MODEL = "gpt-4.1-mini".freeze
    DEFAULT_EMBED_MODEL = "text-embedding-3-small".freeze
    attr_reader :dry_run

    def initialize(api_key:, base_url: "https://api.openai.com/v1", dry_run: false)
      @api_key = api_key
      @base_url = base_url
      @dry_run = dry_run
    end

    def chat(messages:, model: DEFAULT_CHAT_MODEL, temperature: 0.1)
      return stub_chat(messages) if @dry_run
      raise "OPENAI_API_KEY is required" if @api_key.to_s.strip.empty?

      response = connection.post("chat/completions") do |req|
        req.body = JSON.dump(
          model: model,
          temperature: temperature,
          messages: messages
        )
      end

      parsed = safe_parse(response.body)
      content = parsed.dig("choices", 0, "message", "content")
      content || raise("Chat response missing content: #{response.status} #{response.body}")
    end

    def embeddings(inputs:, model: DEFAULT_EMBED_MODEL)
      return inputs.map { |txt| deterministic_vector(txt) } if @dry_run
      raise "OPENAI_API_KEY is required" if @api_key.to_s.strip.empty?

      response = connection.post("embeddings") do |req|
        req.body = JSON.dump(model: model, input: inputs)
      end

      parsed = safe_parse(response.body)
      data = parsed["data"] || []
      data.map { |row| row["embedding"] }
    end

    private

    def connection
      @connection ||= Faraday.new(url: @base_url) do |f|
        f.request :json
        f.response :raise_error
        f.headers["Content-Type"] = "application/json"
        f.headers["Authorization"] = "Bearer #{@api_key}"
      end
    rescue Faraday::Error => e
      raise "Failed to build Faraday connection: #{e.message}"
    end

    def safe_parse(body)
      JSON.parse(body)
    rescue JSON::ParserError => e
      raise "Failed to parse LLM response: #{e.message} #{body}"
    end

    def stub_chat(messages)
      last = messages.last
      content = last && last[:content] || last && last["content"] || ""
      # Provide deterministic JSON-ish answers for agents
      if content.include?("intent") || content.include?("workspaces")
        return '{"workspaces":["Mobility","CoreServices"],"reason":"stub intent"}'
      end
      if content.include?("tables") && content.include?("reason")
        return '{"tables":["mobility.trips","core.users"],"reason":"stub tables"}'
      end
      if content.include?("keep_columns")
        return '{"table_id":"mobility.trips","keep_columns":["trip_id","city","status","requested_at","completed_at","fare_amount"],"reason":"stub prune"}'
      end
      if content.include?("repair") || content.include?("fix the SQL")
        return "SELECT 1 as stub_sql; Explanation: repaired."
      end
      # Default SQL stub
      "SELECT 1 as answer;\n-- explanation: stub response"
    end

    def deterministic_vector(text)
      seed = text.each_byte.reduce(0) { |acc, b| (acc * 31 + b) % 10_000 }
      Array.new(8) { |i| ((seed + i * 13) % 1000) / 1000.0 }
    end
  end
end
