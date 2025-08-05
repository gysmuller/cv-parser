# frozen_string_literal: true

require "cv_parser"
require "rspec/support"
require "rspec/support/differ"
require "webmock/rspec"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Reset CvParser configuration before each test
  config.before(:each) do
    CvParser.reset
  end
end

# Helper to load fixture files
def fixture_path(filename)
  File.join(File.dirname(__FILE__), "fixtures", filename)
end
