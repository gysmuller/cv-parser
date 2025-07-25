# frozen_string_literal: true

module CvParser
  class Extractor
    def initialize(config = CvParser.configuration)
      @config = config
      validate_config!
      @provider = build_provider
    end

    def extract(file_path:, output_schema: nil)
      # Validate the file exists and is readable
      validate_file!(file_path)

      # Use provided output_schema or fall back to configuration
      schema = output_schema || @config.output_schema

      # Validate schema exists
      raise ConfigurationError, "Output schema not configured" if schema.nil?

      # Send file directly to LLM provider for extraction
      @provider.extract_data(
        file_path: file_path,
        output_schema: schema
      )
    end

    private

    def validate_config!
      raise ConfigurationError, "LLM provider not configured" if @config.provider.nil?

      # Skip API key validation for faker provider
      return if @config.provider == :faker
      return unless @config.api_key.nil? || @config.api_key.empty?

      raise ConfigurationError, "API key not configured"
    end

    def build_provider
      case @config.provider
      when :openai
        Providers::OpenAI.new(@config)
      when :anthropic
        Providers::Anthropic.new(@config)
      when :faker
        Providers::Faker.new(@config)
      else
        raise ConfigurationError, "Unsupported provider: #{@config.provider}"
      end
    end

    def validate_file!(file_path)
      raise FileNotFoundError, "File not found: #{file_path}" unless File.exist?(file_path)
      raise FileNotReadableError, "File not readable: #{file_path}" unless File.readable?(file_path)
    end
  end
end
