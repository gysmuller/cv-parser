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
          type: "json_schema",
          properties: {
            name: { type: "string" },
            email: { type: "string" },
            phone: { type: "string" },
            skills: {
              type: "array",
              items: { type: "string" }
            }
          }
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
          type: "json_schema",
          properties: {
            name: { type: "string" },
            experience: {
              type: "array",
              items: {
                type: "object",
                properties: {
                  company: { type: "string" },
                  title: { type: "string" },
                  start_date: { type: "string" },
                  end_date: { type: "string" }
                }
              }
            },
            education: {
              type: "array",
              items: {
                type: "object",
                properties: {
                  university: { type: "string" },
                  degree: { type: "string" },
                  major: { type: "string" },
                  year: { type: "string" }
                }
              }
            }
          }
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

  describe "#extract_data with text files" do
    let(:txt_file_path) { fixture_path("sample_resume.txt") }
    let(:md_file_path) { fixture_path("sample_resume.md") }
    let(:empty_file_path) { fixture_path("empty_resume.txt") }
    let(:output_schema) do
      {
        type: "json_schema",
        properties: {
          contact_information: {
            type: "object",
            properties: {
              name: { type: "string" },
              email: { type: "string" }
            }
          }
        }
      }
    end

    before do
      allow(File).to receive(:exist?).with(txt_file_path).and_return(true)
      allow(File).to receive(:readable?).with(txt_file_path).and_return(true)
      allow(File).to receive(:exist?).with(md_file_path).and_return(true)
      allow(File).to receive(:readable?).with(md_file_path).and_return(true)
    end

    context "with valid text files" do
      it "validates and processes txt files" do
        result = provider.extract_data(output_schema: output_schema, file_path: txt_file_path)

        expect(result).to be_a(Hash)
        expect(result).to include("contact_information")
        expect(result["contact_information"]).to include("name")
      end

      it "validates and processes markdown files" do
        result = provider.extract_data(output_schema: output_schema, file_path: md_file_path)

        expect(result).to be_a(Hash)
        expect(result).to include("contact_information")
      end

      it "works without file_path" do
        result = provider.extract_data(output_schema: output_schema)

        expect(result).to be_a(Hash)
      end
    end

    context "with empty text file" do
      before do
        allow(File).to receive(:exist?).with(empty_file_path).and_return(true)
        allow(File).to receive(:readable?).with(empty_file_path).and_return(true)
      end

      it "raises EmptyTextFileError" do
        expect do
          provider.extract_data(output_schema: output_schema, file_path: empty_file_path)
        end.to raise_error(CvParser::EmptyTextFileError)
      end
    end

    context "with non-existent file" do
      it "raises FileNotFoundError" do
        allow(File).to receive(:exist?).with("non_existent.txt").and_return(false)

        expect do
          provider.extract_data(output_schema: output_schema, file_path: "non_existent.txt")
        end.to raise_error(CvParser::FileNotFoundError)
      end
    end
  end
end
