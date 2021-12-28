# frozen_string_literal: true

class Operation::Components::Operation < Operation::Components::Base
  def call(params, context)
    context_args = context.values_at(*call_args(@callable, types: %i[req opt]))
    operation_result = callable.call(*context_args, **params)
    result = result(params: params, context: context)

    if operation_result.failure?
      result.merge(errors: errors(normalize_failure(operation_result.failure)))
    else
      result.merge(context: context.merge(operation_result.value!))
    end
  end
end
