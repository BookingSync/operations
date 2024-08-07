# frozen_string_literal: true

# The main purpose is to infer attribute properties from the
# related model. We need it to automate form rendering for the
# legacy UI.
class Operations::Form::Attribute
  extend Dry::Initializer
  include Dry::Equalizer(:name, :collection, :model_class, :model_attribute, :form)
  include Operations::Inspect.new(:name, :collection, :model_class, :model_attribute, :form)

  param :name, type: Operations::Types::Coercible::Symbol
  option :collection, type: Operations::Types::Bool, default: proc { false }
  option :model_name, type: (Operations::Types::String | Operations::Types::Class).optional, default: proc {}
  option :form, type: Operations::Types::Class.optional, default: proc {}

  def model_class
    return @model_class if defined?(@model_class)

    @model_class = model_name.is_a?(String) ? model_name.split("#").first.constantize : model_name
  end

  def model_attribute
    return @model_attribute if defined?(@model_attribute)

    @model_attribute = model_class && (model_name.to_s.split("#").second.presence || name.to_s)
  end

  def model_type
    model_class.type_for_attribute(model_attribute) if model_name
  end

  def model_human_name(options = {})
    model_class.human_attribute_name(model_attribute, options) if model_name
  end

  def model_validators
    model_name ? model_class.validators_on(model_attribute) : []
  end
end
