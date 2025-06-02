# frozen_string_literal: true

require "spec_helper"

RSpec.describe CvParser::Providers::Faker do
  let(:config) do
    config = CvParser::Configuration.new
    config.provider = :faker
    config
  end

  let(:provider) { described_class.new(config) }

  describe "#extract_data" do
    context "with a basic schema" do
      let(:output_schema) do
        {
          name: "string",
          email: "string",
          phone: "string",
          skills: ["string"]
        }
      end

      it "returns fake data matching the schema structure" do
        result = provider.extract_data(output_schema: output_schema)

        expect(result).to be_a(Hash)
        expect(result["name"]).to eq("John Doe")
        expect(result["email"]).to eq("john.doe@example.com")
        expect(result["phone"]).to eq("+1 (555) 123-4567")
        expect(result["skills"]).to be_an(Array)
        expect(result["skills"].length).to be_between(1, 3).inclusive
        expect(result["skills"].first).to be_a(String)
      end
    end

    context "with a nested schema" do
      let(:output_schema) do
        {
          name: "string",
          experience: [
            {
              company: "string",
              title: "string",
              start_date: "string",
              end_date: "string"
            }
          ],
          education: [
            {
              university: "string",
              degree: "string",
              major: "string",
              year: "string"
            }
          ]
        }
      end

      it "returns fake data with the correct nested structure" do
        result = provider.extract_data(output_schema: output_schema)

        expect(result).to be_a(Hash)
        expect(result["name"]).to eq("John Doe")

        expect(result["experience"]).to be_an(Array)
        expect(result["experience"].length).to be_between(1, 3).inclusive
        expect(result["experience"].first["company"]).not_to be_nil
        expect(result["experience"].first["title"]).not_to be_nil
        expect(result["experience"].first["start_date"]).not_to be_nil
        expect(result["experience"].first["end_date"]).not_to be_nil

        expect(result["education"]).to be_an(Array)
        expect(result["education"].length).to be_between(1, 3).inclusive
        expect(result["education"].first["university"]).not_to be_nil
        expect(result["education"].first["degree"]).not_to be_nil
        expect(result["education"].first["major"]).not_to be_nil
        expect(result["education"].first["year"]).not_to be_nil
      end
    end
  end

  describe "#upload_file" do
    it "returns a fake file ID" do
      result = provider.upload_file("dummy/path/to/file.pdf")
      expect(result).to include(:id)
      expect(result[:id]).to start_with("fake-file-")
    end
  end
end
