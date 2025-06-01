# frozen_string_literal: true

RSpec.describe CvParser do
  it "has a version number" do
    expect(CvParser::VERSION).not_to be nil
  end

  it "defines the main module" do
    expect(CvParser).to be_a(Module)
  end
end
