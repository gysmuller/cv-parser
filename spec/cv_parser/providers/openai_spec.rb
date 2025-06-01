# frozen_string_literal: true

require "spec_helper"

RSpec.describe CvParser::Providers::OpenAI do
  let(:config) do
    config = CvParser::Configuration.new
    config.configure_openai(access_token: "fake-api-key")
    config.model = "gpt-4o-mini"
    config
  end

  let(:provider) { described_class.new(config) }
  let(:sample_content) { "John Doe\nEmail: john@example.com\nExperience: 5 years as Software Engineer" }
  let(:output_schema) do
    {
      name: "string",
      email: "string",
      experience: [{ title: "string", years: "string" }]
    }
  end

  describe "#extract_data" do
    before do
      # Mock HTTP requests
      @mock_http = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:new).and_return(@mock_http)
      allow(@mock_http).to receive(:use_ssl=)
      allow(@mock_http).to receive(:read_timeout=)
      allow(@mock_http).to receive(:open_timeout=)
    end

    context "with successful API response" do
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
        expect(@mock_http).to receive(:request) do |request|
          # Verify the request body structure
          body = JSON.parse(request.body)
          expect(body["model"]).to eq("gpt-4o-mini")
          expect(body["temperature"]).to eq(0.1)
          expect(body["text"]["format"]["type"]).to eq("json_schema")
          expect(body["text"]["format"]["name"]).to eq("cv_data_extraction")
          expect(body["text"]["format"]).to have_key("schema")

          # For text input, expect the new format
          expect(body["input"]).to be_an(Array)
          expect(body["input"].first["role"]).to eq("user")
          expect(body["input"].first["content"].first["type"]).to eq("input_text")

          mock_http_response
        end

        result = provider.extract_data(
          content: sample_content,
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
      let(:rate_limit_response) do
        response = instance_double(Net::HTTPResponse)
        allow(response).to receive(:code).and_return("429")
        allow(response).to receive(:body).and_return('{"error":{"message":"Rate limit exceeded"}}')
        response
      end

      it "raises a RateLimitError" do
        expect(@mock_http).to receive(:request).and_return(rate_limit_response)

        expect do
          provider.extract_data(
            content: sample_content,
            output_schema: output_schema
          )
        end.to raise_error(CvParser::RateLimitError, /OpenAI rate limit exceeded/)
      end
    end

    context "with other API error" do
      let(:error_response) do
        response = instance_double(Net::HTTPResponse)
        allow(response).to receive(:code).and_return("400")
        allow(response).to receive(:body).and_return('{"error":{"message":"Invalid request"}}')
        response
      end

      it "raises an APIError" do
        expect(@mock_http).to receive(:request).and_return(error_response)

        expect do
          provider.extract_data(
            content: sample_content,
            output_schema: output_schema
          )
        end.to raise_error(CvParser::APIError, /OpenAI API client error/)
      end
    end

    context "with invalid JSON response" do
      let(:invalid_json_response) do
        response = instance_double(Net::HTTPResponse)
        allow(response).to receive(:code).and_return("200")
        allow(response).to receive(:body).and_return('{"output":[{"type":"message","content":[{"type":"text","text":"This is not valid JSON"}]}]}')
        response
      end

      it "raises a ParseError" do
        expect(@mock_http).to receive(:request).and_return(invalid_json_response)

        expect do
          provider.extract_data(
            content: sample_content,
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
end
