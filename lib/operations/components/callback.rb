# frozen_string_literal: true

require "operations/components/base"

# This base component handles `on_failure:` and `on_success` callbacks
# passed to the command. Every callback entry is called outside of the
# operation transaction and any exception is rescued here so the result
# of the whole operation is not affected. Additionally, any callback
# failures will be reported with the command error reporter.
class Operations::Components::Callback < Operations::Components::Base
  include Dry::Monads::Do.for(:call_entry)

  param :callable, type: Operations::Types::Array.of(Operations::Types.Interface(:call))

  private

  def call_entry(entry, params, **context)
    result = yield(entry_result(entry, params, **context))

    Success(result)
  rescue Dry::Monads::Do::Halt => e
    e.result
  rescue => e
    Failure(e)
  end

  def entry_result(entry, params, **context)
    args = call_args(entry, types: %i[req opt])

    if args.one?
      entry.call(params, **context)
    else
      entry.call(**context)
    end
  end

  def maybe_report_failure(callback_type, result)
    if result.public_send(callback_type).any?(Failure)
      error_reporter&.call(
        "Operation #{callback_type} side-effects went sideways",
        result: result.as_json
      )
    end

    result
  end
end
