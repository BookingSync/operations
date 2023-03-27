# frozen_string_literal: true

require "operations/components/callback"

# `on_failure` callbacks are called if a command have failed on a stage
# other than the operation itself or contract. I.e. on policies/preconditions.
class Operations::Components::OnFailure < Operations::Components::Callback
  def call(operation_result)
    callback_context = operation_result.context.merge(operation_failure: operation_result.errors.to_h)
    results = callable.map do |entry|
      call_entry(entry, operation_result, **callback_context)
    end

    maybe_report_failure(:on_failure, operation_result.merge(on_failure: results))
  end
end
