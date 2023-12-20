# frozen_string_literal: true

# This class implements Rails form object compatibility layer
# It is possible to configure form object attributes automatically
# basing on Dry Schema user {Operations::Form::Builder}
# @example
#
#   class AuthorForm < Operations::Form
#     attribute :name
#   end
#
#   class PostForm < Operations::Form
#     attribute :title
#     attribute :tags, collection: true
#     attribute :author, form: AuthorForm
#   end
#
#   PostForm.new({ tags: ["foobar"], author: { name: "Batman" } })
#   # => #<PostForm attributes={:title=>nil, :tags=>["foobar"], :author=>#<AuthorForm attributes={:name=>"Batman"}>}>
#
# @see Operations::Form::Builder
class Operations::Form
  extend Dry::Initializer
  include Dry::Equalizer(:attributes, :errors)

  param :data,
    type: Operations::Types::Hash.map(Operations::Types::Symbol, Operations::Types::Any),
    default: proc { {} },
    reader: :private
  option :messages,
    type: Operations::Types::Hash.map(
      Operations::Types::Nil | Operations::Types::Coercible::Symbol,
      Operations::Types::Any
    ),
    default: proc { {} },
    reader: :private

  class_attribute :attributes, instance_accessor: false, default: {}

  def self.attribute(name, **options)
    attribute = Operations::Form::Attribute.new(name, **options)

    self.attributes = attributes.merge(
      attribute.name => attribute
    )
  end

  def self.human_attribute_name(name, options = {})
    if attributes[name.to_sym]
      attributes[name.to_sym].model_human_name(options)
    else
      name.to_s.humanize
    end
  end

  def self.validators_on(name)
    attributes[name.to_sym]&.model_validators || []
  end

  def type_for_attribute(name)
    self.class.attributes[name.to_sym].model_type
  end

  def localized_attr_name_for(name, locale)
    self.class.attributes[name.to_sym].model_localized_attr_name(locale)
  end

  def has_attribute?(name) # rubocop:disable Naming/PredicateName
    self.class.attributes.key?(name.to_sym)
  end

  def attributes
    self.class.attributes.keys.to_h do |name|
      [name, read_attribute(name)]
    end
  end

  def assigned_attributes
    (self.class.attributes.keys & data.keys).to_h do |name|
      [name, read_attribute(name)]
    end
  end

  def method_missing(name, *)
    read_attribute(name)
  end

  def respond_to_missing?(name, *)
    self.class.attributes.key?(name)
  end

  def model_name
    ActiveModel::Name.new(self.class)
  end

  # This should return false if we want to use POST.
  # Now it is going to generate PATCH form.
  def persisted?
    true
  end

  # Probably can be always nil, it is used in automated URL derival.
  # We can make it work later but it will require additional concepts.
  def to_key
    nil
  end

  def errors
    @errors ||= ActiveModel::Errors.new(self).tap do |errors|
      self.class.attributes.each do |name, attribute|
        add_messages(errors, name, messages[name])
        add_messages_to_collection(errors, name, messages[name]) if attribute.collection
      end

      add_messages(errors, :base, messages[nil])
    end
  end

  def valid?
    errors.empty?
  end

  def read_attribute(name)
    cached_attribute(name) do |value, attribute|
      if attribute.collection && attribute.form
        wrap_collection([name], value, attribute.form)
      elsif attribute.form
        wrap_object([name], value, attribute.form)
      elsif attribute.collection
        value.nil? ? [] : value
      else
        value
      end
    end
  end

  private

  def add_messages(errors, key, messages)
    return unless messages.is_a?(Array)

    messages.each do |message|
      message = message[:text] if message.is_a?(Hash) && message.key?(:text)
      errors.add(key, message)
    end
  end

  def add_messages_to_collection(errors, key, messages)
    return unless messages.is_a?(Hash)

    read_attribute(key).size.times do |i|
      add_messages(errors, "#{key}[#{i}]", messages[i])
    end
  end

  def cached_attribute(name)
    name = name.to_sym
    return unless self.class.attributes.key?(name)

    nested_name = :"#{name}_attributes"
    value = data.key?(nested_name) ? data[nested_name] : data[name]

    (@attributes_cache ||= {})[name] ||= yield(value, self.class.attributes[name])
  end

  def wrap_collection(path, collection, form)
    collection = [] if collection.nil?

    case collection
    when Hash
      collection.values.map.with_index do |data, i|
        wrap_object(path + [i], data, form)
      end
    when Array
      collection.map.with_index do |data, i|
        wrap_object(path + [i], data, form)
      end
    else
      collection
    end
  end

  def wrap_object(path, data, form)
    data = {} if data.nil?

    if data.is_a?(Hash)
      nested_messages = messages.dig(*path)
      nested_messages = {} unless nested_messages.is_a?(Hash)
      form.new(data, messages: nested_messages)
    else
      data
    end
  end
end
