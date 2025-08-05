# frozen_string_literal: true

require "securerandom"

module CvParser
  module Providers
    class Faker < Base
      # Sample data constants
      SKILLS = ["Ruby", "JavaScript", "Python", "React", "Java", "C#", "PHP", "Go", "Swift", "Kotlin"].freeze
      JOB_TITLES = ["Software Engineer", "Full Stack Developer", "DevOps Engineer", "Data Scientist",
                    "Product Manager", "UX Designer", "Frontend Developer", "Backend Developer"].freeze
      COMPANIES = %w[Google Microsoft Amazon Facebook Apple Netflix Tesla Airbnb].freeze
      UNIVERSITIES = ["Stanford University", "MIT", "Harvard", "Berkeley", "Oxford", "Cambridge"].freeze
      DEGREES = ["Bachelor of Science", "Master of Science", "PhD", "MBA"].freeze
      MAJORS = ["Computer Science", "Software Engineering", "Electrical Engineering", "Data Science"].freeze
      LANGUAGES = %w[English Spanish French German Mandarin].freeze

      # Date ranges
      START_YEAR_RANGE = (2010..2020).freeze
      END_YEAR_RANGE = (2015..2022).freeze
      GENERAL_YEAR_RANGE = (2010..2023).freeze

      # Array size range
      ARRAY_SIZE_RANGE = (1..3).freeze

      # Schema types
      JSON_SCHEMA_TYPE = "json_schema"

      def extract_data(output_schema:, file_path: nil)
        validate_inputs!(output_schema, file_path)
        generate_fake_data(output_schema)
      end

      def upload_file(_file_path)
        # No-op for faker provider
        { id: "fake-file-#{SecureRandom.hex(8)}" }
      end

      private

      def validate_inputs!(output_schema, file_path)
        validate_schema_format!(output_schema)

        # Validate file if provided
        return unless file_path

        validate_file_exists!(file_path)
        validate_file_readable!(file_path)

        # For text files, validate content
        return unless text_file?(file_path)

        read_text_file_content(file_path) # Just for validation
      end

      def validate_schema_format!(output_schema)
        return if valid_json_schema_format?(output_schema)

        raise ArgumentError, "The Faker provider requires a JSON Schema format with 'type: \"json_schema\"'"
      end

      def valid_json_schema_format?(schema)
        schema.is_a?(Hash) &&
          ((schema.key?("type") && schema["type"] == JSON_SCHEMA_TYPE) ||
           (schema.key?(:type) && schema[:type] == JSON_SCHEMA_TYPE))
      end

      def generate_fake_data(schema)
        return generate_fake_data_from_json_schema(schema) if json_schema_format?(schema)
        return generate_fake_data_from_hash(schema) if schema.is_a?(Hash)
        return generate_fake_data_from_array(schema) if schema.is_a?(Array) && !schema.empty?

        "fake-value"
      end

      def json_schema_format?(schema)
        schema.is_a?(Hash) &&
          ((schema.key?("type") && schema["type"] == JSON_SCHEMA_TYPE) ||
           (schema.key?(:type) && schema[:type] == JSON_SCHEMA_TYPE))
      end

      def generate_fake_data_from_json_schema(schema)
        properties = extract_properties_from_schema(schema)
        generate_fake_data_from_properties(properties)
      end

      def extract_properties_from_schema(schema)
        schema["properties"] || schema[:properties] || {}
      end

      def generate_fake_data_from_hash(schema)
        result = {}
        schema.each do |key, type|
          result[key.to_s] = generate_value_for_type(type, key)
        end
        result
      end

      def generate_fake_data_from_array(schema)
        count = rand(ARRAY_SIZE_RANGE)
        Array.new(count) { generate_fake_data(schema.first) }
      end

      def generate_fake_data_from_properties(properties)
        result = {}
        properties.each do |key, type|
          result[key.to_s] = generate_value_for_type(type, key)
        end
        result
      end

      def generate_value_for_type(type, key)
        return generate_value_from_typed_hash(type, key) if typed_hash?(type)
        return generate_fake_data(type) if type.is_a?(Hash)
        return generate_fake_data_from_array(type) if type.is_a?(Array)

        generate_string_value(key, nil)
      end

      def typed_hash?(type)
        type.is_a?(Hash) && (type.key?("type") || type.key?(:type))
      end

      def generate_value_from_typed_hash(type, key)
        schema_type = type["type"] || type[:type]
        description = type["description"] || type[:description]

        case schema_type
        when "object"
          properties = type["properties"] || type[:properties] || {}
          generate_fake_data(properties)
        when "array"
          items = type["items"] || type[:items]
          count = rand(ARRAY_SIZE_RANGE)
          Array.new(count) { generate_value_for_type(items, key) }
        when "string"
          generate_string_value(key, description)
        when "number", "integer"
          rand(1..100)
        when "boolean"
          [true, false].sample
        else
          "fake-value"
        end
      end

      def generate_string_value(key, _description = nil)
        key_string = key.to_s.downcase

        case key_string
        when /name/
          generate_name_value
        when /email/
          generate_email_value
        when /phone/
          generate_phone_value
        when /address/
          generate_address_value
        when /summary/, /objective/, /description/
          generate_description_value
        when /skill/
          SKILLS.sample
        when /title/, /position/, /role/
          JOB_TITLES.sample
        when /company/, /employer/, /organization/
          COMPANIES.sample
        when /university/, /school/, /college/
          UNIVERSITIES.sample
        when /degree/
          DEGREES.sample
        when /major/, /field/
          MAJORS.sample
        when /year/, /years/
          generate_years_value
        when /start_date/, /start/
          generate_date_value(START_YEAR_RANGE)
        when /end_date/, /end/
          generate_date_value(END_YEAR_RANGE)
        when /date/
          generate_date_value(GENERAL_YEAR_RANGE)
        when /url/, /website/, /link/
          generate_url_value
        when /language/
          LANGUAGES.sample
        else
          generate_default_value(key)
        end
      end

      def generate_name_value
        "John Doe"
      end

      def generate_email_value
        "john.doe@example.com"
      end

      def generate_phone_value
        "+1 (555) 123-4567"
      end

      def generate_address_value
        "123 Main St, Anytown, CA 94088"
      end

      def generate_description_value
        "Lorem ipsum dolor sit amet, consectetur adipiscing elit."
      end

      def generate_years_value
        rand(1..10).to_s
      end

      def generate_date_value(year_range)
        year = rand(year_range)
        month = format("%02d", rand(1..12))
        day = format("%02d", rand(1..28))
        "#{year}-#{month}-#{day}"
      end

      def generate_url_value
        "https://www.example.com"
      end

      def generate_default_value(key)
        "fake-#{key}-#{SecureRandom.hex(4)}"
      end
    end
  end
end
