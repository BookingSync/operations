# frozen_string_literal: true

require "operations/components/base_callback"

# This component handles `on_failure:` callbacks passed to the
# composite. Every `on_failure:` entry is called in a separate
# transaction and any exception is rescued here so the
# result of the whole operation is not affected.
# If there is a failure in any entry, it is reported with
# `error_reporter` proc.
class Operations::Components::OnFailure < Operations::Components::BaseCallback
end
