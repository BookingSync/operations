# frozen_string_literal: true

# This module helps to follow conventions. Work best with
# {Operations::Command.build}
#
# Unders the hood it defines classes in accordance to the
# nesting convenience. It is always possible to use this module
# along with the manually crafted components if necessary.
#
# @example
#
#   class Namespace::OperationName
#     extend Operations::Convenience
#
#     contract do
#       params { ... }
#       rule(...) { ... }
#     end
#
#     policy do |current_user, **|
#       current_user.is_a?(Superuser) && ...
#     end
#
#     def call(context_value1, context_value2, **params)
#       ...
#     end
#   end
#
# @see Operations::Command.build
#
# Also, if this class is used as a container to cache the command
# instance under some name, this module will provide a method missing
# to call the command with `#call!` method using the `#call` method
# as an interface.
#
# @example
#
#   class Namespace::OperationName
#     extend Operations::Convenience
#
#     def self.default
#       Operations::Command.new(...)
#     end
#   end
#
#   # A normall command call
#   Namespace::OperationName.default.call(...)
#   # Raises exception in case of failure
#   Namespace::OperationName.default.call!(...)
#   # Acts exactly the same way as the previous one
#   # but notice where the bang is.
#   Namespace::OperationName.default!.call(...)
#
# This is especially convenient when you have a DSL that
# expects some object responding to `#call` method but you want
# to raise an exception. In this case you would just pass
# `Namespace::OperationName.default!` into it.
#
module Operations::Convenience
  def self.extended(mod)
    mod.include Dry::Monads[:result]
    mod.include Dry::Monads::Do.for(:call)
    mod.extend Dry::Initializer
  end

  def method_missing(name, *args, **kwargs, &block)
    name_without_suffix = name.to_s.delete_suffix("!").to_sym
    if name.to_s.end_with?("!") && respond_to?(name_without_suffix)
      public_send(name_without_suffix, *args, **kwargs, &block).method(:call!)
    else
      super
    end
  end

  def respond_to_missing?(name, *)
    (name.to_s.end_with?("!") && respond_to?(name.to_s.delete_suffix("!").to_sym)) || super
  end

  def contract(prefix = nil, from: OperationContract, &block)
    contract = Class.new(from)
    contract.config.messages.namespace = name.underscore
    contract.class_eval(&block)
    const_set(:"#{prefix.to_s.camelize}Contract", contract)
  end

  %w[policy precondition callback].each do |kind|
    define_method kind do |prefix = nil, from: Object, &block|
      raise ArgumentError.new("Please provide either a superclass or a block for #{kind}") unless from || block

      klass = Class.new(from)

      if from == Object
        klass.extend(Dry::Initializer)
        klass.include(Dry::Monads[:result])
      end

      klass.define_method(:call, &block) if block

      const_set(:"#{prefix.to_s.camelize}#{kind.camelize}", klass)
    end
  end
end
