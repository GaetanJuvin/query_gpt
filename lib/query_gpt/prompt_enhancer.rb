module QueryGPT
  class PromptEnhancer
    def initialize(llm:)
      @llm = llm
    end

    def enhance(question:, dry_run: false)
      return { question: question, expanded: question } if dry_run

      prompt = <<~PROMPT
        Expand the following analytics question with additional helpful context, without changing its intent.
        Make the result concise and specific.
        Return only the enhanced question text.
        Question: #{question}
      PROMPT
      expanded = @llm.chat(messages: [{ role: "user", content: prompt }])
      { question: question, expanded: expanded.strip }
    rescue StandardError
      { question: question, expanded: question }
    end
  end
end
