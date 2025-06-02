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
      DEFAULT_MODEL = "gpt-4o-mini"

      def initialize(config)
        super
        @api_key = @config.api_key
        @timeout = @config.timeout || 60
        @base_headers = {
          "Authorization" => "Bearer #{@api_key}",
          "User-Agent" => "cv-parser-ruby/#{CvParser::VERSION}",
          **@config.provider_options.fetch(:headers, {})
        }
      end

      def extract_data(output_schema:, file_path: nil)
        raise ArgumentError, "File_path must be provided" unless file_path

        # Validate that we have a proper JSON Schema format
        unless output_schema.is_a?(Hash) &&
               ((output_schema.key?("type") && output_schema["type"] == "json_schema") ||
                (output_schema.key?(:type) && output_schema[:type] == "json_schema"))
          raise ArgumentError, "The OpenAI provider requires a JSON Schema format with 'type: \"json_schema\"'"
        end

        # File upload approach using Responses API
        validate_file_exists!(file_path)
        validate_file_readable!(file_path)

        # Convert DOCX to PDF if necessary
        processed_file_path = convert_to_pdf_if_needed(file_path)

        file_id = upload_file(processed_file_path)
        response = create_response_with_file(file_id, output_schema)

        # Clean up temporary PDF file if we created one
        cleanup_temp_file(processed_file_path, file_path)

        # Parse the response from the Responses API
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

        # Read file content and determine MIME type
        file_content = File.read(file_path, mode: "rb")
        mime_type = MIME::Types.type_for(file_path).first&.content_type || "application/octet-stream"
        filename = File.basename(file_path)

        # Create multipart form data
        boundary = "----cv-parser-#{SecureRandom.hex(16)}"
        form_data = build_multipart_form_data(file_content, filename, mime_type, boundary)

        request = Net::HTTP::Post.new(uri)
        request.body = form_data
        request["Content-Type"] = "multipart/form-data; boundary=#{boundary}"
        @base_headers.each { |key, value| request[key] = value }

        response = make_http_request(uri, request)

        if response.code.to_i == 200
          result = JSON.parse(response.body)
          result["id"]
        else
          handle_error_response(response, "file upload")
        end
      rescue StandardError => e
        raise APIError, "OpenAI API error during file upload: #{e.message}"
      end

      private

      def create_response_with_file(file_id, schema)
        uri = URI(API_RESPONSES_URL)

        payload = {
          model: @config.model || DEFAULT_MODEL,
          input: build_file_input_for_responses_api(file_id),
          text: {
            format: {
              type: "json_schema",
              name: "cv_data_extraction",
              schema: schema_to_json_schema(schema)
            }
          }
        }

        make_responses_api_request(uri, payload)
      end

      def schema_to_json_schema(schema)
        # If it's already a proper JSON Schema format, extract the schema part
        if schema.is_a?(Hash) && schema.key?("type") && schema["type"] == "json_schema"
          # Extract the properties from the JSON Schema format and ensure additionalProperties is set
          properties = schema["properties"] || {}
          processed_properties = ensure_additional_properties(properties)
          return {
            type: "object",
            properties: processed_properties,
            required: processed_properties.keys,
            additionalProperties: false
          }
        elsif schema.is_a?(Hash) && schema.key?(:type) && schema[:type] == "json_schema"
          # Handle symbol keys
          properties = schema[:properties] || {}
          processed_properties = ensure_additional_properties(properties)
          return {
            type: "object",
            properties: processed_properties,
            required: processed_properties.keys,
            additionalProperties: false
          }
        end

        # If we get here, the schema is not in the expected format
        raise ArgumentError, "Invalid schema format. Please use JSON Schema format with 'type: \"json_schema\"'"
      end

      def ensure_additional_properties(properties)
        result = {}
        properties.each do |key, value|
          if value.is_a?(Hash)
            if value["type"] == "object" || value[:type] == "object"
              # Ensure object types have additionalProperties set to false and all properties are required
              nested_props = value["properties"] || value[:properties] || {}
              processed_nested_props = ensure_additional_properties(nested_props)
              result[key] = value.merge(
                additionalProperties: false,
                properties: processed_nested_props,
                required: processed_nested_props.keys
              )
            elsif value["type"] == "array" || value[:type] == "array"
              # Handle array items
              items = value["items"] || value[:items]
              if items.is_a?(Hash) && (items["type"] == "object" || items[:type] == "object")
                nested_props = items["properties"] || items[:properties] || {}
                processed_nested_props = ensure_additional_properties(nested_props)
                updated_items = items.merge(
                  additionalProperties: false,
                  properties: processed_nested_props,
                  required: processed_nested_props.keys
                )
                result[key] = value.merge(items: updated_items)
              else
                result[key] = value
              end
            else
              result[key] = value
            end
          else
            result[key] = value
          end
        end
        result
      end

      def make_responses_api_request(uri, payload)
        request = Net::HTTP::Post.new(uri)
        request.body = payload.to_json
        request["Content-Type"] = "application/json"
        @base_headers.each { |key, value| request[key] = value }

        response = make_http_request(uri, request)

        if response.code.to_i == 200
          JSON.parse(response.body)
        else
          handle_error_response(response, "responses API")
        end
      end

      def make_http_request(uri, request)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.read_timeout = @timeout
        http.open_timeout = @timeout

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
        error_body = response.body
        error_info = begin
          JSON.parse(error_body)
        rescue JSON::ParserError
          { "error" => { "message" => error_body } }
        end

        error_message = error_info.dig("error", "message") || "Unknown error"

        case response.code.to_i
        when 429
          raise RateLimitError, "OpenAI rate limit exceeded during #{context}: #{error_message}"
        when 400..499
          raise APIError, "OpenAI API client error during #{context} (#{response.code}): #{error_message}"
        when 500..599
          raise APIError, "OpenAI API server error during #{context} (#{response.code}): #{error_message}"
        else
          raise APIError, "OpenAI API error during #{context} (#{response.code}): #{error_message}"
        end
      end

      def handle_http_error(error)
        if error.message.include?("rate limit") || error.message.include?("429")
          raise RateLimitError, "OpenAI rate limit exceeded: #{error.message}"
        end

        raise APIError, "OpenAI API error: #{error.message}"
      end

      def build_multipart_form_data(file_content, filename, mime_type, boundary)
        form_data = ""

        # Add file field
        form_data += "--#{boundary}\r\n"
        form_data += "Content-Disposition: form-data; name=\"file\"; filename=\"#{filename}\"\r\n"
        form_data += "Content-Type: #{mime_type}\r\n\r\n"
        form_data += file_content
        form_data += "\r\n"

        # Add purpose field
        form_data += "--#{boundary}\r\n"
        form_data += "Content-Disposition: form-data; name=\"purpose\"\r\n\r\n"
        form_data += "assistants"
        form_data += "\r\n"

        # End boundary
        form_data += "--#{boundary}--\r\n"

        form_data
      end
    end
  end
end
