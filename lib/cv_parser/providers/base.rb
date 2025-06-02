# frozen_string_literal: true

module CvParser
  module Providers
    # Base class for CV parsing providers that defines the common interface
    # and shared functionality for extracting structured data from CV files.
    class Base
      def initialize(config)
        @config = config
      end

      def extract_data(output_schema:, file_path: nil)
        raise NotImplementedError, "Subclasses must implement extract_data"
      end

      def upload_file(file_path)
        raise NotImplementedError, "Subclasses must implement upload_file"
      end

      protected

      def build_extraction_prompt(schema = nil)
        default_prompt = <<~PROMPT
          Extract structured information from the attached CV/Resume as JSON.

          Instructions:
          1. Extract all the requested fields from the CV.
          2. Maintain the exact structure defined in the schema.
          3. If information for a field is not available, use null or empty arrays as appropriate.
          4. For dates, use the format provided in the CV.
          5. Return only raw JSON without any markdown formatting, code blocks, or additional explanations.
          6. Do not prefix your response with ```json or any other markdown syntax.
          7. Start your response with the opening curly brace { and end with the closing curly brace }.
        PROMPT

        prompt = @config.prompt || default_prompt

        if schema
          prompt += <<~SCHEMA

            The output should be formatted as JSON with the following schema:
            #{schema.to_json}
          SCHEMA
        end

        prompt
      end

      def build_system_prompt
        return @config.system_prompt if @config.system_prompt

        <<~PROMPT
          You are a CV parsing assistant. Extract structured information from the attached CV/Resume.
        PROMPT
      end

      def validate_file_exists!(file_path)
        return if File.exist?(file_path)

        raise FileNotFoundError, "File not found: #{file_path}"
      end

      def validate_file_readable!(file_path)
        return if File.readable?(file_path)

        raise FileNotReadableError, "File not readable: #{file_path}"
      end
    end
  end
end
