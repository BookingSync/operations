# frozen_string_literal: true

# The main purpose is to infer attribute properties from the
# related model. We need it to automate form rendering for the
# legacy UI.
class Operation::Form::Attribute
  extend Dry::Initializer
  include Dry::Equalizer(:name, :collection, :form, :model_name)

  param :name, type: Types::Coercible::Symbol
  option :collection, type: Types::Bool, optional: true, default: proc { false }
  option :form, type: Types::Class, optional: true
  option :model_name, type: Types::String, optional: true

  def model_type
    @model_type ||= owning_model.type_for_attribute(string_name) if model_name
  end

  def model_human_name(options = {})
    owning_model.human_attribute_name(string_name, options) if model_name
  end

  def model_validators
    @model_validators ||= model_name ? owning_model.validators_on(string_name) : []
  end

  def model_localized_attr_name(locale)
    owning_model.localized_attr_name_for(string_name, locale) if model_name
  end

  private

  def owning_model
    @owning_model ||= model_name.constantize
  end

  def string_name
    @string_name ||= name.to_s
  end
end
