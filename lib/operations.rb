# frozen_string_literal: true

require "pp"
require "dry-monads"
require "dry/monads/do"
require "dry-validation"
require "active_support/core_ext/array/wrap"
require "active_support/core_ext/class/attribute"
require "active_support/core_ext/module/delegation"
require "active_support/inflector/inflections"
require "active_model/naming"
require "after_commit_everywhere"
require "operations/version"
require "operations/types"
require "operations/configuration"
require "operations/contract"
require "operations/contract/messages_resolver"
require "operations/convenience"
require "operations/command"
require "operations/result"
require "operations/form"
require "operations/form/attribute"
require "operations/form/builder"

# The root gem module
module Operations
  class Error < StandardError
  end

  DEFAULT_ERROR_REPORTER = ->(message, payload) { Sentry.capture_message(message, extra: payload) }
  DEFAULT_TRANSACTION = ->(&block) { ActiveRecord::Base.transaction(requires_new: true, &block) }
  DEFAULT_AFTER_COMMIT = ->(&block) { AfterCommitEverywhere.after_commit(&block) }

  class << self
    attr_reader :default_config

    def configure(**options)
      @default_config = Configuration.new(**options)
    end
  end

  configure(
    error_reporter: DEFAULT_ERROR_REPORTER,
    transaction: DEFAULT_TRANSACTION,
    after_commit: DEFAULT_AFTER_COMMIT
  )
end
