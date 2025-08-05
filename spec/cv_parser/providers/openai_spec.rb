# frozen_string_literal: true

require "spec_helper"

# rubocop:disable Metrics/BlockLength

RSpec.describe CvParser::Providers::OpenAI do
  let(:config) do
    config = CvParser::Configuration.new
    config.provider = :openai
    config.api_key = "fake-api-key"
    config.model = "gpt-4o-mini"
    config
  end

  let(:provider) { described_class.new(config) }
  let(:sample_file_path) { "/tmp/test.pdf" }
  let(:output_schema) do
    {
      type: "json_schema",
      properties: {
        name: { type: "string" },
        email: { type: "string" },
        experience: {
          type: "array",
          items: {
            type: "object",
            properties: {
              title: { type: "string" },
              years: { type: "string" }
            }
          }
        }
      }
    }
  end

  describe "#extract_data" do
    before do
      # Mock file operations
      allow(File).to receive(:exist?).with(sample_file_path).and_return(true)
      allow(File).to receive(:readable?).with(sample_file_path).and_return(true)
      allow(File).to receive(:read).with(sample_file_path, mode: "rb").and_return("fake pdf content")
      allow(File).to receive(:basename).with(sample_file_path).and_return("test.pdf")
      allow(provider).to receive(:convert_to_pdf_if_needed).and_return(sample_file_path)
      allow(provider).to receive(:cleanup_temp_file)

      # Mock MIME type detection
      mime_type = instance_double(MIME::Type)
      allow(mime_type).to receive(:content_type).and_return("application/pdf")
      allow(MIME::Types).to receive(:type_for).with(sample_file_path).and_return([mime_type])

      # Mock HTTP requests
      @mock_http = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:new).and_return(@mock_http)
      allow(@mock_http).to receive(:use_ssl=)
      allow(@mock_http).to receive(:read_timeout=)
      allow(@mock_http).to receive(:open_timeout=)
    end

    context "with successful API response" do
      let(:upload_response_body) do
        { "id" => "file-abc123" }.to_json
      end

      let(:mock_upload_response) do
        response = instance_double(Net::HTTPResponse)
        allow(response).to receive(:code).and_return("200")
        allow(response).to receive(:body).and_return(upload_response_body)
        response
      end

      let(:mock_response_body) do
        {
          "output" => [
            {
              "type" => "message",
              "content" => [
                {
                  "type" => "text",
                  "text" => '{"name":"John Doe","email":"john@example.com","experience":[{"title":"Software Engineer","years":"5 years"}]}'
                }
              ]
            }
          ]
        }.to_json
      end

      let(:mock_http_response) do
        response = instance_double(Net::HTTPResponse)
        allow(response).to receive(:code).and_return("200")
        allow(response).to receive(:body).and_return(mock_response_body)
        response
      end

      it "returns structured data from the API response" do
        # First expect a file upload
        expect(@mock_http).to receive(:request).and_return(mock_upload_response)

        # Then expect a request to the Responses API
        expect(@mock_http).to receive(:request) do |request|
          # Verify the request body structure
          body = JSON.parse(request.body)
          expect(body["model"]).to eq("gpt-4o-mini")
          expect(body["input"]).to be_an(Array)
          expect(body["input"].first["role"]).to eq("user")
          expect(body["input"].first["content"].first["type"]).to eq("input_text")
          expect(body["input"].first["content"][1]["type"]).to eq("input_file")
          expect(body["input"].first["content"][1]["file_id"]).to eq("file-abc123")

          mock_http_response
        end

        result = provider.extract_data(
          file_path: sample_file_path,
          output_schema: output_schema
        )

        expect(result).to be_a(Hash)
        expect(result["name"]).to eq("John Doe")
        expect(result["email"]).to eq("john@example.com")
        expect(result["experience"]).to be_an(Array)
        expect(result["experience"].first["title"]).to eq("Software Engineer")
        expect(result["experience"].first["years"]).to eq("5 years")
      end
    end

    context "with API rate limit error" do
      let(:upload_response_body) do
        { "id" => "file-abc123" }.to_json
      end

      let(:mock_upload_response) do
        response = instance_double(Net::HTTPResponse)
        allow(response).to receive(:code).and_return("200")
        allow(response).to receive(:body).and_return(upload_response_body)
        response
      end

      let(:rate_limit_response) do
        response = instance_double(Net::HTTPResponse)
        allow(response).to receive(:code).and_return("429")
        allow(response).to receive(:body).and_return('{"error":{"message":"Rate limit exceeded"}}')
        response
      end

      it "raises a RateLimitError" do
        # First expect a file upload
        expect(@mock_http).to receive(:request).and_return(mock_upload_response)

        # Then expect a rate limit error
        expect(@mock_http).to receive(:request).and_return(rate_limit_response)

        expect do
          provider.extract_data(
            file_path: sample_file_path,
            output_schema: output_schema
          )
        end.to raise_error(CvParser::RateLimitError, /OpenAI rate limit exceeded/)
      end
    end

    context "with other API error" do
      let(:upload_response_body) do
        { "id" => "file-abc123" }.to_json
      end

      let(:mock_upload_response) do
        response = instance_double(Net::HTTPResponse)
        allow(response).to receive(:code).and_return("200")
        allow(response).to receive(:body).and_return(upload_response_body)
        response
      end

      let(:error_response) do
        response = instance_double(Net::HTTPResponse)
        allow(response).to receive(:code).and_return("400")
        allow(response).to receive(:body).and_return('{"error":{"message":"Invalid request"}}')
        response
      end

      it "raises an APIError" do
        # First expect a file upload
        expect(@mock_http).to receive(:request).and_return(mock_upload_response)

        # Then expect an API error
        expect(@mock_http).to receive(:request).and_return(error_response)

        expect do
          provider.extract_data(
            file_path: sample_file_path,
            output_schema: output_schema
          )
        end.to raise_error(CvParser::APIError, /OpenAI API client error/)
      end
    end

    context "with invalid JSON response" do
      let(:upload_response_body) do
        { "id" => "file-abc123" }.to_json
      end

      let(:mock_upload_response) do
        response = instance_double(Net::HTTPResponse)
        allow(response).to receive(:code).and_return("200")
        allow(response).to receive(:body).and_return(upload_response_body)
        response
      end

      let(:invalid_json_response) do
        response = instance_double(Net::HTTPResponse)
        allow(response).to receive(:code).and_return("200")
        allow(response).to receive(:body).and_return('{"output":[{"type":"message","content":[{"type":"text","text":"This is not valid JSON"}]}]}')
        response
      end

      it "raises a ParseError" do
        # First expect a file upload
        expect(@mock_http).to receive(:request).and_return(mock_upload_response)

        # Then expect a response with invalid JSON
        expect(@mock_http).to receive(:request).and_return(invalid_json_response)

        expect do
          provider.extract_data(
            file_path: sample_file_path,
            output_schema: output_schema
          )
        end.to raise_error(CvParser::ParseError, /Failed to parse OpenAI response as JSON/)
      end
    end
  end

  describe "#upload_file" do
    let(:file_path) { "/tmp/test.pdf" }
    let(:file_content) { "fake pdf content" }

    before do
      # Mock file operations
      allow(File).to receive(:read).with(file_path, mode: "rb").and_return(file_content)
      allow(File).to receive(:basename).and_call_original
      allow(File).to receive(:basename).with(file_path).and_return("test.pdf")
      allow(provider).to receive(:validate_file_exists!)
      allow(provider).to receive(:validate_file_readable!)

      # Mock MIME type detection
      mime_type = instance_double(MIME::Type)
      allow(mime_type).to receive(:content_type).and_return("application/pdf")
      allow(MIME::Types).to receive(:type_for).with(file_path).and_return([mime_type])

      # Mock HTTP
      @mock_http = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:new).and_return(@mock_http)
      allow(@mock_http).to receive(:use_ssl=)
      allow(@mock_http).to receive(:read_timeout=)
      allow(@mock_http).to receive(:open_timeout=)
    end

    context "with successful file upload" do
      let(:upload_response_body) do
        { "id" => "file-abc123" }.to_json
      end

      let(:mock_upload_response) do
        response = instance_double(Net::HTTPResponse)
        allow(response).to receive(:code).and_return("200")
        allow(response).to receive(:body).and_return(upload_response_body)
        response
      end

      it "returns the file ID" do
        expect(@mock_http).to receive(:request).and_return(mock_upload_response)

        result = provider.upload_file(file_path)
        expect(result).to eq("file-abc123")
      end
    end

    context "with upload error" do
      let(:error_response) do
        response = instance_double(Net::HTTPResponse)
        allow(response).to receive(:code).and_return("400")
        allow(response).to receive(:body).and_return('{"error":{"message":"Invalid file"}}')
        response
      end

      it "raises an APIError" do
        expect(@mock_http).to receive(:request).and_return(error_response)

        expect do
          provider.upload_file(file_path)
        end.to raise_error(CvParser::APIError, /OpenAI API client error/)
      end
    end
  end

  describe "#extract_data with text files" do
    let(:txt_file_path) { fixture_path("sample_resume.txt") }
    let(:md_file_path) { fixture_path("sample_resume.md") }
    let(:empty_file_path) { fixture_path("empty_resume.txt") }

    before do
      allow(File).to receive(:exist?).with(txt_file_path).and_return(true)
      allow(File).to receive(:readable?).with(txt_file_path).and_return(true)
      allow(File).to receive(:exist?).with(md_file_path).and_return(true)
      allow(File).to receive(:readable?).with(md_file_path).and_return(true)
    end

    context "with successful text processing" do
      it "processes txt files without file upload" do
        response_body = {
          "output" => [
            {
              "type" => "message",
              "content" => [
                {
                  "type" => "text",
                  "text" => '{"name":"John Doe","email":"john@example.com"}'
                }
              ]
            }
          ]
        }

        http_response = instance_double(Net::HTTPResponse)
        allow(http_response).to receive(:code).and_return("200")
        allow(http_response).to receive(:body).and_return(response_body.to_json)

        allow_any_instance_of(Net::HTTP).to receive(:request).and_return(http_response)

        result = provider.extract_data(output_schema: output_schema, file_path: txt_file_path)

        expect(result).to include(
          "name" => "John Doe",
          "email" => "john@example.com"
        )
      end

      it "processes markdown files correctly" do
        response_body = {
          "output" => [
            {
              "type" => "message",
              "content" => [
                {
                  "type" => "output_text",
                  "text" => '{"name":"John Doe"}'
                }
              ]
            }
          ]
        }

        http_response = instance_double(Net::HTTPResponse)
        allow(http_response).to receive(:code).and_return("200")
        allow(http_response).to receive(:body).and_return(response_body.to_json)

        allow_any_instance_of(Net::HTTP).to receive(:request).and_return(http_response)

        result = provider.extract_data(output_schema: output_schema, file_path: md_file_path)
        expect(result).to include("name" => "John Doe")
      end
    end

    context "with empty text file" do
      before do
        allow(File).to receive(:exist?).with(empty_file_path).and_return(true)
        allow(File).to receive(:readable?).with(empty_file_path).and_return(true)
      end

      it "raises EmptyTextFileError" do
        expect do
          provider.extract_data(output_schema: output_schema, file_path: empty_file_path)
        end.to raise_error(CvParser::EmptyTextFileError)
      end
    end
  end
end

# rubocop:enable Metrics/BlockLength
