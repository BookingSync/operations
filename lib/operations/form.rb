# frozen_string_literal: true

# Configures and defines a form object factory.
class Operations::Form
  include Dry::Equalizer(:key_map, :model_map, :hydrator, :base_class)
  include Operations::Inspect.new(:key_map, :model_map, :hydrator, :base_class, :form_class)

  # We need to make deprecated inheritance from Operations::Form act exactly the
  # same way as from Operations::Form::Base. In order to do this, we are encapsulating all the
  # inheritable functionality in 2 modules and removing methods defined in Operations::Form
  # from the result class.
  def self.inherited(subclass)
    super

    return unless self == Operations::Form

    ActiveSupport::Deprecation.new.warn("Inheritance from Operations::Form is deprecated and will be " \
      "removed in 1.0.0. Please inherit from Operations::Form::Base instead")

    (Operations::Form.instance_methods - Object.instance_methods).each do |method|
      subclass.undef_method(method)
    end

    subclass.extend Operations::Form::Base::ClassMethods
    subclass.prepend Operations::Form::Base::InstanceMethods
  end

  include Dry::Initializer.define(lambda do
    param :key_map_source, Operations::Types.Interface(:contract) |
      Operations::Types.Interface(:schema) | Operations::Types.Interface(:key_map)
    option :model_map, Operations::Types.Interface(:call), optional: true, default: proc {}
    option :hydrator, Operations::Types.Interface(:call), optional: true, default: proc {}
    option :base_class, Operations::Types::Class, default: proc { ::Operations::Form::Base }
  end)

  def call(operation_result)
    form_class.new(
      hydrator.call(form_class, operation_result.params, **operation_result.context).merge(operation_result.params),
      messages: operation_result.errors.to_h
    )
  end

  def to_hash
    {
      key_map: key_map,
      model_map: model_map.class.name,
      hydrator: hydrator.class.name,
      base_class: base_class.name
    }
  end

  private

  def form_class
    @form_class ||= Operations::Form::Builder
      .new(base_class: base_class)
      .build(key_map: key_map, model_map: model_map)
  end

  def key_map
    @key_map ||= if key_map_source.respond_to?(:contract)
      key_map_source.contract.schema.key_map
    elsif key_map_source.respond_to?(:schema)
      key_map_source.schema.key_map
    else
      key_map_source.key_map
    end
  end
end
