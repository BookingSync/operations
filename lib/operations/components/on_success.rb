# frozen_string_literal: true

require "operations/components/base"

# This component handles `on_success:` callbacks passed to the
# composite. Every `on_success:` entry is called in a separate
# transaction and any exception is rescued here so the
# result of the whole operation is not affected.
# If there is a failure in any entry, it is reported with
# `error_reporter` proc.
class Operations::Components::OnSuccess < Operations::Components::Base
  include Dry::Monads::Do.for(:call_entry)

  param :callable, type: Operations::Types::Array.of(Operations::Types.Interface(:call))

  def call(params, context)
    on_success_results = callable.map do |entry|
      call_entry(entry, params, **context)
    end

    maybe_report_failure(result(
      component: :operation,
      params: params,
      context: context,
      on_success: on_success_results
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
    if result.on_success.any?(Failure)
      error_reporter&.call(
        "Operation on_success side-effects went sideways",
        result: result.as_json
      )
    end

    result
  end
end
