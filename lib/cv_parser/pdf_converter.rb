# frozen_string_literal: true

require "zlib"
require "rexml/document"
require "rexml/xpath"

module CvParser
  # Converts DOCX files to PDF format by extracting text content and rendering it as PDF pages
  class PdfConverter
    # Constants modules for better organization
    module PageConstants
      PAGE_WIDTH = 612       # 8.5in × 72dpi
      PAGE_HEIGHT = 792      # 11in × 72dpi
      LEFT_MARGIN = 50
      RIGHT_MARGIN = 50
      TOP_MARGIN = 770       # starting Y position (points)
      BOTTOM_MARGIN = 50
    end

    module TextConstants
      FONT_SIZE = 12
      LINE_HEIGHT = (FONT_SIZE * 1.2).to_f
      CHAR_WIDTH_RATIO = 0.5 # average char width ≈ FONT_SIZE * 0.5
    end

    include PageConstants
    include TextConstants

    # Convert a .docx file into a multi-page PDF.
    #
    # @param input_path [String]  path to the .docx file
    # @param output_path [String] path where the PDF should be written
    # @raise [ArgumentError] if input_path is missing or not .docx
    # @raise [RuntimeError]  if extraction or PDF writing fails
    def convert(input_path, output_path)
      InputValidator.validate!(input_path)

      xml = DocxExtractor.new(input_path).extract_document_xml
      paragraphs = XmlParser.new(xml).parse_paragraphs

      text_processor = TextProcessor.new
      lines = text_processor.process_paragraphs(paragraphs)
      pages = text_processor.paginate_lines(lines)

      pdf_data = PdfBuilder.new.build_pdf(pages)
      FileWriter.write_pdf(output_path, pdf_data)

      output_path
    end

    private

    # Backward compatibility methods for existing tests
    def max_chars_per_line
      TextProcessor.new.send(:max_chars_per_line)
    end

    def wrap_line(text, max_chars)
      LineWrapper.new.wrap_line(text, max_chars)
    end

    def lines_per_page
      TextProcessor.new.send(:lines_per_page)
    end

    def escape_pdf_text(text)
      PdfTextEscaper.escape(text)
    end

    def validate_input!(input_path)
      InputValidator.validate!(input_path)
    end

    def parse_paragraphs(xml_string)
      XmlParser.new(xml_string).parse_paragraphs
    end

    def build_content_stream(lines)
      ContentStreamBuilder.new(lines).build
    end

    def build_pdf(pages)
      PdfBuilder.new.build_pdf(pages)
    end

    # Input validation extracted to separate class
    class InputValidator
      def self.validate!(input_path)
        return if File.exist?(input_path) && File.extname(input_path).downcase == ".docx"

        raise ArgumentError, "Input must be an existing .docx file"
      end
    end

    # DOCX extraction logic extracted to separate class
    class DocxExtractor
      LOCAL_FILE_HEADER_SIG = 0x04034b50
      DOCUMENT_XML_PATH = "word/document.xml"

      def initialize(docx_path)
        @docx_path = docx_path
      end

      def extract_document_xml
        File.open(@docx_path, "rb") do |file|
          scan_for_document_xml(file)
        end
      end

      private

      def scan_for_document_xml(file)
        until file.eof?
          sig_bytes = file.read(4)
          break if sig_bytes.nil? || sig_bytes.bytesize < 4

          sig = sig_bytes.unpack1("V")
          if sig == LOCAL_FILE_HEADER_SIG
            xml_content = process_zip_entry(file)
            return xml_content if xml_content
          else
            # Not a local file header; back up 3 bytes to resync
            file.seek(-3, IO::SEEK_CUR)
          end
        end

        raise "#{DOCUMENT_XML_PATH} not found in DOCX"
      end

      def process_zip_entry(file)
        header = file.read(26)
        entry_info = parse_zip_header(header)

        name_bytes = file.read(entry_info[:fname_len])
        file.read(entry_info[:extra_len])
        compressed_data = file.read(entry_info[:comp_size])

        filename = name_bytes.force_encoding("UTF-8")
        return nil unless filename == DOCUMENT_XML_PATH

        decompress_data(compressed_data, entry_info[:compression])
      end

      def parse_zip_header(header)
        (
          version_needed,
          flags,
          compression,
          _mod_time,
          _mod_date,
          _crc32,
          comp_size,
          _uncomp_size,
          fname_len,
          extra_len
        ) = header.unpack("v v v v v V V V v v")

        {
          compression: compression,
          comp_size: comp_size,
          fname_len: fname_len,
          extra_len: extra_len
        }
      end

      def decompress_data(compressed_data, compression)
        case compression
        when 0
          compressed_data.force_encoding("UTF-8")
        when 8
          Zlib::Inflate.new(-Zlib::MAX_WBITS).inflate(compressed_data)
        else
          raise "Unsupported compression method: #{compression}"
        end
      end
    end

    # XML parsing logic extracted to separate class
    class XmlParser
      def initialize(xml_string)
        @xml_string = xml_string
      end

      def parse_paragraphs
        doc = REXML::Document.new(@xml_string)
        paragraphs = []

        REXML::XPath.each(doc, '//*[local-name()="p"]') do |p_node|
          paragraphs << extract_text_with_breaks(p_node).strip
        end

        paragraphs
      end

      private

      def extract_text_with_breaks(node)
        result = +""

        node.children.each do |child|
          case child.node_type
          when :text
            result << child.to_s
          when :element
            result << process_element_node(child)
          end
        end

        result
      end

      def process_element_node(child)
        return "" unless REXML::XPath.match(child, "/*").any?

        if line_break?(child)
          "\n"
        else
          extract_text_with_breaks(child)
        end
      end

      def line_break?(element)
        element.expanded_name.split(":").last == "br"
      end
    end

    # Text processing and pagination logic
    class TextProcessor
      include PageConstants
      include TextConstants

      def process_paragraphs(paragraphs)
        paragraphs.flat_map do |para_text|
          process_single_paragraph(para_text)
        end.flatten
      end

      def paginate_lines(lines)
        lines.each_slice(lines_per_page).to_a
      end

      private

      def process_single_paragraph(para_text)
        sub_paragraphs = para_text.split("\n", -1)

        sub_paragraphs.map do |line|
          if line.strip.empty?
            [""]
          else
            LineWrapper.new.wrap_line(line, max_chars_per_line)
          end
        end
      end

      def max_chars_per_line
        usable_width = PAGE_WIDTH - LEFT_MARGIN - RIGHT_MARGIN
        (usable_width / (FONT_SIZE * CHAR_WIDTH_RATIO)).floor
      end

      def lines_per_page
        vertical_space = TOP_MARGIN - BOTTOM_MARGIN
        (vertical_space / LINE_HEIGHT).floor + 1
      end
    end

    # Line wrapping logic extracted to separate class
    class LineWrapper
      def wrap_line(text, max_chars)
        return [text] if text.length <= max_chars

        words = text.split(/\s+/)
        lines = []
        current_line = ""

        words.each do |word|
          if current_line.empty?
            current_line = process_first_word_in_line(word, max_chars, lines)
          elsif fits_on_current_line?(current_line, word, max_chars)
            current_line << " " << word
          else
            lines << current_line
            current_line = process_first_word_in_line(word, max_chars, lines)
          end
        end

        lines << current_line unless current_line.empty?
        lines
      end

      private

      def process_first_word_in_line(word, max_chars, lines)
        if word.length <= max_chars
          word
        else
          break_long_word(word, max_chars, lines)
          ""
        end
      end

      def fits_on_current_line?(current_line, word, max_chars)
        (current_line.length + 1 + word.length) <= max_chars
      end

      def break_long_word(word, max_chars, lines)
        word.chars.each_slice(max_chars) { |segment| lines << segment.join }
      end
    end

    # PDF building logic extracted to separate class
    class PdfBuilder
      include PageConstants
      include TextConstants

      def build_pdf(pages)
        pdf_structure = PdfStructure.new(pages)
        pdf_structure.build
      end
    end

    # PDF structure and assembly
    class PdfStructure
      include PageConstants

      PDF_VERSION = "%PDF-1.4"
      PDF_HEADER_BYTES = "%\u00E2\u00E3\u00CF\u00D3"

      def initialize(pages)
        @pages = pages
        @objects = []
        @offsets = []
      end

      def build
        create_catalog_object
        create_pages_object
        create_font_object
        create_page_objects

        assemble_pdf
      end

      private

      def create_catalog_object
        @objects << build_object(1, "<< /Type /Catalog /Pages 2 0 R >>")
      end

      def create_pages_object
        page_ids = calculate_page_ids
        kids_str = page_ids.map { |pid| "#{pid} 0 R" }.join(" ")
        pages_content = "<< /Type /Pages /Count #{page_ids.size} /Kids [#{kids_str}] >>"

        @objects << build_object(2, pages_content)
      end

      def create_font_object
        @objects << build_object(3, "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>")
      end

      def create_page_objects
        page_ids = calculate_page_ids
        content_ids = calculate_content_ids

        @pages.each_with_index do |lines, idx|
          create_page_object(page_ids[idx], content_ids[idx])
          create_content_object(content_ids[idx], lines)
        end
      end

      def create_page_object(page_id, content_id)
        page_content = <<~CONTENT.strip
          << /Type /Page /Parent 2 0 R
             /MediaBox [0 0 #{PAGE_WIDTH} #{PAGE_HEIGHT}]
             /Resources << /Font << /F1 3 0 R >> >>
             /Contents #{content_id} 0 R
          >>
        CONTENT

        @objects << build_object(page_id, page_content)
      end

      def create_content_object(content_id, lines)
        content_stream = ContentStreamBuilder.new(lines).build
        length = content_stream.bytesize

        content_obj = <<~CONTENT
          << /Length #{length} >>
          stream
          #{content_stream}endstream
        CONTENT

        @objects << build_object(content_id, content_obj)
      end

      def calculate_page_ids
        @pages.map.with_index { |_, idx| 4 + (idx * 2) }
      end

      def calculate_content_ids
        @pages.map.with_index { |_, idx| 5 + (idx * 2) }
      end

      def build_object(id, content)
        <<~OBJ
          #{id} 0 obj
          #{content}
          endobj
        OBJ
      end

      def assemble_pdf
        pdf = +"#{PDF_VERSION}\n#{PDF_HEADER_BYTES}\n"

        @objects.each do |obj|
          @offsets << pdf.bytesize
          pdf << obj
        end

        add_xref_table(pdf)

        pdf
      end

      def add_xref_table(pdf)
        xref_offset = pdf.bytesize
        pdf << "xref\n0 #{@objects.size + 1}\n"
        pdf << "0000000000 65535 f \n"

        @offsets.each do |offset|
          pdf << "#{offset.to_s.rjust(10, "0")} 00000 n \n"
        end

        pdf << <<~TRAILER
          trailer
          << /Size #{@objects.size + 1} /Root 1 0 R >>
          startxref
          #{xref_offset}
          %%EOF
        TRAILER
      end
    end

    # Content stream building for PDF pages
    class ContentStreamBuilder
      include PageConstants
      include TextConstants

      def initialize(lines)
        @lines = lines
      end

      def build
        return "" if @lines.empty?

        stream = +"BT\n/F1 #{FONT_SIZE} Tf\n#{LEFT_MARGIN} #{TOP_MARGIN} Td\n"

        @lines.each_with_index do |line, idx|
          add_line_to_stream(stream, line, idx)
        end

        stream << "ET\n"
        stream
      end

      private

      def add_line_to_stream(stream, line, index)
        if line.empty?
          stream << "T*\n"
        else
          escaped_text = PdfTextEscaper.escape(line)
          line_prefix = index.zero? ? "" : "T*\n"
          stream << "#{line_prefix}(#{escaped_text}) Tj\n"
        end
      end
    end

    # PDF text escaping utility
    class PdfTextEscaper
      def self.escape(text)
        text.gsub("\\", "\\\\").gsub("(", '\\(').gsub(")", '\\)')
      end
    end

    # File writing utility
    class FileWriter
      def self.write_pdf(path, data)
        dir = File.dirname(File.expand_path(path))
        Dir.mkdir(dir) unless Dir.exist?(dir)
        File.binwrite(path, data)
      end
    end
  end
end
