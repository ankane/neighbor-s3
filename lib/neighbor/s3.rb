# dependencies
require "aws-sdk-s3vectors"

# modules
require_relative "s3/index"
require_relative "s3/version"

module Neighbor
  module S3
    class Error < StandardError; end

    class << self
      attr_writer :client

      def client
        @client ||= Aws::S3Vectors::Client.new
      end
    end
  end
end
