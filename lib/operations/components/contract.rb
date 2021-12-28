# frozen_string_literal: true

class Operation::Components::Contract < Operation::Components::Base
  def call(params, context)
    contract_result = callable.call(params, **context)

    result(
      params: contract_result.to_h,
      context: contract_result.context.each.to_h,
      # This is the only smart way I figured out to pass options
      # to the schema error messages. The machinery is buried too
      # deeply in dry-schema so reproducing it or trying to use
      # some private API would be too fragile.
      errors: ->(**options) { contract_result.errors(**options) }
    )
  end
end
