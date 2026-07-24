# frozen_string_literal: true

# Used to deserialize operation payload and context
# during the OperationJob processing respectively.
#
# It is the counterpart of {Operations::Sidekiq::Serializer} and
# restores the tagged representation back into the original Ruby
# objects.
class Operations::Sidekiq::Deserializer
  DESERIALIZERS = {
    "Symbol" => ->(data) { data.to_sym },
    "BigDecimal" => ->(data) { BigDecimal(data) },
    "Date" => ->(data) { data.to_date },
    "Time" => ->(data) { Time.zone.parse(data) },
    "Range" => ->(data) { Range.new(*data) },
    "Module" => ->(data) { data.constantize },
    "Class" => ->(data) { data.constantize },
    "GlobalID" => ->(data) { GlobalID::Locator.locate(data) },
    "Money" => ->(data) { Money.new(*data) },
    "ActiveSupport::TimeWithZone" => ->(data) { Time.zone.parse(data) }
  }.freeze

  def call(data)
    case data
    when Array
      data.map { |value| call(value) }
    when Hash
      if data.key?(Operations::Sidekiq::SIDEKIQ_TYPE_KEY)
        deserialize_object(
          data[Operations::Sidekiq::SIDEKIQ_TYPE_KEY],
          data[Operations::Sidekiq::SIDEKIQ_VALUE_KEY]
        )
      else
        deserialize_hash(data)
      end
    else
      data
    end
  end

  private

  def deserialize_hash(hash)
    symbol_keys = Set.new(hash.delete(Operations::Sidekiq::SIDEKIQ_SYMBOL_KEYS) || [])

    hash.to_h do |key, value|
      [
        symbol_keys.include?(key) ? key.to_sym : key,
        call(value)
      ]
    end
  end

  def deserialize_object(type, data)
    if type == "ActiveSupport::HashWithIndifferentAccess"
      data.transform_values { |value| call(value) }.with_indifferent_access
    elsif type == "Dry::Struct"
      class_name, attributes = data.first
      class_name.constantize.new(**deserialize_hash(attributes).deep_symbolize_keys)
    elsif DESERIALIZERS.key?(type)
      DESERIALIZERS[type].call(data)
    else
      raise "Unknown serialized data type #{type} with value #{data}"
    end
  end
end
