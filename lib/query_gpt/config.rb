require "yaml"
require "erb"

module QueryGPT
  module Config
    DEFAULT_PATH = File.expand_path("../../config.yml", __dir__)

    def self.load(path = DEFAULT_PATH)
      return {} unless File.exist?(path)
      erb = ERB.new(File.read(path)).result
      YAML.safe_load(erb, aliases: true) || {}
    end
  end
end
