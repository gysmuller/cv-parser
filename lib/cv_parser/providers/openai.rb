# frozen_string_literal: true

require "net/http"
require "uri"
require "json"
require "mime/types"
require "securerandom"
require "timeout"
require_relative "../pdf_converter"

module CvParser
  module Providers
    class OpenAI < Base
      API_BASE_URL = "https://api.openai.com/v1"
      API_FILE_URL = "https://api.openai.com/v1/files"
      API_RESPONSES_URL = "https://api.openai.com/v1/responses"
      DEFAULT_MODEL = "gpt-4.1-mini"

      # HTTP Status codes
      HTTP_OK = 200
      HTTP_BAD_REQUEST = 400
      HTTP_UNAUTHORIZED = 401
      HTTP_TOO_MANY_REQUESTS = 429
      HTTP_CLIENT_ERROR_START = 400
      HTTP_CLIENT_ERROR_END = 499
      HTTP_SERVER_ERROR_START = 500
      HTTP_SERVER_ERROR_END = 599

      # Constants
      SCHEMA_NAME = "cv_data_extraction"
      FILE_PURPOSE = "assistants"
      MULTIPART_BOUNDARY_PREFIX = "----cv-parser-"
      DEFAULT_MIME_TYPE = "application/octet-stream"

      def initialize(config)
        super
        @api_key = @config.api_key
        @timeout = @config.timeout || 60
        @client = setup_client
      end

      def extract_data(output_schema:, file_path: nil)
        validate_inputs!(output_schema, file_path)

        processed_file_path = prepare_file(file_path)
        file_id = upload_file(processed_file_path)
        response = create_response_with_file(file_id, output_schema)

        cleanup_temp_file(processed_file_path, file_path)

        parse_response_output(response)
      rescue Timeout::Error => e
        raise APIError, "OpenAI API timeout: #{e.message}"
      rescue Net::HTTPError => e
        handle_http_error(e)
      rescue JSON::ParserError => e
        raise ParseError, "Failed to parse OpenAI response as JSON: #{e.message}"
      end

      def upload_file(file_path)
        uri = URI(API_FILE_URL)
        file_content, mime_type, filename = prepare_file_upload_data(file_path)

        boundary = generate_boundary
        form_data = build_multipart_form_data(file_content, filename, mime_type, boundary)

        request = build_upload_request(uri, form_data, boundary)
        response = make_http_request(uri, request)

        handle_upload_response(response)
      rescue StandardError => e
        raise APIError, "OpenAI API error during file upload: #{e.message}"
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

        raise ArgumentError, "The OpenAI provider requires a JSON Schema format with 'type: \"json_schema\"'"
      end

      def valid_json_schema_format?(schema)
        schema.is_a?(Hash) &&
          ((schema.key?("type") && schema["type"] == "json_schema") ||
           (schema.key?(:type) && schema[:type] == "json_schema"))
      end

      def prepare_file(file_path)
        convert_to_pdf_if_needed(file_path)
      end

      def prepare_file_upload_data(file_path)
        file_content = File.read(file_path, mode: "rb")
        mime_type = MIME::Types.type_for(file_path).first&.content_type || DEFAULT_MIME_TYPE
        filename = File.basename(file_path)

        [file_content, mime_type, filename]
      end

      def generate_boundary
        "#{MULTIPART_BOUNDARY_PREFIX}#{SecureRandom.hex(16)}"
      end

      def build_upload_request(uri, form_data, boundary)
        request = Net::HTTP::Post.new(uri)
        request.body = form_data
        request["Content-Type"] = "multipart/form-data; boundary=#{boundary}"
        @base_headers.each { |key, value| request[key] = value }
        request
      end

      def handle_upload_response(response)
        if response.code.to_i == HTTP_OK
          result = JSON.parse(response.body)
          result["id"]
        else
          handle_error_response(response, "file upload")
        end
      end

      def setup_client
        {
          http_class: Net::HTTP,
          timeout: @timeout,
          headers: @base_headers
        }
      end

      def create_response_with_file(file_id, schema)
        uri = URI(API_RESPONSES_URL)
        payload = build_response_payload(file_id, schema)
        make_responses_api_request(uri, payload)
      end

      def build_response_payload(file_id, schema)
        {
          model: @config.model || DEFAULT_MODEL,
          input: build_file_input_for_responses_api(file_id),
          text: {
            format: {
              type: "json_schema",
              name: SCHEMA_NAME,
              schema: schema_to_json_schema(schema)
            }
          }
        }
      end

      def schema_to_json_schema(schema)
        properties = extract_properties_from_schema(schema)
        processed_properties = ensure_additional_properties(properties)

        {
          type: "object",
          properties: processed_properties,
          required: processed_properties.keys,
          additionalProperties: false
        }
      end

      def extract_properties_from_schema(schema)
        if schema.key?("properties")
          schema["properties"]
        elsif schema.key?(:properties)
          schema[:properties]
        else
          raise ArgumentError, "Invalid schema format. Please use JSON Schema format with 'type: \"json_schema\"'"
        end
      end

      def ensure_additional_properties(properties)
        result = {}
        properties.each do |key, value|
          result[key] = process_property_value(value)
        end
        result
      end

      def process_property_value(value)
        return value unless value.is_a?(Hash)

        case property_type(value)
        when "object"
          process_object_property(value)
        when "array"
          process_array_property(value)
        else
          value
        end
      end

      def property_type(value)
        value["type"] || value[:type]
      end

      def process_object_property(value)
        nested_props = value["properties"] || value[:properties] || {}
        processed_nested_props = ensure_additional_properties(nested_props)

        value.merge(
          additionalProperties: false,
          properties: processed_nested_props,
          required: processed_nested_props.keys
        )
      end

      def process_array_property(value)
        items = value["items"] || value[:items]
        return value unless items.is_a?(Hash) && property_type(items) == "object"

        nested_props = items["properties"] || items[:properties] || {}
        processed_nested_props = ensure_additional_properties(nested_props)
        updated_items = items.merge(
          additionalProperties: false,
          properties: processed_nested_props,
          required: processed_nested_props.keys
        )

        value.merge(items: updated_items)
      end

      def make_responses_api_request(uri, payload)
        request = build_json_request(uri, payload)
        response = make_http_request(uri, request)
        handle_responses_api_response(response)
      end

      def build_json_request(uri, payload)
        request = Net::HTTP::Post.new(uri)
        request.body = payload.to_json
        request["Content-Type"] = "application/json"
        @base_headers.each { |key, value| request[key] = value }
        request
      end

      def handle_responses_api_response(response)
        if response.code.to_i == HTTP_OK
          JSON.parse(response.body)
        else
          handle_error_response(response, "responses API")
        end
      end

      def make_http_request(uri, request)
        http = @client[:http_class].new(uri.host, uri.port)
        http.use_ssl = true
        http.read_timeout = @client[:timeout]
        http.open_timeout = @client[:timeout]

        http.request(request)
      end

      def build_file_input_for_responses_api(file_id)
        [
          {
            role: "user",
            content: [
              {
                type: "input_text",
                text: build_extraction_prompt
              },
              {
                type: "input_file",
                file_id: file_id
              }
            ]
          }
        ]
      end

      def parse_response_output(response)
        # Extract content from Responses API format
        output = response["output"]
        return nil unless output&.is_a?(Array) && !output.empty?

        # Look for message with text content
        text_content = nil

        output.each do |item|
          if item.is_a?(Hash)
            if item["type"] == "message" && item["content"]
              item["content"].each do |content_item|
                if content_item.is_a?(Hash)
                  if content_item["type"] == "text"
                    text_content = content_item["text"]
                    break
                  elsif content_item["type"] == "output_text"
                    text_content = content_item["text"]
                    break
                  end
                end
              end
            elsif item["type"] == "text" && item["text"]
              text_content = item["text"]
            end
          end
          break if text_content
        end

        return nil unless text_content

        # Parse the JSON content
        begin
          JSON.parse(text_content)
        rescue JSON::ParserError => e
          # If direct parsing fails, try to extract JSON from text
          raise ParseError, "Failed to parse OpenAI response as JSON: #{e.message}" unless text_content =~ /\{.*\}/m

          json_text = text_content.match(/\{.*\}/m)[0]
          JSON.parse(json_text)
        end
      end

      def handle_error_response(response, context)
        error_info = parse_error_body(response.body)
        error_message = error_info.dig("error", "message") || "Unknown error"
        status_code = response.code.to_i

        case status_code
        when HTTP_TOO_MANY_REQUESTS
          raise RateLimitError, "OpenAI rate limit exceeded during #{context}: #{error_message}"
        when HTTP_CLIENT_ERROR_START..HTTP_CLIENT_ERROR_END
          raise APIError, "OpenAI API client error during #{context} (#{status_code}): #{error_message}"
        when HTTP_SERVER_ERROR_START..HTTP_SERVER_ERROR_END
          raise APIError, "OpenAI API server error during #{context} (#{status_code}): #{error_message}"
        else
          raise APIError, "OpenAI API error during #{context} (#{status_code}): #{error_message}"
        end
      end

      def parse_error_body(error_body)
        JSON.parse(error_body)
      rescue JSON::ParserError
        { "error" => { "message" => error_body } }
      end

      def handle_http_error(error)
        raise RateLimitError, "OpenAI rate limit exceeded: #{error.message}" if rate_limit_error?(error)

        raise APIError, "OpenAI API error: #{error.message}"
      end

      def rate_limit_error?(error)
        error.message.include?("rate limit") || error.message.include?("429")
      end

      def build_multipart_form_data(file_content, filename, mime_type, boundary)
        form_data = ""
        form_data += build_file_field(file_content, filename, mime_type, boundary)
        form_data += build_purpose_field(boundary)
        form_data += build_end_boundary(boundary)
        form_data
      end

      def build_file_field(file_content, filename, mime_type, boundary)
        field = ""
        field += "--#{boundary}\r\n"
        field += "Content-Disposition: form-data; name=\"file\"; filename=\"#{filename}\"\r\n"
        field += "Content-Type: #{mime_type}\r\n\r\n"
        field += file_content
        field += "\r\n"
        field
      end

      def build_purpose_field(boundary)
        field = ""
        field += "--#{boundary}\r\n"
        field += "Content-Disposition: form-data; name=\"purpose\"\r\n\r\n"
        field += FILE_PURPOSE
        field += "\r\n"
        field
      end

      def build_end_boundary(boundary)
        "--#{boundary}--\r\n"
      end

      protected

      def setup_http_client
        super
        @base_headers["Authorization"] = "Bearer #{@api_key}"
      end
    end
  end
end
