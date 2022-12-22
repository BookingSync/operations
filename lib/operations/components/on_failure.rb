# frozen_string_literal: true

require "operations/components/callback"

# `on_failure` callbacks are called if a command have failed on a stage
# other than the operation itself or contract. I.e. on policies/preconditions.
# The original command failure is being passed under `operation_failure:`
# key inside of the context.
class Operations::Components::OnFailure < Operations::Components::Callback
  def call(params, context, component:, errors:)
    callback_context = context.merge(operation_failure: errors.to_h)
    results = callable.map do |entry|
      call_entry(entry, params, **callback_context)
    end

    maybe_report_failure(:on_failure, result(
      component: component,
      params: params,
      context: context,
      errors: errors,
      on_failure: results
    ))
  end
end
