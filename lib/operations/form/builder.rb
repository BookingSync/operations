# frozen_string_literal: true

# Traverses the passed {Dry::Schema::KeyMap} and generates
# {Operations::Form::Base} classes on the fly. Handles nested structures.
#
# @see Operations::Form::Base
class Operations::Form::Builder
  extend Dry::Initializer

  NESTED_ATTRIBUTES_SUFFIX = %r{_attributes\z}.freeze

  option :base_class, Operations::Types::Instance(Class)

  def build(key_map:, model_map:, namespace: nil, class_name: nil, param_key: nil, persisted: nil)
    return namespace.const_get(class_name) if namespace && class_name && namespace.const_defined?(class_name)

    traverse(key_map, model_map, namespace, class_name, param_key, [], persisted: persisted)
  end

  private

  def traverse(key_map, model_map, namespace, class_name, param_key, path, persisted: nil)
    form = Class.new(base_class)
    namespace.const_set(class_name, form) if namespace&.name && class_name
    define_model_name(form, param_key) if param_key && !form.name
    form.persisted = persisted

    key_map.each { |key| define_attribute(form, model_map, key, path) }
    form
  end

  def define_model_name(form, param_key)
    form.define_singleton_method :model_name do
      @model_name ||= ActiveModel::Name.new(self, nil, param_key)
    end
  end

  def define_attribute(form, model_map, key, path)
    case key
    when Dry::Schema::Key::Array
      traverse_array(form, model_map, key, path)
    when Dry::Schema::Key::Hash
      traverse_hash(form, model_map, key, path)
    when Dry::Schema::Key
      form.attribute(key.name, model_name: model_map&.call(path + [key.name]))
    else
      raise "Unknown key_map key: #{key.class}"
    end
  end

  def traverse_array(form, model_map, key, path)
    key_path = path + [key.name]
    nested_form = traverse(key.member, model_map, form, key.name.to_s.underscore.classify, key.name.to_s, key_path)
    form.attribute(key.name, form: nested_form, collection: true, model_name: model_map&.call(key_path))
  end

  def traverse_hash(form, model_map, hash_key, path)
    nested_attributes_suffix = hash_key.name.match?(NESTED_ATTRIBUTES_SUFFIX)
    nested_attributes_collection = hash_key.members.all?(Dry::Schema::Key::Hash) &&
      hash_key.members.map(&:members).uniq.size == 1

    name, members, collection = specify_form_attributes(
      hash_key,
      nested_attributes_suffix,
      nested_attributes_collection
    )
    form.define_method :"#{hash_key.name}=", proc { |attributes| attributes } if nested_attributes_suffix

    key_path = path + [name]
    nested_form = traverse(members, model_map, form, name.underscore.camelize, name.to_s.singularize, key_path)
    form.attribute(name, form: nested_form, collection: collection, model_name: model_map&.call(key_path))
  end

  def specify_form_attributes(hash_key, nested_attributes_suffix, nested_attributes_collection)
    if nested_attributes_suffix && !nested_attributes_collection
      [hash_key.name.gsub(NESTED_ATTRIBUTES_SUFFIX, ""), hash_key.members, false]
    elsif nested_attributes_suffix && nested_attributes_collection
      [hash_key.name.gsub(NESTED_ATTRIBUTES_SUFFIX, ""), hash_key.members.first.members, true]
    else
      [hash_key.name, hash_key.members, false]
    end
  end
end
