require "pg"
require "uri"

module QueryGPT
  class QueryExecutor
    def initialize(db_config:, logger: nil)
      @db_config = db_config
      @logger = logger
    end

    def run(sql)
      clean_sql = sanitize_sql(sql)
      log("Executing SQL")
      conn = PG.connect(pg_params(@db_config))
      res = conn.exec(clean_sql)
      {
        columns: res.fields,
        rows: res.values
      }
    rescue StandardError => e
      raise "Execution failed: #{e.class} #{e.message}"
    ensure
      conn&.close
    end

    private

    def sanitize_sql(sql)
      text = sql.to_s.strip
      # Drop code fences and leading labels
      text = text.gsub(/```(?:sql)?/i, "")
      text = text.gsub(/```/, "")
      text = text.sub(/\ASQL:\s*/i, "")
      # If an explanation block exists, keep only the SQL portion before it
      if text =~ /Explanation:/i
        text = text.split(/Explanation:/i).first.to_s.strip
      end
      text.strip
    end

    def pg_params(cfg)
      # Supports URL or discrete fields
      if cfg["url"]
        url = URI(cfg["url"])
        {
          host: url.host,
          port: url.port,
          dbname: url.path&.sub(%r{\A/}, ""),
          user: url.user,
          password: url.password
        }.compact
      else
        {
          host: cfg["host"],
          port: cfg["port"],
          dbname: cfg["database"] || cfg["dbname"],
          user: cfg["username"] || cfg["user"],
          password: cfg["password"]
        }.compact
      end
    end

    def log(msg)
      @logger&.call(msg)
    end
  end
end
