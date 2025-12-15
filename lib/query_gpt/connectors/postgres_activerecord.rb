require_relative "base_connector"

module QueryGPT
  module Connectors
    # Pulls schema from an ActiveRecord connection (Postgres) and returns QueryGPT fixture data.
    class PostgresActiveRecordConnector < BaseConnector
      def initialize(connection:, workspace:, description:, include_tables: [], exclude_tables: %w[schema_migrations ar_internal_metadata __diesel_schema_migrations])
        @connection = connection
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
      end

      private

      def table_list
        all = @connection.tables
        if @include_tables.any?
          all & @include_tables
        else
          all - @exclude_tables
        end
      end

      def build_schema(table)
        cols = @connection.columns(table).map do |col|
          {
            name: col.name,
            type: col.sql_type,
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
    end
  end
end
