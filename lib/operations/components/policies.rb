# frozen_string_literal: true

# We are looking for the first policy failure to return because
# it does not make sense to check for all policy failures. One is
# more than enough to know that we are not allowed to call the operation.
#
# If policy returns `false` then generic `:unauthorized` error
# code will be used. In case of `Failure` monad - the error code depends
# on the failure internal value. It can be a String, Symbol or even
# a Hash containing `:error` key.
#
# Successful policies return either `true` or `Success` monad.
class Operation::Components::Policies < Operation::Components::Prechecks
  def call(params, context)
    first_failure = callable.lazy.filter_map do |entry|
      result_failure(entry.call(**context), entry)
    end.first

    result(
      params: params,
      context: context,
      errors: errors(normalize_failure([first_failure].compact))
    )
  end

  private

  def result_failure(result, entry)
    case result
    when true, Success
      nil
    when Failure
      result.failure
    when false
      :unauthorized
    else
      raise "Unexpected policy result: #{result} for #{entry}"
    end
  end
end
