require_relative "spec_helper"

RSpec.describe QueryGPT::VectorStore do
  it "returns entries ordered by cosine similarity" do
    vs = described_class.new
    vs.add(id: "a", vector: [1, 0, 0], metadata: { name: "a" })
    vs.add(id: "b", vector: [0, 1, 0], metadata: { name: "b" })
    vs.add(id: "c", vector: [1, 1, 0], metadata: { name: "c" })

    hits = vs.query([0.9, 0.1, 0], top_k: 2)
    expect(hits.map { |h| h[:id] }).to eq(["a", "c"])
    expect(hits.first[:score]).to be > hits.last[:score]
  end
end
