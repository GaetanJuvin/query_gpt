module QueryGPT
  class Embeddings
    def initialize(llm:, dry_run: false)
      @llm = llm
      @dry_run = dry_run
    end

    def embed_texts(texts)
      @llm.embeddings(inputs: texts)
    end
  end
end
