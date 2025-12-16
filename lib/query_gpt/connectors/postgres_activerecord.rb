require_relative "base_connector"
require "pg"

module QueryGPT
  module Connectors
    # Pulls schema from Postgres using the pg gem and returns QueryGPT fixture data.
    class PostgresActiveRecordConnector < BaseConnector
      def initialize(db_config:, workspace:, description:, include_tables: [], exclude_tables: %w[schema_migrations ar_internal_metadata __diesel_schema_migrations])
        @db_config = db_config
        @workspace = workspace
        @description = description
        @include_tables = include_tables
        @exclude_tables = exclude_tables
      end

      def fetch
        tables = table_list
        schemas = tables.map { |t| build_schema(t) }

        {
          workspaces: [
            {
              name: @workspace,
              description: @description,
              table_ids: tables,
              sql_example_ids: [] # leave empty; caller can add curated examples
            }
          ],
          schemas: schemas,
          examples: []
        }
      ensure
        @conn&.close
      end

      private

      def connection
        return @conn if @conn
        params = pg_params(@db_config)
        @conn = PG.connect(params)
      end

      def table_list
        sql = "SELECT tablename FROM pg_tables WHERE schemaname NOT IN ('pg_catalog','information_schema')"
        res = connection.exec(sql)
        all = res.values.flatten
        if @include_tables.any?
          all & @include_tables
        else
          all - @exclude_tables
        end
      end

      def build_schema(table)
        sql = <<~SQL
          SELECT column_name, data_type
          FROM information_schema.columns
          WHERE table_name = $1
          ORDER BY ordinal_position
        SQL
        res = connection.exec_params(sql, [table])
        cols = res.map do |row|
          {
            name: row["column_name"],
            type: row["data_type"],
            description: ""
          }
        end
        {
          table_id: table,
          description: "Exported table #{table}",
          columns: cols,
          partition_info: nil
        }
      end

      def pg_params(cfg)
        if cfg["url"]
          uri = URI(cfg["url"])
          {
            host: uri.host,
            port: uri.port,
            dbname: uri.path&.sub(%r{\A/}, ""),
            user: uri.user,
            password: uri.password
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
    end
  end
end
