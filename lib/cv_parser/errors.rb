# frozen_string_literal: true

module CvParser
  class Error < StandardError; end
  class ConfigurationError < Error; end
  class UnsupportedFormat < Error; end
  class ParseError < Error; end
  class APIError < Error; end
  class RateLimitError < APIError; end
  class AuthenticationError < APIError; end
  class InvalidRequestError < APIError; end
  class FileNotFoundError < Error; end
  class FileNotReadableError < Error; end
end
