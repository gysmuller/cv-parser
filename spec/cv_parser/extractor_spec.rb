# frozen_string_literal: true

require "spec_helper"

RSpec.describe CvParser::Extractor do
  let(:config) do
    CvParser.configure do |config|
      config.configure_openai(access_token: "fake-api-key")
      config.model = "gpt-4o"
    end
    CvParser.configuration
  end

  let(:extractor) { described_class.new(config) }
  let(:output_schema) do
    {
      name: "string",
      email: "string"
    }
  end

  describe "#initialize" do
    it "raises ConfigurationError if provider is not configured" do
      CvParser.reset
      config = CvParser.configuration

      expect do
        described_class.new(config)
      end.to raise_error(CvParser::ConfigurationError, /LLM provider not configured/)
    end

    it "raises ConfigurationError if API key is not configured" do
      CvParser.reset
      config = CvParser.configuration
      config.provider = :openai

      expect do
        described_class.new(config)
      end.to raise_error(CvParser::ConfigurationError, /API key not configured/)
    end

    it "raises ConfigurationError for unsupported provider" do
      CvParser.reset
      config = CvParser.configuration
      config.provider = :unsupported
      config.api_key = "fake-key"

      expect do
        described_class.new(config)
      end.to raise_error(CvParser::ConfigurationError, /Unsupported provider/)
    end
  end

  describe "#extract" do
    let(:mock_provider) { instance_double(CvParser::Providers::OpenAI) }
    let(:sample_file_path) { "test.pdf" }

    before do
      # Mock provider
      allow(CvParser::Providers::OpenAI).to receive(:new).and_return(mock_provider)
      # Mock file validation
      allow(File).to receive(:exist?).with(sample_file_path).and_return(true)
      allow(File).to receive(:readable?).with(sample_file_path).and_return(true)
    end

    it "validates file existence and readability" do
      expected_result = { "name" => "John Doe", "email" => "john@example.com" }

      expect(mock_provider).to receive(:extract_data).with(
        file_path: sample_file_path,
        output_schema: output_schema
      ).and_return(expected_result)

      result = extractor.extract(file_path: sample_file_path, output_schema: output_schema)
      expect(result).to eq(expected_result)
    end
  end
end
