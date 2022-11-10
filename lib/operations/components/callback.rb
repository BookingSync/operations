# frozen_string_literal: true

require "operations/components/base"

# This component handles `on_failure:` and `on_success` callbacks passed to the
# composite. Every callback entry is called in a separate
# transaction and any exception is rescued here so the
# result of the whole operation is not affected.
# If there is a failure in any entry, it is reported with a proc.
class Operations::Components::Callback < Operations::Components::Base
  include Dry::Monads::Do.for(:call_entry)

  CALLBACK_TYPES = %i[on_success on_failure].freeze

  param :callable, type: Operations::Types::Array.of(Operations::Types.Interface(:call))
  option :callback_type, type: Operations::Types::Coercible::Symbol.constrained(included_in: CALLBACK_TYPES)

  def call(params, context)
    results = callable.map do |entry|
      call_entry(entry, params, **context)
    end

    maybe_report_failure(result(
      component: :operation,
      params: params,
      context: context,
      callback_type => results
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
    if result.public_send(callback_type).any?(Failure)
      error_reporter&.call(
        "Operation #{callback_type} side-effects went sideways",
        result: result.as_json
      )
    end

    result
  end
end
