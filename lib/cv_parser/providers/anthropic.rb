# frozen_string_literal: true

require "faraday"
require "json"
require "mime/types"
require "base64"
require "faraday/multipart"
require_relative "../pdf_converter"
require "securerandom"

module CvParser
  module Providers
    class Anthropic < Base
      ANTHROPIC_API_URL = "https://api.anthropic.com/v1/messages"

      ANTHROPIC_API_VERSION = "2023-06-01"
      DEFAULT_MODEL = "claude-3-opus-20240229"

      def initialize(config)
        super
        @client = setup_client
        @pdf_converter = CvParser::PdfConverter.new
      end

      def extract_data(output_schema:, content: nil, file_path: nil)
        if file_path
          # PDF file approach - use base64 encoding
          validate_file_exists!(file_path)
          validate_file_readable!(file_path)

          # Convert DOCX to PDF if necessary
          processed_file_path = convert_to_pdf_if_needed(file_path)

          # Read the file and encode it
          pdf_content = File.read(processed_file_path)
          base64_encoded_pdf = Base64.strict_encode64(pdf_content)

          response = @client.post do |req|
            req.headers["Content-Type"] = "application/json"
            req.headers["x-api-key"] = @config.api_key
            req.headers["anthropic-version"] = ANTHROPIC_API_VERSION

            req.body = {
              model: @config.model || DEFAULT_MODEL,
              max_tokens: 4000,
              temperature: 0.1,
              system: "You are a CV parsing assistant. Extract information from CVs and format as JSON.",
              messages: [
                {
                  role: "user",
                  content: [
                    # PDF document as base64
                    {
                      type: "document",
                      source: {
                        type: "base64",
                        media_type: "application/pdf",
                        data: base64_encoded_pdf
                      }
                    },
                    # Instructions for extraction
                    {
                      type: "text",
                      text: "Extract structured information from the attached CV/Resume as JSON with the following schema:\n#{output_schema.to_json}\n\nInstructions:\n1. Extract all the requested fields from the CV.\n2. Maintain the exact structure defined in the schema.\n3. If information for a field is not available, use null or empty arrays as appropriate.\n4. For dates, use the format provided in the CV.\n5. Return only raw JSON without any markdown formatting, code blocks, or additional explanations.\n6. Do not prefix your response with ```json or any other markdown syntax.\n7. Start your response with the opening curly brace { and end with the closing curly brace }."
                    }
                  ]
                }
              ]
            }.to_json
          end

          # Clean up temporary PDF file if we created one
          cleanup_temp_file(processed_file_path, file_path)
        elsif content
          # Text content approach
          response = @client.post do |req|
            req.headers["Content-Type"] = "application/json"
            req.headers["x-api-key"] = @config.api_key
            req.headers["anthropic-version"] = ANTHROPIC_API_VERSION

            req.body = {
              model: @config.model || DEFAULT_MODEL,
              max_tokens: 4000,
              temperature: 0.1,
              system: "You are a CV parsing assistant. Extract information from CVs and format as JSON.",
              messages: [
                {
                  role: "user",
                  content: build_prompt(content, output_schema)
                }
              ]
            }.to_json
          end
        else
          raise ArgumentError, "Either content or file_path must be provided"
        end

        handle_response(response, output_schema)
      rescue Faraday::Error => e
        raise APIError, "Anthropic API connection error: #{e.message}"
      end

      private

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
        when ".pdf"
          # Already a PDF, return as-is
          file_path
        else
          # For other file types, let Anthropic handle them directly
          file_path
        end
      rescue StandardError => e
        raise APIError, "Failed to convert DOCX to PDF: #{e.message}"
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

      def setup_client
        Faraday.new(url: ANTHROPIC_API_URL) do |f|
          f.options.timeout = @config.timeout
          f.request :json
          f.response :json
          f.adapter Faraday.default_adapter
        end
      end

      def handle_response(response, _schema)
        if response.status == 200
          response_body = response.body
          content = response_body["content"]

          # Improved content handling for different content structures
          raise ParseError, "Unexpected Anthropic response format: content is not an array" unless content.is_a?(Array)

          # Search for text content in the array
          text_content = nil
          content.each do |item|
            if item["type"] == "text" && item["text"]
              text_content = item["text"]
              break
            end
          end

          raise ParseError, "No text content found in Claude's response" unless text_content

          begin
            # Clean the text content to remove markdown formatting if present
            cleaned_text = text_content.strip
            cleaned_text = cleaned_text.gsub(/^```json\s*/, "").gsub(/\s*```$/, "")
            JSON.parse(cleaned_text)
          rescue JSON::ParserError => e
            raise ParseError, "Failed to parse Claude's response as JSON: #{e.message}"
          end

        elsif response.status == 429
          retry_after = response.headers["retry-after"]
          message = retry_after ? "Rate limit exceeded, retry after #{retry_after} seconds" : "Rate limit exceeded"
          raise RateLimitError, message
        elsif response.status == 401
          raise AuthenticationError, "Invalid API key or unauthorized access"
        elsif response.status == 400
          error_message = response.body["error"] ? response.body["error"]["message"] : "Bad request"
          raise InvalidRequestError, "Anthropic API error: #{error_message}"
        else
          error_type = response.body["error"] ? response.body["error"]["type"] : "unknown"
          error_message = response.body["error"] ? response.body["error"]["message"] : "Unknown error"
          raise APIError, "Anthropic API error: #{response.status} - #{error_type} - #{error_message}"
        end
      rescue JSON::ParserError => e
        raise ParseError, "Failed to parse Anthropic response as JSON: #{e.message}"
      end
    end
  end
end
