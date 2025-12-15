module QueryGPT
  class Evaluator
    def evaluate(sql:, pruned_schemas:)
      sql = strip_fences(sql)
      errors = []
      errors << "SQL missing SELECT" unless sql.to_s.strip.match?(/\A\s*(with|select)\b/i)

      allowed_tables = pruned_schemas.map { |s| s.table_id.downcase }
      table_columns = pruned_schemas.to_h { |s| [s.table_id.downcase, columns_for(s)] }

      referenced_tables = extract_tables(sql)
      referenced_tables.each do |t|
        errors << "Table #{t} not allowed" unless allowed_tables.include?(t)
      end

      referenced_columns(sql).each do |(table, col)|
        next unless table
        if table_columns[table]
          errors << "Column #{table}.#{col} not allowed" unless table_columns[table].include?(col)
        else
          errors << "Table #{table} not allowed for column #{col}"
        end
      end

      {
        valid: errors.empty?,
        errors: errors.uniq
      }
    end

    private

    def columns_for(schema)
      schema.columns.map { |c| (c[:name] || c["name"]).downcase }
    end

    def extract_tables(sql)
      sql.scan(/(?:from|join)\s+([a-zA-Z0-9_\.]+)/i).flatten.map(&:downcase).uniq
    end

    def referenced_columns(sql)
      sql.scan(/([a-zA-Z0-9_\.]+)\.([a-zA-Z0-9_]+)/).map do |table, col|
        [table.downcase, col.downcase]
      end
    end

    def strip_fences(sql)
      sql = sql.to_s.strip
      sql = sql.sub(/\A```(?:sql)?/i, "")
      sql = sql.sub(/```+\z/, "")
      sql
    end
  end
end
