module QueryGPT
  class VectorStore
    Entry = Struct.new(:id, :vector, :metadata, keyword_init: true)

    def initialize
      @entries = []
    end

    def add(id:, vector:, metadata: {})
      @entries << Entry.new(id: id, vector: vector, metadata: metadata)
    end

    def query(vector, top_k: 5)
      scored = @entries.map do |entry|
        [cosine_similarity(vector, entry.vector), entry]
      end
      scored.sort_by { |score, _| -score }.first(top_k).map do |score, entry|
        { id: entry.id, score: score, metadata: entry.metadata }
      end
    end

    private

    def cosine_similarity(a, b)
      return 0.0 if a.empty? || b.empty? || a.length != b.length
      dot = a.zip(b).sum { |x, y| x.to_f * y.to_f }
      norm_a = Math.sqrt(a.sum { |x| x.to_f**2 })
      norm_b = Math.sqrt(b.sum { |y| y.to_f**2 })
      return 0.0 if norm_a.zero? || norm_b.zero?
      dot / (norm_a * norm_b)
    end
  end
end
