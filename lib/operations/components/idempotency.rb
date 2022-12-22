# frozen_string_literal: true

require "operations/components/prechecks"

# Contains logic to handle idempotency checks.
#
# Idempotency checks are used to skip operation execution in
# certain conditions.
#
# An idempotency check returns a Result monad. If it returns
# a Failure, the operation body is skipped but the operation
# is considered successful. The value or failure will be merged
# to the result context in order to enrich it (the failure should
# contain something that operation body would return normally
# to mimic a proper operation call result).
#
# Component logs the failed check with `error_reporter`.
class Operations::Components::Idempotency < Operations::Components::Prechecks
  def call(params, context)
    failure, failed_check = process_callables(params, context)

    if failure
      new_result = result(
        params: params,
        context: context.merge(failure.failure)
      )

      report_failure(new_result, failed_check)

      Failure(new_result)
    else
      Success(result(
        params: params,
        context: context
      ))
    end
  end

  private

  def process_callables(params, context)
    failed_check = nil
    failure = nil

    callable.each do |entry|
      result = entry.call(params, **context)

      case result
      when Failure
        failed_check = entry
        failure = result
        break
      when Success
        next
      else
        raise "Unrecognized result of an idempotency check. Expected Result monad, got #{result.class}"
      end
    end

    [failure, failed_check]
  end

  def report_failure(result, failed_check)
    info_reporter&.call(
      "Idempotency check failed",
      result: result.as_json,
      failed_check: failed_check.inspect
    )
  end
end
