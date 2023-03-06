# frozen_string_literal: true

require "dry-struct"

# The framework's configuration shared between all the commands.
#
# @see Operations.default_config
class Operations::Configuration < Dry::Struct
  schema schema.strict

  attribute :info_reporter?, Operations::Types.Interface(:call).optional
  attribute :error_reporter?, Operations::Types.Interface(:call).optional
  attribute :transaction, Operations::Types.Interface(:call)
  attribute :after_commit, Operations::Types.Interface(:call)
end
