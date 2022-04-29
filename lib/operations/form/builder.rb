# frozen_string_literal: true

# Traverses the passed {Dry::Schema::KeyMap} and generates
# {Operations::Form} classes on the fly. Handles nested structures.
#
# @see Operations::Form
class Operations::Form::Builder
  extend Dry::Initializer

  NESTED_ATTRIBUTES_SUFFIX = %r{_attributes\z}.freeze

  option :base_class, Operations::Types::Instance(Class)

  def build(key_map:, namespace:, class_name:, model_map:)
    return namespace.const_get(class_name) if namespace && class_name && namespace.const_defined?(class_name)

    traverse(key_map, namespace, class_name, model_map, [])
  end

  private

  def traverse(key_map, namespace, class_name, model_map, path)
    form = Class.new(base_class)
    namespace.const_set(class_name, form) if namespace && class_name

    key_map.each do |key|
      key_path = path + [key.name]

      case key
      when Dry::Schema::Key::Array
        nested_form = traverse(key.member, form, key.name.underscore.classify, model_map, key_path)
        form.attribute(key.name, form: nested_form, collection: true, **model_name(key_path, model_map))
      when Dry::Schema::Key::Hash
        traverse_hash(form, key, model_map, path)
      when Dry::Schema::Key
        form.attribute(key.name, **model_name(key_path, model_map))
      else
        raise "Unknown key_map key: #{key.class}"
      end
    end

    form
  end

  def traverse_hash(form, hash_key, model_map, path)
    nested_attributes_suffix = hash_key.name.match?(NESTED_ATTRIBUTES_SUFFIX)
    nested_attributes_collection = hash_key.members.all?(Dry::Schema::Key::Hash) &&
      hash_key.members.map(&:members).uniq.size == 1

    name, members, collection = specify_form_attributes(
      hash_key,
      nested_attributes_suffix,
      nested_attributes_collection
    )
    form.define_method "#{hash_key.name}=", proc { |attributes| attributes } if nested_attributes_suffix

    key_path = path + [name]
    nested_form = traverse(members, form, name.underscore.camelize, model_map, key_path)
    form.attribute(name, form: nested_form, collection: collection, **model_name(key_path, model_map))
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

  def model_name(path, model_map)
    _, model_name = model_map.find do |pathspec, _model|
      path.size == pathspec.size && path.zip(pathspec).all? do |slug, pattern|
        pattern.is_a?(Regexp) ? pattern.match?(slug) : slug == pattern
      end
    end

    if model_name
      { model_name: model_name }
    else
      {}
    end
  end
end
