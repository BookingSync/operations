# frozen_string_literal: true

# Configures and defines a form object factory.
# Forms can be defined on top of commants and used in the user-facing controllers.
# Form objects are Rails-specific and support everything that is needed for Rails'
# form rendering helpers. They are designed to replace direct usage of ActiveRecord
# models in controllers and views and act as an integration bridge from Rails
# application to the Operations framework.
#
# @example
#
#   command = Operations::Command.new(...)
#   form = Operations::Form.new(command)
#
#   @form_object = form.build(params)
#
#   form_for @form_object, url: ...
#
#   @form_object = form.persist(params)
#   respond_with @form_object
#
class Operations::Form
  include Dry::Core::Constants
  include Dry::Equalizer(:command, :model_map, :persisted,
    :params_transformations, :hydrators, :hydration_merge_params, :form_class)
  include Operations::Inspect.new(:model_name, :model_map, :persisted,
    :params_transformations, :hydrators, :hydration_merge_params, :form_class)

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
    param :command, type: Operations::Types.Interface(:operation, :contract, :call)
    option :model_name, type: Operations::Types::String.optional, default: proc {}, reader: false
    option :model_map, type: Operations::Types.Interface(:call).optional, default: proc {}
    option :persisted, type: Operations::Types::Bool, default: proc { true }
    option :params_transformations, type: Operations::Types::Coercible::Array.of(Operations::Types.Interface(:call)),
      default: proc { [] }
    option :hydrators, type: Operations::Types::Array.of(Operations::Types.Interface(:call)), default: proc { [] }
    option :hydration_merge_params, type: Operations::Types::Bool, default: proc { true }
    option :base_class, type: Operations::Types::Class, default: proc { ::Operations::Form::Base }
  end)

  def initialize(command, hydrator: nil, hydrators: [], **options)
    hydrators.push(hydrator) if hydrator.present?

    super(command, hydrators: hydrators, **options)
  end

  def build(params = EMPTY_HASH, **context)
    instantiate_form(command.callable(transform_params(params, **context), **context))
  end

  def persist(params = EMPTY_HASH, **context)
    instantiate_form(command.call(transform_params(params, **context), **context))
  end

  def form_class
    @form_class ||= Operations::Form::Builder.new(base_class: base_class)
      .build(key_map: key_map, model_map: model_map, model_name: model_name, persisted: persisted)
  end

  private

  def transform_params(params, **context)
    params = params.to_unsafe_hash if params.respond_to?(:to_unsafe_hash)
    params = params.deep_symbolize_keys
    params = params.merge(params[form_class.model_name.param_key.to_sym] || {})
    params_transformations.inject(params) do |value, transformation|
      transformation.call(form_class, value, **context)
    end
  end

  def instantiate_form(operation_result)
    form_class.new(
      hydrate_params(form_class, operation_result.params, **operation_result.context),
      messages: operation_result.errors.to_h,
      operation_result: operation_result
    )
  end

  def hydrate_params(form_class, params, **context)
    hydrated_params = hydrators.inject({}) do |value, hydrator|
      value.merge(hydrator.call(form_class, params, context).deep_symbolize_keys)
    end
    hydrated_params.deep_merge!(params) if hydration_merge_params
    hydrated_params
  end

  def key_map
    @key_map ||= command.contract.schema.key_map
  end

  def model_name
    @model_name ||= ("#{command.operation.class.name.underscore}_form" if command.operation.class.name)
  end
end
