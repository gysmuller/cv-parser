# CV Parser

A Ruby gem for parsing and extracting structured information from CVs/resumes using LLM providers.

## Features
- Convert DOCX to PDF before uploading to LLM providers
- Extract structured data from CVs by directly uploading files to LLM providers
- Configure different LLM providers (OpenAI, Anthropic, and Faker for testing)
- Customizable output schema to match your data requirements (JSON Schema format)
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

## Usage

### Using in Rails

You can use CV Parser directly in your Ruby or Rails application to extract structured data from CVs. 

#### Basic Configuration

You can configure the gem for different providers:

```ruby
require 'cv_parser'

# OpenAI
CvParser.configure do |config|
  config.provider = :openai
  config.api_key = ENV['OPENAI_API_KEY']
  config.model = 'gpt-4.1-mini'
  config.output_schema = schema
end

# Anthropic
CvParser.configure do |config|
  config.provider = :anthropic
  config.api_key = ENV['ANTHROPIC_API_KEY']
  config.model = 'claude-3-sonnet-20240229'
  config.output_schema = schema
end

# Faker (for testing/development)
CvParser.configure do |config|
  config.provider = :faker
  config.output_schema = schema
end
```

#### Defining an Output Schema

Define the schema for the data you want to extract using JSON Schema format:

```ruby
schema = {
  type: "json_schema",
  name: "cv_parsing",
  description: "Schema for a CV or resume document",
  properties: {
    personal_info: {
      type: "object",
      description: "Personal and contact information for the candidate",
      properties: {
        name: {
          type: "string",
          description: "Full name of the individual"
        },
        email: {
          type: "string",
          description: "Email address of the individual"
        },
        phone: {
          type: "string",
          description: "Phone number of the individual"
        },
        location: {
          type: "string",
          description: "Geographic location or city of residence"
        }
      },
      required: %w[name email]
    },
    experience: {
      type: "array",
      description: "List of professional experience entries",
      items: {
        type: "object",
        description: "A professional experience entry",
        properties: {
          company: {
            type: "string",
            description: "Name of the company or organization"
          },
          position: {
            type: "string",
            description: "Job title or position held"
          },
          start_date: {
            type: "string",
            description: "Start date of employment (e.g. '2020-01')"
          },
          end_date: {
            type: "string",
            description: "End date of employment or 'present'"
          },
          description: {
            type: "string",
            description: "Description of responsibilities and achievements"
          }
        },
        required: %w[company position start_date]
      }
    },
    education: {
      type: "array",
      description: "List of educational qualifications",
      items: {
        type: "object",
        description: "An education entry",
        properties: {
          institution: {
            type: "string",
            description: "Name of the educational institution"
          },
          degree: {
            type: "string",
            description: "Degree or certification received"
          },
          field: {
            type: "string",
            description: "Field of study"
          },
          graduation_date: {
            type: "string",
            description: "Graduation date (e.g. '2019-06')"
          }
        },
        required: %w[institution degree]
      }
    },
    skills: {
      type: "array",
      description: "List of relevant skills",
      items: {
        type: "string",
        description: "A single skill"
      }
    }
  },
  required: %w[personal_info experience education skills]
}
```

Set the output schema in the configuration block:

```ruby
CvParser.configure do |config|
  config.output_schema = schema
end
```

You can also set the output schema in the extractor method which will override the configuration block:

```ruby
extractor = CvParser::Extractor.new
extractor.extract(
  output_schema: schema
)
```

#### Extracting Data from a CV

```ruby
extractor = CvParser::Extractor.new
result = extractor.extract(
  file_path: "path/to/resume.pdf"
)

puts "Name: #{result['personal_info']['name']}"
puts "Email: #{result['personal_info']['email']}"
result['skills'].each { |skill| puts "- #{skill}" }
```

#### Error Handling

```ruby
begin
  result = extractor.extract(
    file_path: "path/to/resume.pdf"
  )
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

---

### Command-Line Interface

CV Parser also provides a CLI for quick analysis:

```bash
cv-parser path/to/resume.pdf
cv-parser --provider anthropic path/to/resume.pdf
cv-parser --format yaml --output result.yaml path/to/resume.pdf
cv-parser --schema custom-schema.json path/to/resume.pdf
cv-parser --help
```

You can use environment variables for API keys and provider selection:

```bash
export OPENAI_API_KEY=your-openai-key
export ANTHROPIC_API_KEY=your-anthropic-key
export CV_PARSER_PROVIDER=openai
export CV_PARSER_API_KEY=your-api-key
cv-parser resume.pdf
```

See the full CLI documentation and options in [examples/cli_usage.md](examples/cli_usage.md).

---

### Testing and Development

#### Using the Faker Provider

The Faker provider generates realistic-looking fake data based on your schema, without making API calls. This is useful for:
- Writing tests (RSpec, Rails, etc.)
- Developing UI components
- Demonstrating functionality without API keys
- Avoiding API costs and rate limits

**RSpec Example:**

```ruby
# spec/your_resume_processor_spec.rb
require 'spec_helper'

