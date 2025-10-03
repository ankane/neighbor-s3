require_relative "lib/neighbor/s3/version"

Gem::Specification.new do |spec|
  spec.name          = "neighbor-s3"
  spec.version       = Neighbor::S3::VERSION
  spec.summary       = "Nearest neighbor search for Ruby and S3 Vectors"
  spec.homepage      = "https://github.com/ankane/neighbor-s3"
  spec.license       = "MIT"

  spec.author        = "Andrew Kane"
  spec.email         = "andrew@ankane.org"

  spec.files         = Dir["*.{md,txt}", "{lib}/**/*"]
  spec.require_path  = "lib"

  spec.required_ruby_version = ">= 3.2"

  spec.add_dependency "aws-sdk-s3vectors"
end
