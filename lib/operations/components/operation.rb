# frozen_string_literal: true

require "operations/components/base"

# Wraps operation component call to adapt to the further processing.
class Operations::Components::Operation < Operations::Components::Base
  PARAMS_FIRST_SIGNATURES = [[:params], [:_params], [:_]].freeze

  def call(params, context)
    arg_names = call_args(@callable, types: %i[req opt])

    operation_result = if PARAMS_FIRST_SIGNATURES.include?(arg_names)
      callable.call(params, **context)
    else
      context_args = context.values_at(*arg_names)
      callable.call(*context_args, **params)
    end

    result = result(params: params, context: context)

    if operation_result.failure?
      result.merge(errors: errors(normalize_failure(operation_result.failure)))
    else
      result.merge(context: context.merge(operation_result.value!))
    end
  end
end
