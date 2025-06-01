# frozen_string_literal: true

module CvParser
  module Providers
    class Base
      def initialize(config)
        @config = config
      end

      def extract_data(output_schema:, content: nil, file_path: nil)
        raise NotImplementedError, "Subclasses must implement extract_data"
      end

      def upload_file(file_path)
        raise NotImplementedError, "Subclasses must implement upload_file"
      end

      protected

      def build_prompt(content, schema)
        <<~PROMPT
          Please extract structured information from the following CV/Resume.

          The output should be formatted as JSON with the following schema:
          #{schema.to_json}

          CV/Resume Content:
          #{content}

          Instructions:
          1. Extract all the requested fields from the CV.
          2. Maintain the exact structure defined in the schema.
          3. If information for a field is not available, use null or empty arrays as appropriate.
          4. For dates, use the format provided in the CV.
          5. Return only JSON without any additional explanations.
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