RSpec.describe YourResumeProcessor do
  # Define a JSON Schema format schema for testing
  let(:test_schema) do
    {
      type: "json_schema",
      name: "cv_parsing_test",
      description: "Test schema for CV parsing",
      properties: {
        personal_info: {
          type: "object",
          description: "Personal information",
          properties: {
            name: {
              type: "string",
              description: "Full name"
            },
            email: {
              type: "string",
              description: "Email address"
            }
          },
          required: %w[name email]
        },
        skills: {
          type: "array",
          description: "List of skills",
          items: {
            type: "string",
            description: "A skill"
          }
        }
      },
      required: %w[personal_info skills]
    }
  end

  before do
    # Configure CV Parser to use the faker provider
    CvParser.configure do |config|
      config.provider = :faker
    end
  end

  after do
    # Reset configuration after tests
    CvParser.reset
  end

  it "processes a resume and extracts relevant fields" do
    processor = YourResumeProcessor.new
    result = processor.process_resume("spec/fixtures/sample_resume.pdf", test_schema)
    
    # The faker provider will return consistent test data
    expect(result.personal_info.name).to eq("John Doe")
    expect(result.personal_info.email).to eq("john.doe@example.com")
    expect(result.skills).to be_an(Array)
    expect(result.skills).not_to be_empty
  end
end
```

You can also use the Faker provider in development by toggling with an environment variable (see above).

## Advanced Configuration

You can further customize CV Parser by setting advanced options in the configuration block. For example:

```ruby
CvParser.configure do |config|
  # Configure OpenAI with organization ID
  config.provider = :openai
  config.api_key = ENV['OPENAI_API_KEY']
  config.model = 'gpt-4.1-mini'
  
  # Set timeout for file uploads (important for larger files)
  config.timeout = 120  # Default: 60 seconds
  config.max_retries = 2  # Default: 3
  
  # Provider-specific options
  config.provider_options[:organization_id] = ENV['OPENAI_ORG_ID']

  # You can also set custom prompts for the LLM:
  config.prompt = "Extract the following fields from the CV..."
  config.system_prompt = "You are a CV parsing assistant."
  config.output_schema = schema
  config.max_tokens = 4000
  config.temperature = 0.1
end
```

## How It Works

CV Parser uploads the CV file directly to the LLM provider (OpenAI or Anthropic) and instructs the model to extract structured information according to your schema.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`.

## Testing Your Application

### Using the Faker Provider in Tests

The CV Parser gem includes a faker provider specifically designed for testing environments. This allows you to write tests for your application without making actual API calls to OpenAI or Anthropic, which has several benefits:

1. Tests run faster without external API calls
2. No API costs during test runs
3. Consistent, predictable results
4. No need for API keys in CI/CD environments

#### Basic Test Setup

Here's how to use the faker provider in your RSpec tests:

```ruby
# spec/your_resume_processor_spec.rb
require 'spec_helper'

RSpec.describe YourResumeProcessor do
  # Define a JSON Schema format schema for testing
  let(:test_schema) do
    {
      type: "json_schema",
      name: "cv_parsing_test",
      description: "Test schema for CV parsing",
      properties: {
        personal_info: {
          type: "object",
          description: "Personal information",
          properties: {
            name: {
              type: "string",
              description: "Full name"
            },
            email: {
              type: "string",
              description: "Email address"
            }
          },
          required: %w[name email]
        },
        skills: {
          type: "array",
          description: "List of skills",
          items: {
            type: "string",
            description: "A skill"
          }
        }
      },
      required: %w[personal_info skills]
    }
  end

  before do
    # Configure CV Parser to use the faker provider
    CvParser.configure do |config|
      config.provider = :faker
    end
  end

  after do
    # Reset configuration after tests
    CvParser.reset
  end

  it "processes a resume and extracts relevant fields" do
    processor = YourResumeProcessor.new
    result = processor.process_resume("spec/fixtures/sample_resume.pdf", test_schema)
    
    # The faker provider will return consistent test data
    expect(result.personal_info.name).to eq("John Doe")
    expect(result.personal_info.email).to eq("john.doe@example.com")
    expect(result.skills).to be_an(Array)
    expect(result.skills).not_to be_empty
  end
end
```

#### Using in Rails Tests

In a Rails application, you might configure the faker provider in your test environment:

```ruby
# config/environments/test.rb
Rails.application.configure do
  # ... other configuration

  # Configure CV Parser with faker for testing
  config.after_initialize do
    CvParser.configure do |config|
      config.provider = :faker
    end
  end
end
```

#### Customizing Faker Output for Tests

The faker provider generates realistic-looking data based on your schema. The data is deterministic for fields like name, email, and phone, but randomized for arrays and collections. You can write tests that check for structure without relying on specific content for variable fields.

### Using the Faker Provider for Development

You can also use the faker provider during development to avoid consuming API quotas:

```ruby
# In development.rb or through your app's configuration
if Rails.env.development? && ENV['USE_FAKER'] == 'true'
  CvParser.configure do |config|
    config.provider = :faker
  end
end
```

Then use an environment variable to toggle between real APIs and the faker:

```bash
# Use faker provider for development
USE_FAKER=true rails server

# Use real API (when needed)
USE_FAKER=false rails server
```

## Testing with Faker Provider

For testing purposes, CV Parser includes a faker provider that generates realistic-looking fake data based on your schema structure without making actual API calls:

```ruby
# Configure with Faker provider
CvParser.configure do |config|
  config.provider = :faker
end

# Use the extractor as normal
extractor = CvParser::Extractor.new
result = extractor.extract(
  file_path: "path/to/resume.pdf",  # Path will be ignored by faker
  output_schema: schema  # Using the JSON Schema format defined above
)

# Faker will generate structured data based on your schema
puts result.inspect
```

This is particularly useful for:
- Writing tests without making API calls
- Developing UI components that consume CV data
- Demonstrating functionality without API keys