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

module CvParser
  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      if block_given?
        yield(configuration)
        # The block is expected to create a new Configuration and assign it
        # to @configuration via instance_variable_set, but if not, we can
        # still use the default configuration initialized above
      end
      configuration
    end

    def reset
      @configuration = Configuration.new
    end
  end

  class Error < StandardError; end

  # Your code goes here...
end
