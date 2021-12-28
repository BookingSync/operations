# frozen_string_literal: true

# Just a base contract with i18n set up and a bunch of useful macro.
class Operation::Contract < Dry::Validation::Contract
  option :message_resolver, default: -> { Operation::Contract::MessagesResolver.new(messages) }

  config.messages.backend = :i18n
  config.messages.top_namespace = :operations

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

  def self.find(context_key, **options)
    macro = Operation::Contract::Find.new(context_key, **options)

    rule do |context:|
      repo = if respond_to?(macro.repo_name)
        public_send(macro.repo_name)
      else
        macro.generic_repo
      end

      context[macro.context_key] ||= (macro.get(repo, values[macro.field]) if key?(macro.field))

      if context[macro.context_key]
        macro.wrap_entity(context[macro.context_key], repo: repo).each do |key, value|
          context[key] = value
        end
      elsif key?(macro.field)
        key(macro.field).failure(:not_found, entity_name: macro.entity_name) unless schema_error?(macro.field)
      elsif macro.required?
        key(macro.field).failure(:key?)
      end
    end
  end

  def call(input, **initial_context)
    super(input, initial_context)
  end
end
