# frozen_string_literal: true

# An ancestor for all the operation components.
# Holds shared methods.
class Operations::Components::Base
  include Dry::Monads[:result]
  extend Dry::Initializer

  MONADS_DO_WRAPPER_SIGNATURES = [
    [%i[rest *], %i[block &]],
    [%i[rest], %i[block &]], # Ruby 3.0, 3.1
    [%i[rest *], %i[keyrest **], %i[block &]],
    [%i[rest], %i[keyrest], %i[block &]] # Ruby 3.0, 3.1
  ].freeze
  DEFAULT_NAMES_MAP = { # Ruby 3.0, 3.1
    rest: "*",
    keyrest: "**"
  }.freeze

  param :callable, type: Operations::Types.Interface(:call)
  option :message_resolver, type: Operations::Types.Interface(:call), optional: true
  option :info_reporter, type: Operations::Types::Nil | Operations::Types.Interface(:call), optional: true
  option :error_reporter, type: Operations::Types::Nil | Operations::Types.Interface(:call), optional: true

  private

  def result(**options)
    ::Operations::Result.new(
      component: self.class.name.demodulize.underscore.to_sym,
      **options
    )
  end

  def call_args(callable, types:)
    (@call_args ||= {})[[callable, types]] ||= call_method(callable).parameters.filter_map do |(type, name)|
      name || DEFAULT_NAMES_MAP[type] if types.include?(type)
    end
  end

  def call_method(callable)
    method = callable.respond_to?(:parameters) ? callable : callable.method(:call)
    # calling super_method here because `Operations::Convenience`
    # calls `include Dry::Monads::Do.for(:call)` which creates
    # a delegator method around the original one.
    method = method.super_method if MONADS_DO_WRAPPER_SIGNATURES.include?(method.parameters)
    method
  end

  def errors(data)
    messages = Array.wrap(data).map do |datum|
      message_resolver.call(
        message: datum[:message],
        path: Array.wrap(datum[:path] || [nil]),
        tokens: datum[:tokens] || {},
        meta: datum[:meta] || {}
      )
    end

    Dry::Validation::MessageSet.new(messages).freeze
  end

  def normalize_failure(failure)
    case failure
    when Array
      failure.map { |f| normalize_failure(f) }
    when Hash
      {
        # Odd interface inconsistency in DRY: dry-validation's key().failure() requires `:text` key
        # while Message::Resolver requires `:message` key since it can be both: Symbol or String.
        # And `:error` alias key is just for personal preference.
        message: failure[:message] || failure[:text] || failure[:error],
        tokens: failure[:tokens],
        path: failure[:path],
        meta: failure.except(:message, :text, :error, :tokens, :path)
      }
    when String, Symbol
      { message: failure }
    else
      raise "Unexpected failure contents: #{failure}"
    end
  end
end
