# frozen_string_literal: true

require "securerandom"

module CvParser
  module Providers
    class Faker < Base
      def initialize(config)
        super
        @skills = ["Ruby", "JavaScript", "Python", "React", "Java", "C#", "PHP", "Go", "Swift", "Kotlin"]
        @job_titles = ["Software Engineer", "Full Stack Developer", "DevOps Engineer", "Data Scientist",
                       "Product Manager", "UX Designer", "Frontend Developer", "Backend Developer"]
        @companies = %w[Google Microsoft Amazon Facebook Apple Netflix Tesla Airbnb]
        @universities = ["Stanford University", "MIT", "Harvard", "Berkeley", "Oxford", "Cambridge"]
        @degrees = ["Bachelor of Science", "Master of Science", "PhD", "MBA"]
        @majors = ["Computer Science", "Software Engineering", "Electrical Engineering", "Data Science"]
      end

      def extract_data(output_schema:, file_path: nil)
        # Validate that we have a proper JSON Schema format
        unless output_schema.is_a?(Hash) &&
               ((output_schema.key?("type") && output_schema["type"] == "json_schema") ||
                (output_schema.key?(:type) && output_schema[:type] == "json_schema"))
          raise ArgumentError, "The Faker provider requires a JSON Schema format with 'type: \"json_schema\"'"
        end

        # Generate fake data based on the provided schema
        generate_fake_data(output_schema)
      end

      def upload_file(file_path)
        # No-op for faker provider
        { id: "fake-file-#{SecureRandom.hex(8)}" }
      end

      private

      def generate_fake_data(schema)
        # Handle JSON Schema format
        if schema.is_a?(Hash) &&
           ((schema.key?("type") && schema["type"] == "json_schema") ||
            (schema.key?(:type) && schema[:type] == "json_schema"))
          # Extract properties from JSON Schema format
          properties = schema["properties"] || schema[:properties] || {}
          generate_fake_data_from_properties(properties)
        elsif schema.is_a?(Hash)
          result = {}
          schema.each do |key, type|
            result[key.to_s] = generate_value_for_type(type, key)
          end
          result
        elsif schema.is_a?(Array) && !schema.empty?
          # For arrays, generate 1-3 items of the array's first element type
          count = rand(1..3)
          Array.new(count) { generate_fake_data(schema.first) }
        else
          "fake-value"
        end
      end

      # Helper method to generate fake data from schema properties
      def generate_fake_data_from_properties(properties)
        result = {}
        properties.each do |key, type|
          result[key.to_s] = generate_value_for_type(type, key)
        end
        result
      end

      def generate_value_for_type(type, key)
        # Handle JSON Schema property definitions
        if type.is_a?(Hash) && type.key?("type")
          case type["type"]
          when "object"
            generate_fake_data(type["properties"] || {})
          when "array"
            count = rand(1..3)
            Array.new(count) { generate_value_for_type(type["items"], key) }
          when "string"
            generate_string_value(key, type["description"])
          when "number", "integer"
            rand(1..100)
          when "boolean"
            [true, false].sample
          else
            "fake-value"
          end
        elsif type.is_a?(Hash) && type.key?(:type)
          # Handle symbol keys
          case type[:type]
          when "object"
            generate_fake_data(type[:properties] || {})
          when "array"
            count = rand(1..3)
            Array.new(count) { generate_value_for_type(type[:items], key) }
          when "string"
            generate_string_value(key, type[:description])
          when "number", "integer"
            rand(1..100)
          when "boolean"
            [true, false].sample
          else
            "fake-value"
          end
        elsif type.is_a?(Hash)
          generate_fake_data(type)
        elsif type.is_a?(Array)
          count = rand(1..3)
          Array.new(count) { generate_fake_data(type.first) }
        else
          generate_string_value(key, nil)
        end
      end

      def generate_string_value(key, description = nil)
        # Handle primitive types based on key name semantics
        case key.to_s.downcase
        when /name/
          "John Doe"
        when /email/
          "john.doe@example.com"
        when /phone/
          "+1 (555) 123-4567"
        when /address/
          "123 Main St, Anytown, CA 94088"
        when /summary/, /objective/, /description/
          "Lorem ipsum dolor sit amet, consectetur adipiscing elit."
        when /skill/
          @skills.sample
        when /title/, /position/, /role/
          @job_titles.sample
        when /company/, /employer/, /organization/
          @companies.sample
        when /university/, /school/, /college/
          @universities.sample
        when /degree/
          @degrees.sample
        when /major/, /field/
          @majors.sample
        when /year/, /years/
          rand(1..10).to_s
        when /start_date/, /start/
          "#{rand(2010..2020)}-#{format("%02d", rand(1..12))}-#{format("%02d", rand(1..28))}"
        when /end_date/, /end/
          "#{rand(2015..2022)}-#{format("%02d", rand(1..12))}-#{format("%02d", rand(1..28))}"
        when /date/
          "#{rand(2010..2023)}-#{format("%02d", rand(1..12))}-#{format("%02d", rand(1..28))}"
        when /url/, /website/, /link/
          "https://www.example.com"
        when /language/
          %w[English Spanish French German Mandarin].sample
        else
          "fake-#{key}-#{SecureRandom.hex(4)}"
        end
      end
    end
  end
end
