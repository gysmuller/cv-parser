# frozen_string_literal: true

module CvParser
  class Configuration
    attr_accessor :provider, :model, :api_key, :timeout, :max_retries, :prompt, :system_prompt
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
    end
  end
end
