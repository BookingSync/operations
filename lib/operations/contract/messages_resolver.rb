# frozen_string_literal: true

# Patching the default messages resolver to append `:code` meta
# to every message produced.
class Operations::Contract::MessagesResolver < Dry::Validation::Messages::Resolver
  def call(message:, meta: Dry::Schema::EMPTY_HASH, **rest)
    meta = meta.merge(code: message) if message.is_a?(Symbol)

    super
  end
end
