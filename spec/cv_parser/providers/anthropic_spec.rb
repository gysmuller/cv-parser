# frozen_string_literal: true

require "spec_helper"

RSpec.describe CvParser::Providers::Anthropic do
  let(:config) do
    config = CvParser::Configuration.new
    config.provider = :anthropic
    config.api_key = "fake-api-key"
    config.model = "claude-3-opus-20240229"
    config
  end

  let(:provider) { described_class.new(config) }
  let(:sample_file_path) { "example.pdf" }
  let(:output_schema) do
    {
      name: "string",
      email: "string",
      experience: [{ title: "string", years: "string" }]
    }
  end

  describe "#extract_data" do
    let(:api_url) { CvParser::Providers::Anthropic::ANTHROPIC_API_URL }

    context "with successful API response" do
      before do
        # Mock the Faraday response object to ensure it behaves like the real API
        # Need to mock the JSON parsing that happens in the provider
        allow_any_instance_of(Faraday::Connection).to receive(:post).and_return(
          instance_double(
            Faraday::Response,
            status: 200,
            body: {
              "id" => "msg_01234567",
              "type" => "message",
              "role" => "assistant",
              "model" => "claude-3-opus-20240229",
              "content" => [
                {
                  "type" => "text",
                  "text" => '{"name":"John Doe","email":"john@example.com","experience":[{"title":"Software Engineer","years":"5 years"}]}'
                }
              ]
            }
          )
        )
      end

      it "handles file path input with PDF processing" do
        pdf_content = "fake pdf content"
        base64_encoded_pdf = Base64.strict_encode64(pdf_content)

        # Mock file operations
        allow(provider).to receive(:validate_file_exists!)
        allow(provider).to receive(:validate_file_readable!)
        allow(provider).to receive(:convert_to_pdf_if_needed).and_return(sample_file_path)
        allow(File).to receive(:read).with(sample_file_path).and_return(pdf_content)
        allow(provider).to receive(:cleanup_temp_file)

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
      before do
        allow_any_instance_of(Faraday::Connection).to receive(:post).and_return(
          instance_double(
            Faraday::Response,
            status: 429,
            headers: { "retry-after" => "30" },
            body: { "error" => { "message" => "Rate limit exceeded" } }
          )
        )
      end

      it "raises a RateLimitError" do
        # Mock file operations for a file-based test
        allow(provider).to receive(:validate_file_exists!)
        allow(provider).to receive(:validate_file_readable!)
        allow(provider).to receive(:convert_to_pdf_if_needed).and_return(sample_file_path)
        allow(File).to receive(:read).with(sample_file_path).and_return("fake pdf content")
        allow(provider).to receive(:cleanup_temp_file)

        expect do
          provider.extract_data(
            file_path: sample_file_path,
            output_schema: output_schema
          )
        end.to raise_error(CvParser::RateLimitError, /Rate limit exceeded/)
      end
    end

    context "with authentication error" do
      before do
        allow_any_instance_of(Faraday::Connection).to receive(:post).and_return(
          instance_double(
            Faraday::Response,
            status: 401,
            body: { "error" => { "message" => "Invalid API key" } }
          )
        )
      end

      it "raises an AuthenticationError" do
        # Mock file operations for a file-based test
        allow(provider).to receive(:validate_file_exists!)
        allow(provider).to receive(:validate_file_readable!)
        allow(provider).to receive(:convert_to_pdf_if_needed).and_return(sample_file_path)
        allow(File).to receive(:read).with(sample_file_path).and_return("fake pdf content")
        allow(provider).to receive(:cleanup_temp_file)

        expect do
          provider.extract_data(
            file_path: sample_file_path,
            output_schema: output_schema
          )
        end.to raise_error(CvParser::AuthenticationError, /Invalid API key/)
      end
    end

    context "with invalid request error" do
      before do
        allow_any_instance_of(Faraday::Connection).to receive(:post).and_return(
          instance_double(
            Faraday::Response,
            status: 400,
            body: { "error" => { "message" => "Bad request parameter" } }
          )
        )
      end

      it "raises an InvalidRequestError" do
        # Mock file operations for a file-based test
        allow(provider).to receive(:validate_file_exists!)
        allow(provider).to receive(:validate_file_readable!)
        allow(provider).to receive(:convert_to_pdf_if_needed).and_return(sample_file_path)
        allow(File).to receive(:read).with(sample_file_path).and_return("fake pdf content")
        allow(provider).to receive(:cleanup_temp_file)

        expect do
          provider.extract_data(
            file_path: sample_file_path,
            output_schema: output_schema
          )
        end.to raise_error(CvParser::InvalidRequestError, /Anthropic API error/)
      end
    end

    context "with unexpected error" do
      before do
        allow_any_instance_of(Faraday::Connection).to receive(:post).and_return(
          instance_double(
            Faraday::Response,
            status: 500,
            body: { "error" => { "type" => "server_error", "message" => "Internal server error" } }
          )
        )
      end

      it "raises an APIError" do
        # Mock file operations for a file-based test
        allow(provider).to receive(:validate_file_exists!)
        allow(provider).to receive(:validate_file_readable!)
        allow(provider).to receive(:convert_to_pdf_if_needed).and_return(sample_file_path)
        allow(File).to receive(:read).with(sample_file_path).and_return("fake pdf content")
        allow(provider).to receive(:cleanup_temp_file)

        expect do
          provider.extract_data(
            file_path: sample_file_path,
            output_schema: output_schema
          )
        end.to raise_error(CvParser::APIError, /Anthropic API error/)
      end
    end

    context "with invalid JSON in response" do
      before do
        allow_any_instance_of(Faraday::Connection).to receive(:post).and_return(
          instance_double(
            Faraday::Response,
            status: 200,
            body: {
              "id" => "msg_01234567",
              "type" => "message",
              "role" => "assistant",
              "model" => "claude-3-opus-20240229",
              "content" => [
                {
                  "type" => "text",
                  "text" => "This is not valid JSON"
                }
              ]
            }
          )
        )
      end

      it "raises a ParseError" do
        # Mock file operations for a file-based test
        allow(provider).to receive(:validate_file_exists!)
        allow(provider).to receive(:validate_file_readable!)
        allow(provider).to receive(:convert_to_pdf_if_needed).and_return(sample_file_path)
        allow(File).to receive(:read).with(sample_file_path).and_return("fake pdf content")
        allow(provider).to receive(:cleanup_temp_file)

        expect do
          provider.extract_data(
            file_path: sample_file_path,
            output_schema: output_schema
          )
        end.to raise_error(CvParser::ParseError, /Failed to parse Claude's response as JSON/)
      end
    end

    context "with missing arguments" do
      it "raises an ArgumentError when file_path is not provided" do
        expect do
          provider.extract_data(output_schema: output_schema)
        end.to raise_error(ArgumentError, /File_path must be provided/)
      end
    end
  end
end
