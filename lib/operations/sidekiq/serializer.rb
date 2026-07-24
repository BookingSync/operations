# frozen_string_literal: true

# Used to serialize operation payload and context
# during the OperationJob scheduling respectively.
#
# Sidekiq only allows simple JSON types as job arguments. This
# serializer encodes richer types (Time, Date, BigDecimal, Symbol,
# Range, Module/Class, Dry::Struct, Money, GlobalID-able objects and
# symbol-keyed hashes) into a tagged representation that
# {Operations::Sidekiq::Deserializer} can restore losslessly.
class Operations::Sidekiq::Serializer
  def call(data) # rubocop:disable Metrics/CyclomaticComplexity
    case data
    when Array then serialized_array(data)
    when ActiveSupport::HashWithIndifferentAccess then serialized_hash_with_indifferent_access(data)
    when Hash then serialized_hash(data)
    when Time, DateTime then serialized_time(data)
    when Date, BigDecimal, Symbol then serialized_as_json(data)
    when Range then serialized_range(data)
    when Dry::Struct then serialize_dry_struct(data)
    when Module, Class then serialized_constant(data)
    else serialized_fallback(data)
    end
  end

  private

  def serialized_fallback(data)
    if defined?(Money) && data.is_a?(Money)
      serialized_money(data)
    elsif data.respond_to?(:to_global_id)
      serialized_global_id(data)
    else
      data
    end
  end

  def serialized_array(array)
    array.map { |value| call(value) }
  end

  def serialized_hash_with_indifferent_access(hash)
    serialized_object(
      "ActiveSupport::HashWithIndifferentAccess",
      hash.to_h { |key, value| [key.to_s, call(value)] }
    )
  end

  def serialized_hash(hash)
    symbol_keys = hash.keys.grep(Symbol).map(&:to_s)
    hash.to_h { |key, value| [key.to_s, call(value)] }
      .merge(Operations::Sidekiq::SIDEKIQ_SYMBOL_KEYS => symbol_keys)
  end

  def serialized_time(data)
    serialized_object(data.class.name, data.iso8601(9))
  end

  def serialized_as_json(data)
    serialized_object(data.class.name, data.as_json)
  end

  def serialized_range(range)
    serialized_object(range.class.name, [range.begin, range.end, range.exclude_end?])
  end

  def serialized_money(money)
    serialized_object(money.class.name, [money.fractional, money.currency.to_s])
  end

  def serialize_dry_struct(struct)
    serialized_object(Dry::Struct.name, serialized_hash(struct.class.name => struct.to_h))
  end

  def serialized_constant(constant)
    raise "Unable to serialize an anonymous constant #{constant}" unless constant.name

    serialized_object(constant.class.name, constant.name)
  end

  def serialized_global_id(object)
    serialized_object("GlobalID", object.to_global_id.to_s)
  end

  def serialized_object(key, value)
    {
      Operations::Sidekiq::SIDEKIQ_TYPE_KEY => key,
      Operations::Sidekiq::SIDEKIQ_VALUE_KEY => value
    }
  end
end
