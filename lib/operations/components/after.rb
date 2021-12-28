# frozen_string_literal: true

# This component handles `after:` callbacks passed to the
# composite. Every `after:` entry is called in a separate
# transaction and any exception is rescued here so the
# result of the whole operation is not affected.
# If there is a failure in any entry, it is reported with
# `error_reporter` proc.
class Operation::Components::After < Operation::Components::Base
  include Dry::Monads::Do.for(:call_entry)

  param :callable, type: Types::Array.of(Types.Interface(:call))

  def call(params, context)
    after_results = callable.map do |entry|
      call_entry(entry, params, **context)
    end

    maybe_report_failure(result(
      component: :operation,
      params: params,
      context: context,
      after: after_results
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
    if result.after.any?(Failure)
      error_reporter.call(
        "Operation side-effects went sideways",
        result: result.pretty_inspect
      )
    end

    result
  end
end
