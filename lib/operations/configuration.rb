# frozen_string_literal: true

# The framework's configuration shared between all the commands.
#
# @see Operations.default_config
class Operations::Configuration
  extend Dry::Initializer

  option :info_reporter, Operations::Types.Interface(:call), optional: true
  option :error_reporter, Operations::Types.Interface(:call), optional: true
  option :transaction, Operations::Types.Interface(:call)

  def to_h
    self.class.dry_initializer.attributes(self)
  end
end
