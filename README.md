# CV Parser

A Ruby gem for parsing and extracting structured information from CVs/resumes using LLM providers.

## Features
- Convert DOCX to PDF before uploading to LLM providers
- Extract structured data from CVs by directly uploading files to LLM providers
- Configure different LLM providers (OpenAI and Anthropic)
- Customizable output schema to match your data requirements
- Command-line interface for quick parsing and analysis
- Robust error handling and validation

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'cv-parser'
```

And then execute:

```bash
$ bundle install
```

Or install it yourself as:

```bash
$ gem install cv-parser
```

## Dependencies

This gem requires the following dependencies:

- Ruby 2.6.0 or higher


## Usage

### Command-Line Interface

CV Parser comes with a command-line interface for quick resume analysis:

```bash
# Basic usage - parse a resume
cv-parser path/to/resume.pdf

# Specify a different provider
cv-parser --provider anthropic path/to/resume.pdf

# Output as YAML and save to file
cv-parser --format yaml --output result.yaml path/to/resume.pdf

# Use a custom schema
cv-parser --schema custom-schema.json path/to/resume.pdf

# Show help
cv-parser --help
```

#### CLI Options

The following command-line options are available:

| Option | Description |
|--------|-------------|
| `-p, --provider PROVIDER` | LLM Provider to use (openai or anthropic) |
| `-k, --api-key API_KEY` | API key for the LLM provider |
| `-f, --format FORMAT` | Output format (json or yaml) |
| `-o, --output FILE` | Write output to file instead of stdout |
| `-s, --schema FILE` | Custom schema file (JSON) for the output structure |
| `-h, --help` | Show help message |
| `-v, --version` | Show version |

#### Environment Variables

You can also use environment variables instead of command-line options:

```bash
# Set API keys
export OPENAI_API_KEY=your-openai-key
export ANTHROPIC_API_KEY=your-anthropic-key

# Set default provider
export CV_PARSER_PROVIDER=openai
export CV_PARSER_API_KEY=your-api-key

# Then run without specifying keys on command line
cv-parser resume.pdf
```

See the full CLI documentation in [examples/cli_usage.md](examples/cli_usage.md).

### Basic Configuration

```ruby
require 'cv_parser'

# Configure with OpenAI
CvParser.configure do |config|
  config.configure_openai(access_token: ENV['OPENAI_API_KEY'])
  config.model = 'gpt-4.1-mini'
end

# Or configure with Anthropic
CvParser.configure do |config|
  config.configure_anthropic(api_key: ENV['ANTHROPIC_API_KEY'])
  config.model = 'claude-3-sonnet-20240229'  # Optional
end
```

### Defining an Output Schema

Define the schema that represents how you want the CV data structured:

```ruby
schema = {
  personal_info: {
    name: "string",
    email: "string",
    phone: "string",
    location: "string"
  },
  experience: [
    {
      company: "string",
      position: "string",
      start_date: "string",
      end_date: "string",
      description: "string"
    }
  ],
  education: [
    {
      institution: "string",
      degree: "string",
      field: "string",
      graduation_date: "string"
    }
  ],
  skills: ["string"]
}
```

### Extracting Data from a CV

```ruby
# Create an extractor instance
extractor = CvParser::Extractor.new

# Upload and process a CV file
result = extractor.extract(
  file_path: "path/to/resume.pdf",
  output_schema: schema
)

# Access extracted data
puts "Name: #{result['personal_info']['name']}"
puts "Email: #{result['personal_info']['email']}"

# Print all skills
result['skills'].each do |skill|
  puts "- #{skill}"
end
```

### Error Handling

```ruby
begin
  result = extractor.extract(
    file_path: "path/to/resume.pdf",
    output_schema: schema
  )
  # Process result
rescue CvParser::FileNotFoundError, CvParser::FileNotReadableError => e
  puts "File error: #{e.message}"
rescue CvParser::ParseError => e
  puts "Error parsing the response: #{e.message}"
rescue CvParser::APIError => e
  puts "LLM API error: #{e.message}"
rescue CvParser::ConfigurationError => e
  puts "Configuration error: #{e.message}"
end
```

## Advanced Configuration

```ruby
CvParser.configure do |config|
  # Configure OpenAI with organization ID
  config.configure_openai(
    access_token: ENV['OPENAI_API_KEY'],
    organization_id: ENV['OPENAI_ORG_ID']
  )
  
  # Set timeout for file uploads (important for larger files)
  config.timeout = 120  # Default: 60 seconds
  config.max_retries = 2  # Default: 3
end
```

## How It Works

CV Parser uploads the CV file directly to the LLM provider (OpenAI or Anthropic) and instructs the model to extract structured information according to your schema. This approach offers several advantages:

1. **Better context preservation** - The LLM can see the original document with its formatting and layout intact
2. **Support for more formats** - Any file format the LLM provider supports can be processed
3. **Simplified processing** - No need for complex document parsing libraries

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/gysmuller/cv-parser.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT). 