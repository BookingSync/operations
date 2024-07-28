# frozen_string_literal: true

# Configures inspect/pretty_print methods on object.
class Operations::Inspect < Module
  extend Dry::Initializer

  param :attributes, Operations::Types::Coercible::Array.of(Operations::Types::Symbol), reader: false
  param :value_methods, Operations::Types::Hash.map(Operations::Types::Symbol, Operations::Types::Symbol)

  def initialize(*attributes, **kwargs)
    super(attributes.flatten(1), kwargs)

    define_pretty_print(@attributes, @value_methods)
  end

  private

  def define_pretty_print(attributes, value_methods)
    define_method(:pretty_print) do |pp|
      object_group_method = self.class.name ? :object_group : :object_address_group
      pp.public_send(object_group_method, self) do
        pp.seplist(attributes, -> { pp.text "," }) do |name|
          pp.breakable " "
          pp.group(1) do
            pp.text name.to_s
            pp.text "="
            pp.pp __send__(value_methods[name] || name)
          end
        end
      end
    end
  end
end
