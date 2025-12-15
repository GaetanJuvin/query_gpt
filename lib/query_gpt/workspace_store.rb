require "yaml"
require "fileutils"
require_relative "types"

module QueryGPT
  class WorkspaceStore
    attr_reader :workspaces, :tables, :sql_examples

    def self.load_fixtures(root: File.expand_path("../query_gpt/fixtures", __dir__))
      workspaces_path = File.join(root, "workspaces.yml")
      schemas_path = File.join(root, "schemas.yml")
      examples_path = File.join(root, "sql_examples.yml")
      data = {
        workspaces: YAML.load_file(workspaces_path),
        schemas: YAML.load_file(schemas_path),
        examples: YAML.load_file(examples_path)
      }
      new(data)
    end

    def self.write_fixtures(data, output_dir:)
      FileUtils.mkdir_p(output_dir)
      File.write(File.join(output_dir, "workspaces.yml"), YAML.dump(data[:workspaces] || data["workspaces"]))
      File.write(File.join(output_dir, "schemas.yml"), YAML.dump(data[:schemas] || data["schemas"]))
      File.write(File.join(output_dir, "sql_examples.yml"), YAML.dump(data[:examples] || data["examples"]))
    end

    def initialize(data)
      workspaces_data = data[:workspaces] || data["workspaces"]
      schemas_data = data[:schemas] || data["schemas"]
      examples_data = data[:examples] || data["examples"]

      @workspaces = workspaces_data.map do |row|
        Workspace.new(
          name: row[:name] || row["name"],
          description: row[:description] || row["description"],
          table_ids: row[:table_ids] || row["table_ids"],
          sql_example_ids: row[:sql_example_ids] || row["sql_example_ids"]
        )
      end

      @tables = schemas_data.map do |row|
        TableSchema.new(
          table_id: row[:table_id] || row["table_id"],
          description: row[:description] || row["description"],
          columns: row[:columns] || row["columns"],
          partition_info: row[:partition_info] || row["partition_info"]
        )
      end

      @sql_examples = examples_data.map do |row|
        SqlExample.new(
          id: row[:id] || row["id"],
          workspace: row[:workspace] || row["workspace"],
          description: row[:description] || row["description"],
          sql: row[:sql] || row["sql"]
        )
      end
    end

    def workspace_names
      @workspaces.map(&:name)
    end

    def workspace_by_name(name)
      @workspaces.find { |w| w.name.downcase == name.to_s.downcase }
    end

    def tables_for(workspace_names)
      ids = workspace_names.flat_map { |w| workspace_by_name(w)&.table_ids || [] }
      @tables.select { |t| ids.include?(t.table_id) }
    end

    def table_by_id(id)
      @tables.find { |t| t.table_id == id }
    end

    def sql_examples_for(workspace_names)
      ids = workspace_names.flat_map { |w| workspace_by_name(w)&.sql_example_ids || [] }
      @sql_examples.select { |ex| ids.include?(ex.id) }
    end
  end
end
