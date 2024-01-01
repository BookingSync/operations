# frozen_string_literal: true

# Configures inspect/pretty_print methods on object.
class Operations::Inspect < Module
  extend Dry::Initializer

  param :attributes, Operations::Types::Coercible::Array.of(Operations::Types::Symbol), reader: false

  def initialize(*attributes, **kwargs)
    super(attributes.flatten(1), **kwargs)

    define_pretty_print(attributes)
  end

  private

  def define_pretty_print(attributes)
    define_method(:pretty_print) do |pp|
      pp.object_group(self) do
        pp.seplist(attributes, -> { pp.text "," }) do |name|
          pp.breakable " "
          pp.group(1) do
            pp.text name.to_s
            pp.text "="
            pp.pp __send__(name)
          end
        end
      end
    end
  end
end
