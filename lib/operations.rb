# frozen_string_literal: true

require "dry-monads"
require "dry/monads/do"
require "dry-validation"
require "active_support/core_ext/array/wrap"
require "active_support/core_ext/class/attribute"
require "active_support/core_ext/module/delegation"
require "active_support/inflector/inflections"
require "active_model/naming"
require "omni_service"
require "operations/version"
require "operations/types"
require "operations/inspect"
require "operations/contract"
require "operations/contract/messages_resolver"
require "operations/convenience"
require "operations/form"
require "operations/form/base"
require "operations/form/attribute"
require "operations/form/builder"
require "operations/form/deprecated_legacy_model_map_implementation"
require "operations/command"
require "operations/result"

# The root gem module
module Operations
end

class Operations::Error < StandardError
end
