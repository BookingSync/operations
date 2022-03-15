# frozen_string_literal: true

# The framework's configuration shared between all the commands.
#
# @see Operations.default_config
class Operations::Configuration
  extend Dry::Initializer

  option :error_reporter, Operations::Types.Interface(:call)
  option :transaction, Operations::Types.Interface(:call)
end
