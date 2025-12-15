# QueryGPT Ruby Demo

QueryGPT is a Ruby CLI that turns natural language questions into SQL using a multi agent pipeline inspired by Uber's QueryGPT blog post. It runs locally, loads curated workspaces, proposes tables, prunes columns, gathers few shot SQL examples, and calls an LLM to produce SQL plus an explanation. A dry run mode uses deterministic stubs so it works without an API key or network.

## Setup
```bash
cd ~/Project/query_gpt
bundle install
```

## Run
```bash
# With OpenAI (uses config.yml -> fixtures_path or defaults)
OPENAI_API_KEY=sk-... bundle exec ruby query_gpt.rb --question "How many trips were completed yesterday in Seattle?"

# Dry run (no network, deterministic)
bundle exec ruby query_gpt.rb --question "How many trips were completed yesterday in Seattle?" --dry-run --debug

# Override workspace or tables
bundle exec ruby query_gpt.rb --question "Ad impressions last week by campaign" --workspace Ads --debug
bundle exec ruby query_gpt.rb --question "User retention by cohort" --tables core.users,core.sessions --debug
```

## Use the app schema (connectors + cache)
Export the current database schema into QueryGPT fixtures (preferred). Default fixture lookup will use `fixtures/generated` if present or `fixtures_path` from config.yml:
```bash
# Edit config.yml -> workspaces.upskill.database (connection) and schema_export settings.
bundle exec ruby schema_export.rb --profile upskill
```
Then run the CLI pointing at the generated cache (or let the CLI pick it by default):
```bash
bundle exec ruby query_gpt.rb --fixtures lib/query_gpt/fixtures/generated --question "Show signups per day last week"
```

## Pipeline stages
- Workspaces: curated collections of tables and SQL examples per domain.
- Intent Agent: maps the user question to one or more workspaces.
- Table Agent: proposes relevant tables (accepts user override).
- Column Prune Agent: reduces schemas to relevant columns.
- Prompt Enhancer (optional): expands vague questions with added context.
- SQL Generator: builds a few shot prompt with pruned schemas and examples, enforces business rules, and asks for SQL plus explanation.
- Evaluator: basic checks for hallucinated tables/columns and syntactic sanity.

## Fixtures
See `lib/query_gpt/fixtures/*.yml` for demo workspaces, schemas, and SQL examples. Swap these with your own or plug in a real schema registry by replacing the workspace and schema loaders.

## Notes
- Uses Postgres dialect in prompts.
- LLM calls are via Faraday to OpenAI endpoints. Set `OPENAI_API_KEY`.
- Dry run returns deterministic JSON and SQL for testing and demos.
- No external database is required. SQL is printed, not executed.

## Connectors, cache, and extensions
- Config: edit `config.yml` to point at your fixtures cache (and schema export settings).
- Connectors fetch schemas from sources (e.g., ActiveRecord/Postgres today). Use them to generate a cached fixture set under `lib/query_gpt/fixtures/generated`.
- To add Snowflake or other sources, implement `QueryGPT::Connectors::BaseConnector#fetch` and write fixtures via `WorkspaceStore.write_fixtures`.
- To add curated SQL examples, edit `sql_examples.yml` in your generated directory.
- A real schema registry can be wired by replacing `WorkspaceStore.load_fixtures` with a custom loader.
