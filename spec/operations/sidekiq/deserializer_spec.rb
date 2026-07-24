# frozen_string_literal: true

RSpec.describe Operations::Sidekiq::Deserializer do
  subject(:deserializer) { described_class.new }

  before do
    struct_class = Class.new(Dry::Struct) do
      attribute :percentage, Operations::Types::Any
      attribute :fixed_amount, Operations::Types::Any
    end
    stub_const("PricingPlan", struct_class)
  end

  describe "#call" do
    it "reverses the serializer for scalars, collections and rich types" do
      data = {
        number: 42,
        "string" => "foobar",
        "array" => [4.2, BigDecimal("4.2"), Date.new(2026, 7, 24)],
        money: Money.new(42_00, "EUR"),
        "pricing_plan" => PricingPlan.new(percentage: BigDecimal("1.2"), fixed_amount: Money.new(30, "EUR")),
        hash_with_indifferent_access: {
          foo: :bar,
          time_with_zone: Time.zone.parse("2026-07-24T12:34:56.123456789Z")
        }.with_indifferent_access,
        "nested_hash" => {
          "range" => 1..42,
          "module" => Operations::Sidekiq,
          "class" => Operations::Command
        }
      }
      serialized = Operations::Sidekiq::Serializer.new.call(data)

      expect(deserializer.call(serialized)).to eq(data)
    end

    it "restores symbol keys tracked by the serializer" do
      serialized = { "foo" => 1, "bar" => 2, "$sidekiq_symbol_keys" => ["foo"] }

      expect(deserializer.call(serialized)).to eq(foo: 1, "bar" => 2)
    end

    it "restores plain Time-tagged values through the time zone" do
      serialized = { "$sidekiq_type" => "Time", "$sidekiq_value" => "2026-07-24T12:34:56.123456789Z" }

      expect(deserializer.call(serialized)).to eq(Time.zone.parse("2026-07-24T12:34:56.123456789Z"))
    end

    it "restores ActiveSupport::TimeWithZone-tagged values" do
      serialized = {
        "$sidekiq_type" => "ActiveSupport::TimeWithZone",
        "$sidekiq_value" => "2026-07-24T12:34:56.123456789Z"
      }

      expect(deserializer.call(serialized)).to eq(Time.zone.parse("2026-07-24T12:34:56.123456789Z"))
    end

    it "locates global ids" do
      located = Object.new
      allow(GlobalID::Locator).to receive(:locate).with("gid://test/Amenity/1").and_return(located)
      serialized = { "$sidekiq_type" => "GlobalID", "$sidekiq_value" => "gid://test/Amenity/1" }

      expect(deserializer.call(serialized)).to be(located)
    end

    it "raises on unknown serialized types" do
      expect { deserializer.call("$sidekiq_type" => "Nope", "$sidekiq_value" => "x") }
        .to raise_error(%r{Unknown serialized data type Nope})
    end
  end
end
