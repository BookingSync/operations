# frozen_string_literal: true

# We check all the precondition failures to return all the codes to
# the user at once. This provides a better UX, user is able to fix
# everything at once instead of getting messages one by one. This is
# similar to the idea of validations.
#
# Precondition can return a Symbol - it will be used as an error code.
# If String is returned - it will be used as a message itself. Please
# avoid returning string, use i18n instead. Hash with `:error` key
# will be also treated as a failure ans used accordingly. Also, `Failure`
# monad gets unwrapped and the value follows the rules above. Also, it is
# possible to return an array of failures.
#
# Successful preconditions returns either nil or an empty array or a
# `Success` monad.
class Operation::Components::Preconditions < Operation::Components::Prechecks
  def call(params, context)
    failures = callable.flat_map do |entry|
      results = Array.wrap(entry.call(**context))
      results.filter_map { |result| result_failure(result) }
    end

    result(
      params: params,
      context: context,
      errors: errors(normalize_failure(failures))
    )
  end

  private

  def result_failure(result)
    case result
    when nil, Success
      nil
    when Failure
      result.failure
    else
      result
    end
  end
end
