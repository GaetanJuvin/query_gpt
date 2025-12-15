module QueryGPT
  Workspace = Struct.new(:name, :description, :table_ids, :sql_example_ids, keyword_init: true)

  TableSchema = Struct.new(:table_id, :description, :columns, :partition_info, keyword_init: true)

  SqlExample = Struct.new(:id, :workspace, :description, :sql, keyword_init: true)

  PipelineResult = Struct.new(
    :intent,
    :selected_workspaces,
    :proposed_tables,
    :confirmed_tables,
    :pruned_schemas,
    :generated_sql,
    :explanation,
    :debug,
    keyword_init: true
  )
end
