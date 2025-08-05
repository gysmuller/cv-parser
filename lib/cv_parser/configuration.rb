# frozen_string_literal: true

module CvParser
  # Configuration settings for CV parser including LLM provider, API credentials, and extraction options
  class Configuration
    attr_accessor :provider, :model, :api_key, :timeout, :max_retries, :prompt, :system_prompt,
                  :output_schema, :max_tokens, :temperature
    attr_reader :provider_options

    def initialize
      @provider = nil
      @model = nil
      @api_key = nil
      @timeout = 60
      @max_retries = 3
      @provider_options = {}
      @prompt = nil
      @system_prompt = nil
      @output_schema = nil
      @max_tokens = 4000
      @temperature = 0.1
    end
  end
end
