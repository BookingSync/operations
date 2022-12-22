# frozen_string_literal: true

require "operations/components/callback"

# `on_success` callbacks are called when command was successful and implemented
# to be executed outside the outermost DB transcation (this is configurable
# but by default AfterCommitEverywhere gem is used).
# It there is a wrapping transaction (in cases when command is called inside
# of another command), the inner command result will have empty `on_success`
# component (since the callbacks will happen when the wparring command is finished).
class Operations::Components::OnSuccess < Operations::Components::Callback
  option :after_commit, type: Operations::Types.Interface(:call)

  def call(params, context, component:)
    callback_result = after_commit.call { call_entries(params, context, component: component) }

    if callback_result.is_a?(Operations::Result)
      callback_result
    else
      result(
        component: component,
        params: params,
        context: context
      )
    end
  end

  private

  def call_entries(params, context, component:)
    results = callable.map do |entry|
      call_entry(entry, params, **context)
    end

    maybe_report_failure(:on_success, result(
      component: component,
      params: params,
      context: context,
      on_success: results
    ))
  end
end
