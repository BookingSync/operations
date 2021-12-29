# frozen_string_literal: true

# Just a base contract with i18n set up and a bunch of useful macro.
class Operations::Contract < Dry::Validation::Contract
  option :message_resolver, default: -> { Operations::Contract::MessagesResolver.new(messages) }

  # config.messages.backend = :i18n
  config.messages.top_namespace = "operations"

  def self.inherited(subclass)
    super

    return unless subclass.name

    namespace = subclass.name.underscore.split("/")[0..-2].join("/")
    subclass.config.messages.namespace = namespace
  end

  def self.prepend_rule(...)
    rule(...)
    rules.unshift(rules.pop)
  end

  def self.ensure_presence(context_key, field: "#{context_key}_id", optional: false)
    rule do |context:|
      next if context[context_key] || schema_error?(field)

      if key?(field)
        key(field).failure(:not_found, entity_name: context_key.to_s.humanize)
      elsif !optional
        key(field).failure(:key?)
      end
    end
  end

  def call(input, **initial_context)
    super(input, initial_context)
  end
end
