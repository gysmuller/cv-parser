# frozen_string_literal: true

require "securerandom"
require_relative "../pdf_converter"

module CvParser
  module Providers
    # Base class for CV parsing providers that defines the common interface
    # and shared functionality for extracting structured data from CV files.
    class Base
      def initialize(config)
        @config = config
        @pdf_converter = CvParser::PdfConverter.new
        setup_http_client
      end

      def extract_data(output_schema:, file_path: nil)
        raise NotImplementedError, "Subclasses must implement extract_data"
      end

      def upload_file(file_path)
        raise NotImplementedError, "Subclasses must implement upload_file"
      end

      protected

      def setup_http_client
        @api_key = @config.api_key
        @timeout = @config.timeout || 60
        @base_headers = {
          "User-Agent" => "cv-parser-ruby/#{CvParser::VERSION}",
          **@config.provider_options.fetch(:headers, {})
        }
      end

      def convert_to_pdf_if_needed(file_path)
        file_ext = File.extname(file_path).downcase

        case file_ext
        when ".docx"
          # Generate a temporary PDF file path
          temp_pdf_path = File.join(
            File.dirname(file_path),
            "#{File.basename(file_path, file_ext)}_converted_#{SecureRandom.hex(8)}.pdf"
          )

          # Convert DOCX to PDF
          @pdf_converter.convert(file_path, temp_pdf_path)
          temp_pdf_path
        when ".pdf", ".txt", ".md"
          # PDF files, text files - return as-is
          # Text files will be handled as text content by providers
          file_path
        else
          # For other file types, let the provider handle them directly
          file_path
        end
      rescue StandardError => e
        raise APIError, "Failed to convert file: #{e.message}"
      end

      def cleanup_temp_file(processed_file_path, original_file_path)
        # Only delete if we created a temporary converted file
        if processed_file_path != original_file_path && File.exist?(processed_file_path)
          File.delete(processed_file_path)
        end
      rescue StandardError => e
        # Log the error but don't fail the main operation
        warn "Warning: Failed to cleanup temporary file #{processed_file_path}: #{e.message}"
      end

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

      def text_file?(file_path)
        [".txt", ".md"].include?(File.extname(file_path).downcase)
      end

      def read_text_file_content(file_path)
        content = File.read(file_path, encoding: "UTF-8")

        # Validate content is not empty
        raise EmptyTextFileError, "Text file is empty: #{file_path}" if content.strip.empty?

        content
      rescue Encoding::InvalidByteSequenceError, Encoding::UndefinedConversionError => e
        raise TextFileEncodingError, "Invalid text encoding in file #{file_path}: #{e.message}"
      end
    end
  end
end
