---
# Default fixture cache (workspaces.yml, schemas.yml, sql_examples.yml)
fixtures_path: "./lib/query_gpt/fixtures/generated"

default: &default
  schema_export:
    description: "Exported from Rails schema"
    output_dir: "./lib/query_gpt/fixtures/generated"
    include_tables: []
    exclude_tables:
      - schema_migrations
      - ar_internal_metadata
      - __diesel_schema_migrations

# DB defaults, similar to database.yml
default_db: &default_db
  adapter: postgresql
  encoding: unicode
  pool: 5
  host: localhost
  port: 5432
  username: postgres
  password: ""

workspaces:
  upskill:
    <<: *default
    database:
      <<: *default_db
      database: qwasar_dev
      username: gaetanjuvin
      password: "<%= ENV.fetch('UPSKILL_DB_PASSWORD', '') %>"
    schema_export:
      <<: *default
      workspace: "Upskill"

  billing:
    <<: *default
    database:
      <<: *default_db
      database: billing
      username: billing
      password: "<%= ENV.fetch('BILLING_DB_PASSWORD', '') %>"
    schema_export:
      description: "Billing export"
      workspace: "Billing"
      output_dir: "./lib/query_gpt/fixtures/billing"

  analytics:
    <<: *default
    database:
      <<: *default_db
      url: "<%= ENV['ANALYTICS_DATABASE_URL'] %>"
    schema_export:
      workspace: "Analytics"
      include_tables:
        - events
        - users
