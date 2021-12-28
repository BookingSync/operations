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
require "active_model/errors"
require "operations/version"
require "operations/types"
require "operations/contract"
require "operations/contract/messages_resolver"
require "operations/composite"
require "operations/result"
require "operations/form"
require "operations/form/attribute"
require "operations/form/builder"
require "operation_contract"

# Dry::Schema.load_extensions(:monads)
# Dry::Validation.load_extensions(:monads)

# Your code goes here...
class Operations::Error < StandardError
end
