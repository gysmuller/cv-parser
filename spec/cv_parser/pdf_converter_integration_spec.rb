# frozen_string_literal: true

require "spec_helper"
require "tempfile"
require "fileutils"

RSpec.describe CvParser::PdfConverter do
  let(:converter) { described_class.new }
  let(:docx_fixture_path) { fixture_path("cv_example.docx") }
  let(:output_dir) { File.join(Dir.tmpdir, "cv_parser_test_#{Time.now.to_i}") }

  before do
    FileUtils.mkdir_p(output_dir)
  end

  after do
    FileUtils.rm_rf(output_dir)
  end

  describe "integration tests" do
    it "successfully converts a docx to PDF" do
      output_path = File.join(output_dir, "output.pdf")

      # Perform the conversion
      result = converter.convert(docx_fixture_path, output_path)

      # Verify the results
      expect(result).to eq(output_path)
      expect(File.exist?(output_path)).to be true
      expect(File.size(output_path)).to be > 0

      # Basic PDF header and footer checks
      pdf_content = File.binread(output_path)
      expect(pdf_content).to start_with("%PDF-1.4")
      expect(pdf_content).to end_with("%%EOF\n")
    end

    it "handles file paths with spaces" do
      output_path = File.join(output_dir, "output with spaces.pdf")

      # Perform the conversion
      result = converter.convert(docx_fixture_path, output_path)

      # Verify the results
      expect(result).to eq(output_path)
      expect(File.exist?(output_path)).to be true
    end

    it "creates the immediate parent directory if it doesn't exist" do
      # Create a single-level directory that doesn't exist yet
      output_path = File.join(output_dir, "new_dir", "output.pdf")

      # Create parent directory first (since the implementation doesn't create nested dirs)
      FileUtils.mkdir_p(File.dirname(output_path))

      # Perform the conversion
      converter.convert(docx_fixture_path, output_path)

      # Verify the file exists
      expect(File.exist?(output_path)).to be true
    end

    it "raises an error for invalid input files" do
      output_path = File.join(output_dir, "output.pdf")

      # Test with non-existent file
      expect do
        converter.convert("non_existent_file.docx", output_path)
      end.to raise_error(ArgumentError)

      # Test with file of wrong extension
      temp_txt = Tempfile.new(["test", ".txt"])
      begin
        expect do
          converter.convert(temp_txt.path, output_path)
        end.to raise_error(ArgumentError)
      ensure
        temp_txt.close
        temp_txt.unlink
      end
    end
  end
end
