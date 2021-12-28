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
module Operations::Convenience
  def self.extended(mod)
    mod.include Dry::Monads[:result]
    mod.include Dry::Monads::Do.for(:call)
    mod.extend Dry::Initializer
  end

  def contract(prefix = nil, from: OperationContract, &block)
    contract = Class.new(from, &block)
    contract.config.messages.namespace = name.underscore
    const_set("#{prefix.to_s.camelize}Contract", contract)
  end

  def policy(prefix = nil, from: Object, &block)
    raise ArgumentError.new("Please provide either a superclass or a block for policy") unless from || block

    policy = Class.new(from)
    policy.extend(Dry::Initializer) unless from
    policy.define_method(:call, &block) if block

    const_set("#{prefix.to_s.camelize}Policy", policy)
  end

  def precondition(prefix = nil, from: Object, &block)
    raise ArgumentError.new("Please provide either a superclass or a block for precondition") unless from || block

    precondition = Class.new(from)
    precondition.extend(Dry::Initializer) unless from
    precondition.define_method(:call, &block) if block

    const_set("#{prefix.to_s.camelize}Precondition", precondition)
  end
end
