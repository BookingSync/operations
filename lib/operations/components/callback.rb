# frozen_string_literal: true

require "operations/components/base"

# This base component handles `on_failure:` and `on_success:` callbacks
# passed to the command. Every callback entry is called outside of the
# operation transaction and any exception is rescued here so the result
# of the whole operation is not affected. Additionally, any callback
# failures will be reported with the command error reporter.
# The original operation result will be optionally passed as the second
# positional argument for the `call` method.
class Operations::Components::Callback < Operations::Components::Base
  include Dry::Monads::Do.for(:call_entry)

  param :callable, type: Operations::Types::Array.of(Operations::Types.Interface(:call))

  private

  def call_entry(entry, operation_result, **context)
    result = yield(entry_result(entry, operation_result, **context))

    Success(result)
  rescue Dry::Monads::Do::Halt => e
    e.result
  rescue => e
    Failure(e)
  end

  def entry_result(entry, operation_result, **context)
    args = call_args(entry, types: %i[req opt])
    kwargs = call_args(entry, types: %i[key keyreq keyrest])

    case [args.size, kwargs.present?]
    when [1, true]
      entry.call(operation_result.params, **context)
    when [1, false]
      entry.call(operation_result)
    when [0, true]
      entry.call(**context)
    else
      raise "Invalid callback `#call` signature. Should be either `(params, **context)` or `(operation_result)`"
    end
  end

  def maybe_report_failure(callback_type, result)
    if result.public_send(callback_type).any?(Failure)
      error_reporter&.call(
        "Operation #{callback_type} side-effects went sideways",
        result: result.as_json(include_command: true)
      )
    end

    result
  end
end
