# frozen_string_literal: true

require "optparse"
require "json"
require_relative "../cv_parser"

module CvParser
  class CLI
    DEFAULT_SCHEMA = {
      contact_information: {
        name: "string",
        email: "string",
        phone: "string",
        location: "string",
        linkedin: "string"
      },
      education: [
        {
          institution: "string",
          degree: "string",
          field_of_study: "string",
          dates: "string",
          achievements: ["string"]
        }
      ],
      work_experience: [
        {
          company: "string",
          position: "string",
          dates: "string",
          responsibilities: ["string"],
          achievements: ["string"]
        }
      ],
      skills: ["string"],
      languages: ["string"],
      certifications: ["string"]
    }.freeze

    def initialize
      @options = {
        provider: nil,
        api_key: nil,
        output_format: "json",
        output_file: nil,
        schema_file: nil
      }
    end

    def run(args = ARGV)
      parse_options(args)

      if args.empty?
        puts "Error: No input file specified"
        puts @parser
        exit 1
      end

      input_file = args[0]

      # Early exit for special options where we don't need a file
      return if @options[:help] || @options[:version]

      # Check if file exists
      if !input_file || !File.exist?(input_file)
        puts "Error: Input file '#{input_file}' not found"
        exit 1
      end

      configure_parser

      begin
        output_schema = load_schema
        result = extract_data(input_file, output_schema)
        output_result(result)
      rescue CvParser::Error => e
        puts "Error: #{e.message}"
        exit 1
      end
    end

    private

    def parse_options(args)
      @parser = OptionParser.new do |opts|
        opts.banner = "Usage: cv-parser [options] <file>"

        opts.on("-p", "--provider PROVIDER", "LLM Provider (openai, anthropic, or faker)") do |provider|
          @options[:provider] = provider.to_sym
        end

        opts.on("-k", "--api-key API_KEY", "API key for the LLM provider") do |key|
          @options[:api_key] = key
        end

        opts.on("-f", "--format FORMAT", "Output format (json or yaml)") do |format|
          @options[:output_format] = format
        end

        opts.on("-o", "--output FILE", "Write output to file") do |file|
          @options[:output_file] = file
        end

        opts.on("-s", "--schema FILE", "Custom schema file (JSON)") do |file|
          @options[:schema_file] = file
        end

        opts.on("-h", "--help", "Show this help message") do
          puts opts
          @options[:help] = true
          exit
        end

        opts.on("-v", "--version", "Show version") do
          puts "CV Parser v#{CvParser::VERSION}"
          @options[:version] = true
          exit
        end
      end

      @parser.parse!(args)
    end

    def configure_parser
      CvParser.configure do |config|
        config.provider = @options[:provider] if @options[:provider]
        config.api_key = @options[:api_key] if @options[:api_key]

        # Try environment variables if not provided via options
        config.provider ||= (ENV["CV_PARSER_PROVIDER"]&.to_sym if ENV["CV_PARSER_PROVIDER"])

        # Configure based on provider
        case config.provider
        when :openai
          config.api_key ||= ENV["CV_PARSER_API_KEY"] || ENV.fetch("OPENAI_API_KEY", nil)
        when :anthropic
          config.api_key ||= ENV["CV_PARSER_API_KEY"] || ENV.fetch("ANTHROPIC_API_KEY", nil)
        when :faker
          config.api_key ||= "fake-api-key"
        else
          # Default to OpenAI if nothing specified
          config.provider = :openai
          config.api_key ||= ENV["CV_PARSER_API_KEY"] || ENV.fetch("OPENAI_API_KEY", nil)
        end
      end
    end

    def load_schema
      if @options[:schema_file]
        unless File.exist?(@options[:schema_file])
          puts "Error: Schema file '#{@options[:schema_file]}' not found"
          exit 1
        end

        begin
          JSON.parse(File.read(@options[:schema_file]))
        rescue JSON::ParserError => e
          puts "Error: Invalid JSON schema file: #{e.message}"
          exit 1
        end
      else
        DEFAULT_SCHEMA
      end
    end

    def extract_data(input_file, output_schema)
      puts "Parsing CV: #{input_file}"
      puts "Using provider: #{CvParser.configuration.provider}"

      extractor = CvParser::Extractor.new
      extractor.extract(file_path: input_file, output_schema: output_schema)
    end

    def output_result(result)
      formatted_output = case @options[:output_format]
                         when "yaml"
                           require "yaml"
                           result.to_yaml
                         else
                           JSON.pretty_generate(result)
                         end

      if @options[:output_file]
        File.write(@options[:output_file], formatted_output)
        puts "Output written to: #{@options[:output_file]}"
      else
        puts "\nResults:"
        puts formatted_output
      end
    end
  end
end
