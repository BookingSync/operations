# frozen_string_literal: true

require "operations/components/base"

# An ancestor for all the operation callbacks.
# Holds shared methods.
class Operations::Components::BaseCallback < Operations::Components::Base
  include Dry::Monads::Do.for(:call_entry)

  param :callable, type: Operations::Types::Array.of(Operations::Types.Interface(:call))

  def self.inherited(subclass)
    super

    subclass.const_set(:CALLBACK_NAME, subclass.name.demodulize.underscore.to_sym)
  end

  def call(params, context)
    results = callable.map do |entry|
      call_entry(entry, params, **context)
    end

    maybe_report_failure(result(
      component: :operation,
      params: params,
      context: context,
      self.class::CALLBACK_NAME => results
    ))
  end

  private

  def call_entry(entry, params, **context)
    args = call_args(entry, types: %i[req opt])

    result = transaction.call do
      yield(args.one? ? entry.call(params, **context) : entry.call(**context))
    end

    Success(result)
  rescue Dry::Monads::Do::Halt => e
    e.result
  rescue => e
    Failure(e)
  end

  def maybe_report_failure(result)
    if result.public_send(self.class::CALLBACK_NAME).any?(Failure)
      error_reporter&.call(
        "Operation #{self.class::CALLBACK_NAME} side-effects went sideways",
        result: result.as_json
      )
    end

    result
  end
end
