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
      DEFAULT_MODEL = "claude-3-5-sonnet-20241022"

      def initialize(config)
        super
        @client = setup_client
      end

      def extract_data(output_schema:, file_path: nil)
        raise ArgumentError, "File_path must be provided" unless file_path

        # Validate that we have a proper JSON Schema format
        unless output_schema.is_a?(Hash) &&
               ((output_schema.key?("type") && output_schema["type"] == "json_schema") ||
                (output_schema.key?(:type) && output_schema[:type] == "json_schema"))
          raise ArgumentError, "The Anthropic provider requires a JSON Schema format with 'type: \"json_schema\"'"
        end

        # PDF file approach - use base64 encoding
        validate_file_exists!(file_path)
        validate_file_readable!(file_path)

        # Convert DOCX to PDF if necessary
        processed_file_path = convert_to_pdf_if_needed(file_path)

        # Read the file and encode it
        pdf_content = File.read(processed_file_path)
        base64_encoded_pdf = Base64.strict_encode64(pdf_content)

        # Create the extraction tool with the provided schema
        extraction_tool = build_extraction_tool(output_schema)

        response = @client.post do |req|
          req.headers["Content-Type"] = "application/json"
          req.body = {
            model: @config.model || DEFAULT_MODEL,
            max_tokens: @config.max_tokens,
            temperature: @config.temperature,
            system: build_system_prompt,
            tools: [extraction_tool],
            tool_choice: { type: "tool", name: "extract_cv_data" },
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
                    text: build_extraction_prompt(output_schema)
                  }
                ]
              }
            ]
          }.to_json
        end

        # Clean up temporary PDF file if we created one
        cleanup_temp_file(processed_file_path, file_path)

        handle_tool_response(response, output_schema)
      rescue Faraday::Error => e
        raise APIError, "Anthropic API connection error: #{e.message}"
      end

      private

      def build_extraction_tool(output_schema)
        # Validate that we have a proper JSON Schema format
        unless output_schema.is_a?(Hash) &&
               ((output_schema.key?("type") && output_schema["type"] == "json_schema") ||
                (output_schema.key?(:type) && output_schema[:type] == "json_schema"))
          raise ArgumentError, "Invalid schema format. Please use JSON Schema format with 'type: \"json_schema\"'"
        end

        # Convert the schema to proper JSON Schema format
        json_schema = normalize_schema_to_json_schema(output_schema)

        {
          name: "extract_cv_data",
          description: "Extract structured data from a CV/resume document according to the provided schema. Always use this tool to return the extracted data in the exact format specified by the schema.",
          input_schema: json_schema
        }
      end

      def normalize_schema_to_json_schema(schema)
        # If it's already a proper JSON Schema format, extract the schema part
        if schema.is_a?(Hash) && schema.key?("type") && schema["type"] == "json_schema"
          # Extract the properties from the JSON Schema format
          return {
            type: "object",
            properties: schema["properties"] || {},
            required: schema["required"] || []
          }
        elsif schema.is_a?(Hash) && schema.key?(:type) && schema[:type] == "json_schema"
          # Handle symbol keys
          return {
            type: "object",
            properties: schema[:properties] || {},
            required: schema[:required] || []
          }
        end

        # If it's already a proper JSON Schema (has type property), return as-is
        return schema if schema.is_a?(Hash) && (schema.key?("type") || schema.key?(:type))

        # If we get here, the schema is not in the expected format
        raise ArgumentError, "Invalid schema format. Please use JSON Schema format with 'type: \"json_schema\"'"
      end

      def setup_client
        Faraday.new(url: ANTHROPIC_API_URL) do |f|
          f.options.timeout = @timeout
          f.request :json
          f.response :json
          f.adapter Faraday.default_adapter
          @base_headers.each { |key, value| f.headers[key] = value }
        end
      end

      def handle_tool_response(response, _schema)
        if response.status == 200
          response_body = response.body
          content = response_body["content"]

          raise ParseError, "Unexpected Anthropic response format: content is not an array" unless content.is_a?(Array)

          # Look for the tool_use block in the response
          tool_use_block = content.find { |block| block["type"] == "tool_use" }

          raise ParseError, "No tool_use block found in Claude's response" unless tool_use_block

          unless tool_use_block["name"] == "extract_cv_data"
            raise ParseError, "Unexpected tool used: #{tool_use_block["name"]}"
          end

          # The tool input should already be structured according to our schema
          extracted_data = tool_use_block["input"]

          raise ParseError, "Tool input is not a hash/object as expected" unless extracted_data.is_a?(Hash)

          extracted_data

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

      protected

      def setup_http_client
        super
        @base_headers["x-api-key"] = @api_key
        @base_headers["anthropic-version"] = ANTHROPIC_API_VERSION
      end
    end
  end
end
