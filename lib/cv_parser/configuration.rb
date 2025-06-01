# frozen_string_literal: true

module CvParser
  class Configuration
    attr_accessor :provider, :model, :api_key, :timeout, :max_retries
    attr_reader :provider_options

    def initialize
      @provider = nil
      @model = nil
      @api_key = nil
      @timeout = 60
      @max_retries = 3
      @provider_options = {}
    end

    def configure_openai(access_token:, organization_id: nil, **options)
      @provider = :openai
      @api_key = access_token
      @provider_options = { organization_id: organization_id }.merge(options)
    end

    def configure_anthropic(api_key:, **options)
      @provider = :anthropic
      @api_key = api_key
      @provider_options = options
    end
  end
end
