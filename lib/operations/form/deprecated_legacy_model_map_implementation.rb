# frozen_string_literal: true

# Traverses the passed {Dry::Schema::KeyMap} and generates
# {Operations::Form::Base} classes on the fly. Handles nested structures.
#
# @see Operations::Form::Base
class Operations::Form::DeprecatedLegacyModelMapImplementation
  extend Dry::Initializer

  TYPE = Operations::Types::Hash.map(
    Operations::Types::Coercible::Array.of(
      Operations::Types::String | Operations::Types::Symbol | Operations::Types.Instance(Regexp)
    ),
    Operations::Types::String
  )

  param :model_map_hash, TYPE, default: proc { {} }

  def call(path)
    model_map_hash.find do |pathspec, _model|
      path.size == pathspec.size && path.zip(pathspec).all? do |slug, pattern|
        pattern.is_a?(Regexp) ? pattern.match?(slug) : slug == pattern
      end
    end&.second
  end
end
