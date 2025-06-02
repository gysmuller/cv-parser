# frozen_string_literal: true

RSpec.describe CvParser::CLI do
  let(:cli) { described_class.new }
  let(:output) { StringIO.new }
  let(:test_file) { "spec/fixtures/sample_resume.md" }

  before do
    # Redirect stdout for testing
    $stdout = output

    # Create a test file if it doesn't exist
    unless File.exist?(test_file)
      FileUtils.mkdir_p(File.dirname(test_file))
      File.write(test_file, "# Sample Resume\n\nJohn Doe\nSoftware Engineer")
    end

    # Stub ENV variables with a default for any key
    allow(ENV).to receive(:[]) { |key| nil }
    allow(ENV).to receive(:[]).with("CV_PARSER_PROVIDER").and_return(nil)
    allow(ENV).to receive(:[]).with("CV_PARSER_API_KEY").and_return(nil)
    allow(ENV).to receive(:[]).with("OPENAI_API_KEY").and_return("test-openai-key")
    allow(ENV).to receive(:[]).with("ANTHROPIC_API_KEY").and_return(nil)

    # Mock the extractor to prevent actual API calls
    extractor = instance_double(CvParser::Extractor)
    allow(CvParser::Extractor).to receive(:new).and_return(extractor)
    allow(extractor).to receive(:extract).and_return({
                                                       "contact_information" => {
                                                         "name" => "John Doe",
                                                         "email" => "john@example.com"
                                                       },
                                                       "skills" => %w[Ruby Rails]
                                                     })
  end

  after do
    # Restore stdout
    $stdout = STDOUT

    # Reset CvParser configuration
    CvParser.reset
  end

  describe "#run" do
    before do
      # Mock exit to prevent tests from ending
      allow(cli).to receive(:exit)
    end

    it "shows help when using the --help option" do
      cli.run(["--help"])
      expect(output.string).to include("Usage: cv-parser [options]")
    end

    it "shows version when using the --version option" do
      cli.run(["--version"])
      expect(output.string).to include("CV Parser v#{CvParser::VERSION}")
    end

    it "reports an error when no input file is specified" do
      cli.run([])
      expect(output.string).to include("Error: No input file specified")
    end

    it "reports an error when input file doesn't exist" do
      cli.run(["non_existent_file.pdf"])
      expect(output.string).to include("Error: Input file 'non_existent_file.pdf' not found")
    end

    context "with valid input file" do
      it "configures the parser and extracts data" do
        # Use faker provider to avoid API key issues
        cli.run(["--provider", "faker", test_file])
        expect(CvParser.configuration.provider).to eq(:faker)
        expect(CvParser.configuration.api_key).to eq("fake-api-key")
        expect(output.string).to include("Parsing CV: #{test_file}")
        expect(output.string).to include("Using provider: faker")
        expect(output.string).to include("John Doe")
      end

      it "respects provider option with openai" do
        cli.run(["--provider", "openai", "--api-key", "test-key", test_file])
        expect(CvParser.configuration.provider).to eq(:openai)
        expect(CvParser.configuration.api_key).to eq("test-key")
      end

      it "respects provider option with anthropic" do
        cli.run(["--provider", "anthropic", "--api-key", "test-key", test_file])
        expect(CvParser.configuration.provider).to eq(:anthropic)
        expect(CvParser.configuration.api_key).to eq("test-key")
      end

      it "respects provider option with faker" do
        cli.run(["--provider", "faker", test_file])
        expect(CvParser.configuration.provider).to eq(:faker)
        expect(CvParser.configuration.api_key).to eq("fake-api-key")
      end

      it "respects output format option" do
        cli.run(["--format", "yaml", test_file])
        expect(output.string).to include("name: John Doe")
      end
    end
  end
end
