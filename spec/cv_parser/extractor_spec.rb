# frozen_string_literal: true

require "spec_helper"

RSpec.describe CvParser::Extractor do
  let(:config) do
    CvParser.configure do |config|
      config.provider = :openai
      config.api_key = "fake-api-key"
      config.model = "gpt-4o"
    end
    CvParser.configuration
  end

  let(:extractor) { described_class.new(config) }
  let(:output_schema) do
    {
      type: "json_schema",
      properties: {
        name: { type: "string" },
        email: { type: "string" }
      }
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

  describe "#extract with text files" do
    let(:txt_file_path) { fixture_path("sample_resume.txt") }
    let(:md_file_path) { fixture_path("sample_resume.md") }
    let(:expected_result) { { "name" => "John Doe", "email" => "john@example.com" } }

    before do
      allow(File).to receive(:exist?).with(txt_file_path).and_return(true)
      allow(File).to receive(:readable?).with(txt_file_path).and_return(true)
      allow(File).to receive(:exist?).with(md_file_path).and_return(true)
      allow(File).to receive(:readable?).with(md_file_path).and_return(true)
    end

    it "successfully extracts data from txt files" do
      # Create new extractor with faker provider
      CvParser.configure do |config|
        config.provider = :faker
        config.api_key = "fake-api-key"
      end

      faker_extractor = CvParser::Extractor.new
      result = faker_extractor.extract(file_path: txt_file_path, output_schema: output_schema)
      expect(result).to be_a(Hash)
      expect(result).to include("name")
    end

    it "successfully extracts data from markdown files" do
      # Create new extractor with faker provider
      CvParser.configure do |config|
        config.provider = :faker
        config.api_key = "fake-api-key"
      end

      faker_extractor = CvParser::Extractor.new
      result = faker_extractor.extract(file_path: md_file_path, output_schema: output_schema)
      expect(result).to be_a(Hash)
      expect(result).to include("name")
    end

    it "validates text file existence" do
      allow(File).to receive(:exist?).with("non_existent.txt").and_return(false)

      expect do
        extractor.extract(file_path: "non_existent.txt", output_schema: output_schema)
      end.to raise_error(CvParser::FileNotFoundError)
    end
  end
end
