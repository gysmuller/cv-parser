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

      def initialize(config)
        super
        @api_key = @config.api_key
        @timeout = @config.timeout || 60
        @pdf_converter = CvParser::PdfConverter.new
        @base_headers = {
          "Authorization" => "Bearer #{@api_key}",
          "User-Agent" => "cv-parser-ruby/#{CvParser::VERSION}",
          **@config.provider_options.fetch(:headers, {})
        }
      end

      def extract_data(output_schema:, content: nil, file_path: nil)
        if file_path
          # File upload approach using Responses API
          validate_file_exists!(file_path)
          validate_file_readable!(file_path)

          # Convert DOCX to PDF if necessary
          processed_file_path = convert_to_pdf_if_needed(file_path)

          file_id = upload_file(processed_file_path)
          response = create_response_with_file(file_id, output_schema)

          # Clean up temporary PDF file if we created one
          cleanup_temp_file(processed_file_path, file_path)
        elsif content
          # Text content approach using Responses API
          response = create_response_with_text(content, output_schema)
        else
          raise ArgumentError, "Either content or file_path must be provided"
        end

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
        uri = URI("#{API_BASE_URL}/files")

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
          # For other file types, let OpenAI handle them directly
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

      def create_response_with_file(file_id, schema)
        uri = URI("#{API_BASE_URL}/responses")

        payload = {
          model: @config.model || "gpt-4o-mini",
          input: build_file_input_for_responses_api(file_id, schema),
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

      def create_response_with_text(content, schema)
        uri = URI("#{API_BASE_URL}/responses")

        payload = {
          model: @config.model || "gpt-4.1-mini",
          input: build_text_input_for_responses_api(content, schema),
          text: {
            format: {
              type: "json_schema",
              name: "cv_data_extraction",
              schema: schema_to_json_schema(schema)
            }
          },
          temperature: 0.1
        }

        make_responses_api_request(uri, payload)
      end

      def schema_to_json_schema(schema)
        json_schema = {
          type: "object",
          properties: {},
          required: [],
          additionalProperties: false
        }

        schema.each do |key, value|
          if value == "string"
            json_schema[:properties][key] = { type: "string" }
            json_schema[:required] << key
          elsif %w[number integer].include?(value)
            json_schema[:properties][key] = { type: value }
            json_schema[:required] << key
          elsif value == "boolean"
            json_schema[:properties][key] = { type: "boolean" }
            json_schema[:required] << key
          elsif value.is_a?(Array)
            json_schema[:properties][key] = {
              type: "array",
              items: value.first.is_a?(Hash) ? schema_to_json_schema(value.first) : { type: "string" }
            }
            json_schema[:required] << key
          elsif value.is_a?(Hash)
            json_schema[:properties][key] = schema_to_json_schema(value)
            json_schema[:required] << key
          end
        end

        json_schema
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

      def build_file_input_for_responses_api(file_id, schema)
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

      def build_text_input_for_responses_api(content, schema)
        [
          {
            role: "user",
            content: [
              {
                type: "input_text",
                text: "#{build_extraction_prompt}\n\nDocument content:\n#{content}"
              }
            ]
          }
        ]
      end

      def build_extraction_prompt
        <<~PROMPT
          You are a CV parsing assistant. Extract structured information from the attached CV/Resume.

          Instructions:
          1. Extract all the requested fields from the CV.
          2. Maintain the exact structure defined in the schema.
          3. If information for a field is not available, use null or empty arrays as appropriate.
          4. For dates, use the format provided in the CV.
          5. Return only JSON without any additional explanations.
        PROMPT
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
    end
  end
end
