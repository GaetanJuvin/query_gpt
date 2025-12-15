require_relative "spec_helper"

RSpec.describe QueryGPT::WorkspaceStore do
  let(:store) { described_class.load_fixtures(root: File.expand_path("../lib/query_gpt/fixtures", __dir__)) }

  it "loads workspaces, tables, and examples" do
    expect(store.workspaces.map(&:name)).to include("Mobility", "Ads", "CoreServices")
    expect(store.tables.map(&:table_id)).to include("mobility.trips", "ads.impressions", "core.sessions")
    expect(store.sql_examples.map(&:id)).to include("ex_trips_daily_city", "ex_ads_ctr", "ex_users_cohort")
  end

  it "filters tables by workspace" do
    tables = store.tables_for(["Mobility"]).map(&:table_id)
    expect(tables).to match_array(["mobility.trips", "mobility.driver_payments"])
  end

  it "filters examples by workspace" do
    ids = store.sql_examples_for(["Ads"]).map(&:id)
    expect(ids).to include("ex_ads_ctr")
    expect(ids).not_to include("ex_users_signup_daily")
  end
end
