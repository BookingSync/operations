# frozen_string_literal: true

class Operation::Contract::MessagesResolver < Dry::Validation::Messages::Resolver
  def call(message:, meta: Dry::Schema::EMPTY_HASH, **rest)
    meta = meta.merge(code: message) if message.is_a?(Symbol)

    super(message: message, meta: meta, **rest)
  end
end
