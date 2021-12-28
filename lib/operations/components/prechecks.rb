# frozen_string_literal: true

require "operations/components/base"

# Contains common logic for policies and preconditions.
class Operations::Components::Prechecks < Operations::Components::Base
  param :callable, type: Operations::Types::Array.of(Operations::Types.Interface(:call))

  def required_context
    @required_context ||= required_kwargs | context_keys
  end

  private

  def context_keys
    keys = callable.flat_map do |entry|
      if entry.respond_to?(:context_key)
        [entry.context_key]
      elsif entry.respond_to?(:context_keys)
        entry.context_keys
      else
        []
      end
    end

    keys.map(&:to_sym)
  end

  def required_kwargs
    callable.flat_map do |entry|
      call_args(entry, types: %i[keyreq])
    end.uniq
  end
end
