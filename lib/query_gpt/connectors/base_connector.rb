module QueryGPT
  module Connectors
    class BaseConnector
      def fetch
        raise NotImplementedError, "implement #fetch to return {workspaces:, schemas:, examples:}"
      end
    end
  end
end
