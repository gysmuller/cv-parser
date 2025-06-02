# frozen_string_literal: true

require "spec_helper"
require "tempfile"
require "fileutils"

RSpec.describe CvParser::PdfConverter do
  let(:converter) { described_class.new }
  let(:docx_fixture_path) { fixture_path("cv_example.docx") }
  let(:output_pdf_path) { File.join(Dir.tmpdir, "test_output.pdf") }

  after do
    # Clean up any generated files
    FileUtils.rm_f(output_pdf_path)
  end

  describe "#convert" do
    it "converts a .docx file to PDF" do
      # Act
      result = converter.convert(docx_fixture_path, output_pdf_path)

      # Assert
      expect(result).to eq(output_pdf_path)
      expect(File.exist?(output_pdf_path)).to be true
      expect(File.size(output_pdf_path)).to be > 0

      # Basic PDF header check
      pdf_content = File.binread(output_pdf_path)
      expect(pdf_content).to start_with("%PDF-1.4")
      expect(pdf_content).to end_with("%%EOF\n")
    end

    it "raises ArgumentError for non-existent files" do
      expect do
        converter.convert("non_existent_file.docx", output_pdf_path)
      end.to raise_error(ArgumentError, /Input must be an existing .docx file/)
    end

    it "raises ArgumentError for non-docx files" do
      non_docx_file = Tempfile.new(["test", ".txt"])
      begin
        expect do
          converter.convert(non_docx_file.path, output_pdf_path)
        end.to raise_error(ArgumentError, /Input must be an existing .docx file/)
      ensure
        non_docx_file.close
        non_docx_file.unlink
      end
    end
  end

  describe "private methods" do
    # Test private methods using the send method

    describe "#max_chars_per_line" do
      it "calculates the correct number of characters per line" do
        usable_width = 612 - 50 - 50 # PAGE_WIDTH - LEFT_MARGIN - RIGHT_MARGIN
        expected = (usable_width / (12 * 0.5)).floor # (usable_width / (FONT_SIZE * 0.5)).floor

        expect(converter.send(:max_chars_per_line)).to eq(expected)
      end
    end

    describe "#wrap_line" do
      it "returns the original text if it fits on one line" do
        text = "Short text"
        max_chars = 20

        result = converter.send(:wrap_line, text, max_chars)

        expect(result).to eq([text])
      end

      it "wraps text that exceeds the maximum line length" do
        text = "This is a longer text that needs to be wrapped across multiple lines"
        max_chars = 20

        result = converter.send(:wrap_line, text, max_chars)

        expect(result.length).to be > 1
        expect(result.all? { |line| line.length <= max_chars }).to be true
      end

      it "handles very long words by breaking them" do
        text = "Supercalifragilisticexpialidocious"
        max_chars = 10

        result = converter.send(:wrap_line, text, max_chars)

        expect(result.length).to eq(4)
        expect(result.all? { |line| line.length <= max_chars }).to be true
      end
    end

    describe "#lines_per_page" do
      it "calculates the correct number of lines per page" do
        vertical_space = 770 - 50 # TOP_MARGIN - BOTTOM_MARGIN
        line_height = 12 * 1.2 # FONT_SIZE * 1.2
        expected = (vertical_space / line_height).floor + 1

        expect(converter.send(:lines_per_page)).to eq(expected)
      end
    end

    describe "#escape_pdf_text" do
      it "escapes special characters in PDF text" do
        text = "Text with (parentheses) and \\backslashes\\"

        result = converter.send(:escape_pdf_text, text)

        expect(result).to eq("Text with \\(parentheses\\) and \\backslashes\\")
      end
    end
  end
end
