# frozen_string_literal: true

require "zlib"
require "rexml/document"
require "rexml/xpath"

module CvParser
  class PdfConverter
    LOCAL_FILE_HEADER_SIG = 0x04034b50

    PDF_VERSION = "%PDF-1.4"
    PAGE_WIDTH = 612       # 8.5in × 72dpi
    PAGE_HEIGHT = 792      # 11in  × 72dpi

    LEFT_MARGIN = 50
    RIGHT_MARGIN = 50
    TOP_MARGIN = 770       # starting Y position (points)
    BOTTOM_MARGIN = 50

    FONT_SIZE = 12
    LINE_HEIGHT = (FONT_SIZE * 1.2).to_f

    # Convert a .docx file into a multi-page PDF.
    #
    # @param input_path [String]  path to the .docx file
    # @param output_path [String] path where the PDF should be written
    # @raise [ArgumentError] if input_path is missing or not .docx
    # @raise [RuntimeError]  if extraction or PDF writing fails
    def convert(input_path, output_path)
      validate_input!(input_path)

      xml = extract_document_xml(input_path)
      paragraphs = parse_paragraphs(xml)

      # produce an array of all lines, handling wraps and blank lines
      lines = paragraphs.flat_map do |para_text|
        # split on manual breaks
        sub_paragraphs = para_text.split("\n", -1)
        # if para_text ends in "\n", split will include a trailing empty string,
        # which we want to preserve as a blank line
        sub_paragraphs.map do |line|
          if line.strip.empty?
            [""] # preserve blank line
          else
            wrap_line(line, max_chars_per_line)
          end
        end
      end.flatten

      # group lines into pages
      lp = lines_per_page
      pages = lines.each_slice(lp).to_a

      pdf_data = build_pdf(pages)
      write_pdf(output_path, pdf_data)
      output_path
    end

    private

    # Ensure the input exists and ends with .docx
    def validate_input!(input_path)
      return if File.exist?(input_path) && File.extname(input_path).downcase == ".docx"

      raise ArgumentError, "Input must be an existing .docx file"
    end

    # Scan through the DOCX (ZIP) for word/document.xml,
    # read its compressed bytes, and decompress with Zlib.
    # Returns the XML string.
    def extract_document_xml(docx_path)
      File.open(docx_path, "rb") do |f|
        until f.eof?
          sig_bytes = f.read(4)
          break if sig_bytes.nil? || sig_bytes.bytesize < 4

          sig = sig_bytes.unpack1("V")
          if sig == LOCAL_FILE_HEADER_SIG
            header = f.read(26)
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

            name_bytes = f.read(fname_len)
            f.read(extra_len)
            compressed_data = f.read(comp_size)

            filename = name_bytes.force_encoding("UTF-8")
            if filename == "word/document.xml"
              if compression == 0
                return compressed_data.force_encoding("UTF-8")
              elsif compression == 8
                return Zlib::Inflate.new(-Zlib::MAX_WBITS).inflate(compressed_data)
              else
                raise "Unsupported compression method: #{compression}"
              end
            end
          else
            # Not a local file header; back up 3 bytes to resync
            f.seek(-3, IO::SEEK_CUR)
          end
        end
      end
      raise "word/document.xml not found in DOCX"
    end

    # Use REXML to parse the XML and extract an array of paragraph texts.
    # Each paragraph may contain "\n" where Word used <w:br/>.
    def parse_paragraphs(xml_string)
      doc = REXML::Document.new(xml_string)
      paragraphs = []

      # For each <w:p> element:
      REXML::XPath.each(doc, '//*[local-name()="p"]') do |p_node|
        paragraphs << text_with_breaks(p_node).strip
      end

      paragraphs
    end

    # Recursively collect text from a node, inserting "\n" on <w:br/>.
    def text_with_breaks(node)
      result = +"" # Create a mutable string
      node.children.each do |child|
        if child.node_type == :text
          result << child.to_s
        elsif child.node_type == :element && REXML::XPath.match(child, "/*").any?
          # If it's a <w:br/>, insert newline
          result << if child.expanded_name.split(":").last == "br"
                      "\n"
                    else
                      text_with_breaks(child)
                    end
        end
      end
      result
    end

    # Estimate how many characters fit per line, assuming
    # average char width ≈ FONT_SIZE * 0.5 (monospaced-ish).
    def max_chars_per_line
      usable_width = PAGE_WIDTH - LEFT_MARGIN - RIGHT_MARGIN
      (usable_width / (FONT_SIZE * 0.5)).floor
    end

    # Wrap a single line of text into multiple lines no longer than max_chars.
    # Splits on spaces; if one word exceeds max_chars, it breaks mid-word.
    def wrap_line(text, max_chars)
      return [text] if text.length <= max_chars

      words = text.split(/\s+/)
      lines = []
      current = ""

      words.each do |w|
        if current.empty?
          if w.length <= max_chars
            current = w
          else
            # word alone exceeds max_chars → break it
            w.chars.each_slice(max_chars) { |seg| lines << seg.join }
            current = ""
          end
        elsif (current.length + 1 + w.length) <= max_chars
          current << " " << w
        else
          lines << current
          if w.length <= max_chars
            current = w
          else
            # break the long word
            w.chars.each_slice(max_chars) { |seg| lines << seg.join }
            current = ""
          end
        end
      end

      lines << current unless current.empty?
      lines
    end

    # Compute how many lines fit on one page.
    def lines_per_page
      vertical_space = TOP_MARGIN - BOTTOM_MARGIN
      # +1 to account for the first line at TOP_MARGIN
      (vertical_space / LINE_HEIGHT).floor + 1
    end

    # Build a multi-page PDF string given an array of pages,
    # where each page is itself an array of text lines.
    def build_pdf(pages)
      objects = []
      offsets = []

      # object 1: catalog
      objects << <<~OBJ
        1 0 obj
        << /Type /Catalog /Pages 2 0 R >>
        endobj
      OBJ

      # object 2: pages (Kids and Count will be filled after we know page IDs)
      # We'll generate the Kids array once we know how many pages there are.
      # Placeholder for now:
      pages_obj_template = lambda do |kid_ids|
        kids_str = kid_ids.map { |pid| "#{pid} 0 R" }.join(" ")
        <<~OBJ
          2 0 obj
          << /Type /Pages /Count #{kid_ids.size} /Kids [#{kids_str}] >>
          endobj
        OBJ
      end

      # object 3: font (Helvetica)
      objects << <<~OBJ
        3 0 obj
        << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>
        endobj
      OBJ

      # Now assign IDs for page and content objects.
      # Page IDs start at 4, then increment by 2: 4,6,8,...
      # Content IDs follow: 5,7,9,...
      page_ids = []
      content_ids = []
      pages.each_with_index do |_, idx|
        page_ids << (4 + (idx * 2))
        content_ids << (5 + (idx * 2))
      end

      # Insert the correct pages obj at index 1
      objects.insert(1, pages_obj_template.call(page_ids))

      # For each page, build page obj then content obj
      pages.each_with_index do |lines, idx|
        pid = page_ids[idx]
        cid = content_ids[idx]

        # page object
        objects << <<~OBJ
          #{pid} 0 obj
          << /Type /Page /Parent 2 0 R
             /MediaBox [0 0 #{PAGE_WIDTH} #{PAGE_HEIGHT}]
             /Resources << /Font << /F1 3 0 R >> >>
             /Contents #{cid} 0 R
          >>
          endobj
        OBJ

        # content stream: place each line at successive positions
        content_stream = build_content_stream(lines)
        length = content_stream.bytesize

        # content object
        objects << <<~OBJ
          #{cid} 0 obj
          << /Length #{length} >>
          stream
          #{content_stream}endstream
          endobj
        OBJ
      end

      # Assemble PDF: header + objects + xref + trailer
      pdf = +"#{PDF_VERSION}\n%\u00E2\u00E3\u00CF\u00D3\n"
      objects.each do |obj|
        offsets << pdf.bytesize
        pdf << obj
      end

      xref_offset = pdf.bytesize
      pdf << "xref\n0 #{objects.size + 1}\n"
      pdf << "0000000000 65535 f \n"
      offsets.each do |ofs|
        pdf << (ofs.to_s.rjust(10, "0") + " 00000 n \n")
      end

      pdf << <<~TRAILER
        trailer
        << /Size #{objects.size + 1} /Root 1 0 R >>
        startxref
        #{xref_offset}
        %%EOF
      TRAILER

      pdf
    end

    # Build the PDF content stream for a single page.
    # Each page's lines are placed from TOP_MARGIN downwards.
    def build_content_stream(lines)
      return "" if lines.empty?

      stream = +"BT\n/F1 #{FONT_SIZE} Tf\n#{LEFT_MARGIN} #{TOP_MARGIN} Td\n"
      lines.each_with_index do |ln, idx|
        if ln.empty?
          # move down one line without drawing
          stream << "T*\n"
        else
          escaped = escape_pdf_text(ln)
          # if not the very first line, we move down before writing
          prefix = idx.zero? ? "" : "T*\n"
          stream << "#{prefix}(#{escaped}) Tj\n"
        end
      end
      stream << "ET\n"
      stream
    end

    # Escape parentheses and backslashes in PDF literal text
    def escape_pdf_text(str)
      str.gsub("\\", "\\\\").gsub("(", '\\(').gsub(")", '\\)')
    end

    # Write the PDF data to disk
    def write_pdf(path, data)
      dir = File.dirname(File.expand_path(path))
      Dir.mkdir(dir) unless Dir.exist?(dir)
      File.binwrite(path, data)
    end
  end
end
