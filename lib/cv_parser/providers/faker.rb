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
        # Generate fake data based on the provided schema
        generate_fake_data(output_schema)
      end

      def upload_file(file_path)
        # No-op for faker provider
        { id: "fake-file-#{SecureRandom.hex(8)}" }
      end

      private

      def generate_fake_data(schema)
        if schema.is_a?(Hash)
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

      def generate_value_for_type(type, key)
        if type.is_a?(Hash)
          generate_fake_data(type)
        elsif type.is_a?(Array)
          count = rand(1..3)
          Array.new(count) { generate_fake_data(type.first) }
        else
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
            if type.to_s.downcase == "string"
              "fake-#{key}-#{SecureRandom.hex(4)}"
            elsif %w[number integer].include?(type.to_s.downcase)
              rand(1..100)
            elsif type.to_s.downcase == "boolean"
              [true, false].sample
            else
              "fake-value"
            end
          end
        end
      end
    end
  end
end
