# frozen_string_literal: true

# This class implements Rails form object compatibility layer
# It is possible to configure form object attributes automatically
# basing on Dry Schema user {Operations::Form::Builder}
# @example
#
#   class AuthorForm < Operations::Form::Base
#     attribute :name
#   end
#
#   class PostForm < Operations::Form::Base
#     attribute :title
#     attribute :tags, collection: true
#     attribute :author, form: AuthorForm
#   end
#
#   PostForm.new({ tags: ["foobar"], author: { name: "Batman" } })
#   # => #<PostForm attributes={:title=>nil, :tags=>["foobar"], :author=>#<AuthorForm attributes={:name=>"Batman"}>}>
#
# @see Operations::Form::Builder
class Operations::Form::Base
  BUILD_ASSOCIATION_PREFIX = "build_"
  NESTED_ATTRIBUTES_SUFFIX = "_attributes="

  # :nodoc:
  module ClassMethods
    def self.extended(base)
      base.singleton_class.include Operations::Inspect.new(:attributes)

      base.extend Dry::Initializer
      base.include Dry::Equalizer(:attributes, :errors)
      base.include Operations::Inspect.new(:attributes, :errors)

      base.param :data,
        type: Operations::Types::Hash.map(Operations::Types::Symbol, Operations::Types::Any),
        default: proc { {} },
        reader: :private
      base.option :messages,
        type: Operations::Types::Hash.map(
          Operations::Types::Nil | Operations::Types::Coercible::Symbol,
          Operations::Types::Any
        ),
        default: proc { {} },
        reader: :private
      base.option :operation_result, default: proc {}

      base.class_attribute :attributes, instance_accessor: false, default: {}
      base.class_attribute :primary_key, instance_accessor: false, default: :id
      base.class_attribute :persisted, instance_accessor: false, default: nil

      base.define_method :initialize do |*args, **kwargs|
        if args.empty?
          # Initializing Operations::Form::Base instance
          super(kwargs, **{})
        else
          # Initializing Operations::Form instance as form object (deprecated)
          super(*args, **kwargs)
        end
      end
    end

    def attribute(name, **options)
      attribute = Operations::Form::Attribute.new(name, **options)

      self.attributes = attributes.merge(
        attribute.name => attribute
      )
    end

    def human_attribute_name(name, options = {})
      if attributes[name.to_sym]
        attributes[name.to_sym].model_human_name(options)
      else
        name.to_s.humanize
      end
    end

    def validators_on(name)
      attributes[name.to_sym]&.model_validators || []
    end

    def model_name
      @model_name ||= ActiveModel::Name.new(self)
    end

    def reflect_on_association(...); end
  end

  # :nodoc:
  module InstanceMethods
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

    # For now we gracefully return nil for unknown methods
    def method_missing(name, *args, **kwargs)
      build_attribute_name = build_attribute_name(name)
      build_attribute = self.class.attributes[build_attribute_name]
      plural_build_attribute = self.class.attributes[build_attribute_name.to_s.pluralize.to_sym]

      if has_attribute?(name)
        read_attribute(name)
      elsif build_attribute&.form
        build_attribute.form.new(*args, **kwargs)
      elsif plural_build_attribute&.form
        plural_build_attribute.form.new(*args, **kwargs)
      end
    end

    def respond_to_missing?(name, *)
      has_attribute?(name) ||
        build_nested_form?(build_attribute_name(name)) ||
        self.class.attributes[nested_attribute_name(name)]&.form
    end

    def model_name
      self.class.model_name
    end

    def persisted?
      self.class.persisted.nil? ? read_attribute(self.class.primary_key).present? : self.class.persisted
    end

    def new_record?
      !persisted?
    end

    def _destroy
      Operations::Types::Params::Bool.call(read_attribute(:_destroy)) { false }
    end
    alias_method :marked_for_destruction?, :_destroy

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
    alias_method :read_attribute_for_validation, :read_attribute

    def to_hash
      {
        attributes: attributes,
        errors: errors
      }
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

    def build_attribute_name(name)
      name.to_s.delete_prefix(BUILD_ASSOCIATION_PREFIX).to_sym if name.to_s.start_with?(BUILD_ASSOCIATION_PREFIX)
    end

    def nested_attribute_name(name)
      name.to_s.delete_suffix(NESTED_ATTRIBUTES_SUFFIX).to_sym if name.to_s.end_with?(NESTED_ATTRIBUTES_SUFFIX)
    end

    def build_nested_form?(name)
      !!(self.class.attributes[name]&.form ||
        self.class.attributes[name.to_s.pluralize.to_sym]&.form)
    end
  end

  extend ClassMethods
  include InstanceMethods
end
