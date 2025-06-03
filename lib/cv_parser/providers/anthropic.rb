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
      TOOL_NAME = "extract_cv_data"

      # HTTP Status codes
      HTTP_OK = 200
      HTTP_BAD_REQUEST = 400
      HTTP_UNAUTHORIZED = 401
      HTTP_TOO_MANY_REQUESTS = 429

      def initialize(config)
        super
        @client = setup_client
      end

      def extract_data(output_schema:, file_path: nil)
        validate_inputs!(output_schema, file_path)

        processed_file_path = prepare_file(file_path)
        base64_content = encode_file_to_base64(processed_file_path)

        response = make_api_request(output_schema, base64_content)

        cleanup_temp_file(processed_file_path, file_path)

        handle_tool_response(response, output_schema)
      rescue Faraday::Error => e
        raise APIError, "Anthropic API connection error: #{e.message}"
      end

      private

      def validate_inputs!(output_schema, file_path)
        raise ArgumentError, "File_path must be provided" unless file_path

        validate_schema_format!(output_schema)
        validate_file_exists!(file_path)
        validate_file_readable!(file_path)
      end

      def validate_schema_format!(output_schema)
        return if valid_json_schema_format?(output_schema)

        raise ArgumentError, "The Anthropic provider requires a JSON Schema format with 'type: \"json_schema\"'"
      end

      def valid_json_schema_format?(schema)
        schema.is_a?(Hash) &&
          ((schema.key?("type") && schema["type"] == "json_schema") ||
           (schema.key?(:type) && schema[:type] == "json_schema"))
      end

      def prepare_file(file_path)
        convert_to_pdf_if_needed(file_path)
      end

      def encode_file_to_base64(file_path)
        pdf_content = File.read(file_path)
        Base64.strict_encode64(pdf_content)
      end

      def make_api_request(output_schema, base64_content)
        extraction_tool = build_extraction_tool(output_schema)

        @client.post do |req|
          req.headers["Content-Type"] = "application/json"
          req.body = build_request_body(output_schema, extraction_tool, base64_content).to_json
        end
      end

      def build_request_body(output_schema, extraction_tool, base64_content)
        {
          model: @config.model || DEFAULT_MODEL,
          max_tokens: @config.max_tokens,
          temperature: @config.temperature,
          system: build_system_prompt,
          tools: [extraction_tool],
          tool_choice: { type: "tool", name: TOOL_NAME },
          messages: [build_message(output_schema, base64_content)]
        }
      end

      def build_message(output_schema, base64_content)
        {
          role: "user",
          content: [
            build_document_content(base64_content),
            build_text_content(output_schema)
          ]
        }
      end

      def build_document_content(base64_content)
        {
          type: "document",
          source: {
            type: "base64",
            media_type: "application/pdf",
            data: base64_content
          }
        }
      end

      def build_text_content(output_schema)
        {
          type: "text",
          text: build_extraction_prompt(output_schema)
        }
      end

      def build_extraction_tool(output_schema)
        json_schema = normalize_schema_to_json_schema(output_schema)

        {
          name: TOOL_NAME,
          description: "Extract structured data from a CV/resume document according to the provided schema. Always use this tool to return the extracted data in the exact format specified by the schema.",
          input_schema: json_schema
        }
      end

      def normalize_schema_to_json_schema(schema)
        # Extract the properties from the JSON Schema format
        properties = extract_properties_from_schema(schema)
        required = extract_required_from_schema(schema)

        {
          type: "object",
          properties: properties,
          required: required
        }
      end

      def extract_properties_from_schema(schema)
        if schema.key?("properties")
          schema["properties"]
        elsif schema.key?(:properties)
          schema[:properties]
        else
          {}
        end
      end

      def extract_required_from_schema(schema)
        if schema.key?("required")
          schema["required"]
        elsif schema.key?(:required)
          schema[:required]
        else
          []
        end
      end

      def handle_tool_response(response, _schema)
        case response.status
        when HTTP_OK
          extract_tool_data_from_response(response)
        when HTTP_TOO_MANY_REQUESTS
          handle_rate_limit_error(response)
        when HTTP_UNAUTHORIZED
          raise AuthenticationError, "Invalid API key or unauthorized access"
        when HTTP_BAD_REQUEST
          handle_bad_request_error(response)
        else
          handle_generic_api_error(response)
        end
      rescue JSON::ParserError => e
        raise ParseError, "Failed to parse Anthropic response as JSON: #{e.message}"
      end

      def extract_tool_data_from_response(response)
        response_body = response.body
        content = response_body["content"]

        raise ParseError, "Unexpected Anthropic response format: content is not an array" unless content.is_a?(Array)

        tool_use_block = find_tool_use_block(content)
        validate_tool_use_block(tool_use_block)

        extracted_data = tool_use_block["input"]
        raise ParseError, "Tool input is not a hash/object as expected" unless extracted_data.is_a?(Hash)

        extracted_data
      end

      def find_tool_use_block(content)
        content.find { |block| block["type"] == "tool_use" }
      end

      def validate_tool_use_block(tool_use_block)
        raise ParseError, "No tool_use block found in Claude's response" unless tool_use_block

        return if tool_use_block["name"] == TOOL_NAME

        raise ParseError, "Unexpected tool used: #{tool_use_block["name"]}"
      end

      def handle_rate_limit_error(response)
        retry_after = response.headers["retry-after"]
        message = retry_after ? "Rate limit exceeded, retry after #{retry_after} seconds" : "Rate limit exceeded"
        raise RateLimitError, message
      end

      def handle_bad_request_error(response)
        error_message = response.body.dig("error", "message") || "Bad request"
        raise InvalidRequestError, "Anthropic API error: #{error_message}"
      end

      def handle_generic_api_error(response)
        error_type = response.body.dig("error", "type") || "unknown"
        error_message = response.body.dig("error", "message") || "Unknown error"
        raise APIError, "Anthropic API error: #{response.status} - #{error_type} - #{error_message}"
      end

      protected

      # Sets up the Faraday HTTP client with proper headers and configuration
      def setup_http_client
        super
        @base_headers["x-api-key"] = @api_key
        @base_headers["anthropic-version"] = ANTHROPIC_API_VERSION
      end

      # Configures and returns a Faraday client instance
      def setup_client
        Faraday.new(url: ANTHROPIC_API_URL) do |f|
          f.options.timeout = @timeout
          f.request :json
          f.response :json
          f.adapter Faraday.default_adapter
          @base_headers.each { |key, value| f.headers[key] = value }
        end
      end
    end
  end
end
