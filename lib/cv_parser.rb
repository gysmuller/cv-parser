# frozen_string_literal: true

require_relative "cv_parser/version"
require_relative "cv_parser/configuration"
require_relative "cv_parser/errors"
require_relative "cv_parser/providers/base"
require_relative "cv_parser/providers/openai"
require_relative "cv_parser/providers/anthropic"
require_relative "cv_parser/providers/faker"
require_relative "cv_parser/extractor"
require_relative "cv_parser/cli"

# A Ruby gem for parsing CVs and resumes using AI providers
module CvParser
  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration) if block_given?
      configuration
    end

    def reset
      @configuration = Configuration.new
    end
  end

  class Error < StandardError; end
end
