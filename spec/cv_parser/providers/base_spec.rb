# frozen_string_literal: true

require "spec_helper"

RSpec.describe CvParser::Providers::Base do
  let(:config) do
    config = CvParser::Configuration.new
    config.provider = :test
    config.api_key = "fake-api-key"
    config
  end

  let(:provider) { described_class.new(config) }
  let(:txt_file_path) { fixture_path("sample_resume.txt") }
  let(:md_file_path) { fixture_path("sample_resume.md") }
  let(:pdf_file_path) { fixture_path("cv_example.docx") } # We'll pretend this is a PDF
  let(:empty_file_path) { fixture_path("empty_resume.txt") }

  describe "#text_file?" do
    it "returns true for .txt files" do
      expect(provider.send(:text_file?, txt_file_path)).to be true
    end

    it "returns true for .md files" do
      expect(provider.send(:text_file?, md_file_path)).to be true
    end

    it "returns false for .pdf files" do
      expect(provider.send(:text_file?, pdf_file_path)).to be false
    end

    it "is case insensitive" do
      expect(provider.send(:text_file?, "test.TXT")).to be true
      expect(provider.send(:text_file?, "test.MD")).to be true
    end
  end

  describe "#read_text_file_content" do
    context "with valid text file" do
      it "reads the content successfully" do
        content = provider.send(:read_text_file_content, txt_file_path)
        expect(content).to include("John Doe")
        expect(content).to include("Software Engineer")
      end
    end

    context "with empty text file" do
      it "raises EmptyTextFileError" do
        expect do
          provider.send(:read_text_file_content, empty_file_path)
        end.to raise_error(CvParser::EmptyTextFileError, /Text file is empty/)
      end
    end

    context "with non-existent file" do
      it "raises appropriate error" do
        expect do
          provider.send(:read_text_file_content, "non_existent.txt")
        end.to raise_error(Errno::ENOENT)
      end
    end
  end

  describe "#convert_to_pdf_if_needed" do
    it "returns the original path for text files" do
      result = provider.send(:convert_to_pdf_if_needed, txt_file_path)
      expect(result).to eq(txt_file_path)
    end

    it "returns the original path for markdown files" do
      result = provider.send(:convert_to_pdf_if_needed, md_file_path)
      expect(result).to eq(md_file_path)
    end
  end

  describe "#extract_data" do
    it "raises NotImplementedError" do
      expect do
        provider.extract_data(output_schema: {}, file_path: txt_file_path)
      end.to raise_error(NotImplementedError)
    end
  end

  describe "#upload_file" do
    it "raises NotImplementedError" do
      expect do
        provider.upload_file(txt_file_path)
      end.to raise_error(NotImplementedError)
    end
  end
end
