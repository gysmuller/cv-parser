# frozen_string_literal: true

require "spec_helper"

RSpec.describe CvParser::PdfConverter do
  let(:converter) { described_class.new }
  let(:docx_fixture_path) { fixture_path("cv_example.docx") }

  describe "XML extraction and parsing" do
    it "validates the docx input path" do
      expect { converter.send(:validate_input!, "not_a_docx_file.txt") }.to raise_error(ArgumentError)
      expect { converter.send(:validate_input!, "non_existent.docx") }.to raise_error(ArgumentError)

      # Should not raise an error for valid docx path
      expect { converter.send(:validate_input!, docx_fixture_path) }.not_to raise_error
    end

    it "parses paragraphs from XML" do
      # Create a simple test XML with a paragraph
      xml = <<~XML
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
            <w:p>
              <w:r>
                <w:t>Sample paragraph text</w:t>
              </w:r>
            </w:p>
          </w:body>
        </w:document>
      XML

      paragraphs = converter.send(:parse_paragraphs, xml)

      expect(paragraphs).to be_an(Array)
      expect(paragraphs.size).to be > 0
      expect(paragraphs.first).to eq("Sample paragraph text")
    end

    it "correctly handles line breaks in paragraphs" do
      # Simplified XML with minimal whitespace
      xml = <<~XML
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
            <w:p>
              <w:r><w:t>Line 1</w:t></w:r>
              <w:r><w:br/></w:r>
              <w:r><w:t>Line 2</w:t></w:r>
            </w:p>
          </w:body>
        </w:document>
      XML

      paragraphs = converter.send(:parse_paragraphs, xml)

      expect(paragraphs.size).to eq(1)
      # The implementation may handle whitespace differently, so strip it for comparison
      expect(paragraphs.first.gsub(/\s+/, " ").strip).to eq("Line 1 Line 2")
    end
  end

  describe "PDF generation" do
    let(:test_pages) { [["Line 1", "Line 2"], ["Page 2 Line 1"]] }

    it "builds valid PDF content streams" do
      content_stream = converter.send(:build_content_stream, test_pages.first)

      expect(content_stream).to start_with("BT\n/F1")
      expect(content_stream).to include("(Line 1) Tj\n")
      expect(content_stream).to include("(Line 2) Tj\n")
      expect(content_stream).to end_with("ET\n")
    end

    it "builds valid PDF data" do
      pdf_data = converter.send(:build_pdf, test_pages)

      expect(pdf_data).to start_with("%PDF-1.4")
      expect(pdf_data).to include("obj")
      expect(pdf_data).to include("/Type /Catalog")
      expect(pdf_data).to include("/Type /Pages")
      expect(pdf_data).to include("/Type /Page")
      expect(pdf_data).to include("/Type /Font")
      expect(pdf_data).to include("stream")
      expect(pdf_data).to include("endstream")
      expect(pdf_data).to include("xref")
      expect(pdf_data).to include("trailer")
      expect(pdf_data).to end_with("%%EOF\n")
    end

    it "creates line wrapping correctly" do
      short_text = "Short text"
      long_text = "This is a much longer text that should be wrapped to multiple lines based on the maximum character count per line"

      # Test that short text is not wrapped
      short_result = converter.send(:wrap_line, short_text, 20)
      expect(short_result).to eq([short_text])

      # Test that long text is wrapped
      long_result = converter.send(:wrap_line, long_text, 20)
      expect(long_result.length).to be > 1
      expect(long_result.all? { |line| line.length <= 20 }).to be true

      # Test that very long words are broken
      long_word = "Supercalifragilisticexpialidocious"
      word_result = converter.send(:wrap_line, long_word, 10)
      expect(word_result.length).to be > 1
      expect(word_result.all? { |line| line.length <= 10 }).to be true
    end
  end
end
