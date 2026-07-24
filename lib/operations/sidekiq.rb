# frozen_string_literal: true

require "operations"
require "sidekiq"

# A parent module for Operations::Sidekiq::Convenience,
# defines constants and helpers used to run operations
# asynchronously via Sidekiq.
#
# This part of the framework is optional and must be required
# explicitly:
#
#   require "operations/sidekiq"
#
# It expects Sidekiq to be available. Serialization of `Money`
# and GlobalID-able objects is supported when those libraries
# are loaded but they are not hard dependencies.
#
# @see Operations::Sidekiq::Convenience
module Operations::Sidekiq
  SIDEKIQ_TYPE_KEY = "$sidekiq_type"
  SIDEKIQ_VALUE_KEY = "$sidekiq_value"
  SIDEKIQ_SYMBOL_KEYS = "$sidekiq_symbol_keys"

  def self.operation_container(operation)
    container_class = operation.respond_to?(:operation) ? operation.operation.class : operation.class

    raise "Unable to perform async anonymous operation #{container_class}" unless container_class.name

    container_method = container_class.singleton_methods(false).find do |name|
      container_class.send(name) == operation if container_class.method(name).arity.zero?
    end

    raise "Unable to find the appropriate command for the operation" unless container_method

    [container_class, container_method]
  end
end

require "operations/sidekiq/serializer"
require "operations/sidekiq/deserializer"
require "operations/sidekiq/job"
require "operations/sidekiq/command"
require "operations/sidekiq/convenience"
