# frozen_string_literal: true

RSpec.describe Operations::Sidekiq::Serializer do
  subject(:serializer) { described_class.new }

  describe "#call" do
    it "passes JSON-native scalars through untouched" do
      expect(serializer.call(42)).to eq(42)
      expect(serializer.call("foo")).to eq("foo")
      expect(serializer.call(4.2)).to eq(4.2)
      expect(serializer.call(nil)).to be_nil
    end

    it "serializes symbol-keyed hashes tracking the symbol keys" do
      expect(serializer.call({ foo: 1, "bar" => 2 })).to eq(
        "foo" => 1, "bar" => 2, "$sidekiq_symbol_keys" => ["foo"]
      )
    end

    it "serializes HashWithIndifferentAccess" do
      expect(serializer.call({ foo: 1 }.with_indifferent_access)).to eq(
        "$sidekiq_type" => "ActiveSupport::HashWithIndifferentAccess",
        "$sidekiq_value" => { "foo" => 1 }
      )
    end

    it "serializes arrays element-wise" do
      expect(serializer.call([1, :two, BigDecimal("3.3")])).to eq([
        1,
        { "$sidekiq_type" => "Symbol", "$sidekiq_value" => "two" },
        { "$sidekiq_type" => "BigDecimal", "$sidekiq_value" => "3.3" }
      ])
    end

    it "serializes symbols, big decimals and dates via as_json" do
      expect(serializer.call(:foo)).to eq("$sidekiq_type" => "Symbol", "$sidekiq_value" => "foo")
      expect(serializer.call(BigDecimal("4.2"))).to eq("$sidekiq_type" => "BigDecimal", "$sidekiq_value" => "4.2")
      expect(serializer.call(Date.new(2026, 7, 24))).to eq("$sidekiq_type" => "Date", "$sidekiq_value" => "2026-07-24")
    end

    it "serializes times with nanosecond precision" do
      time = Time.zone.parse("2026-07-24T12:34:56.123456789Z")

      expect(serializer.call(time)).to eq(
        "$sidekiq_type" => "ActiveSupport::TimeWithZone",
        "$sidekiq_value" => "2026-07-24T12:34:56.123456789Z"
      )
    end

    it "serializes ranges" do
      expect(serializer.call(1..42)).to eq("$sidekiq_type" => "Range", "$sidekiq_value" => [1, 42, false])
    end

    it "serializes money" do
      expect(serializer.call(Money.new(42_00, "EUR"))).to eq(
        "$sidekiq_type" => "Money", "$sidekiq_value" => [42_00, "EUR"]
      )
    end

    it "serializes modules and classes by name" do
      expect(serializer.call(Operations::Sidekiq)).to eq(
        "$sidekiq_type" => "Module", "$sidekiq_value" => "Operations::Sidekiq"
      )
      expect(serializer.call(Operations::Command)).to eq(
        "$sidekiq_type" => "Class", "$sidekiq_value" => "Operations::Command"
      )
    end

    it "raises for anonymous constants" do
      expect { serializer.call(Class.new) }.to raise_error(%r{anonymous constant})
    end

    it "serializes dry-structs preserving the class name and nested types" do
      stub_const("PricingPlan", Class.new(Dry::Struct) do
        attribute :percentage, Operations::Types::Any
        attribute :fixed_amount, Operations::Types::Any
      end)
      struct = PricingPlan.new(percentage: BigDecimal("1.2"), fixed_amount: Money.new(30, "EUR"))

      expect(serializer.call(struct)).to eq(
        "$sidekiq_type" => "Dry::Struct",
        "$sidekiq_value" => {
          "PricingPlan" => {
            "percentage" => { "$sidekiq_type" => "BigDecimal", "$sidekiq_value" => "1.2" },
            "fixed_amount" => { "$sidekiq_type" => "Money", "$sidekiq_value" => [30, "EUR"] },
            "$sidekiq_symbol_keys" => %w[percentage fixed_amount]
          },
          "$sidekiq_symbol_keys" => []
        }
      )
    end

    it "serializes global-id-able objects" do
      globalidable = Class.new do
        def to_global_id
          "gid://test/Amenity/1"
        end
      end.new

      expect(serializer.call(globalidable)).to eq(
        "$sidekiq_type" => "GlobalID", "$sidekiq_value" => "gid://test/Amenity/1"
      )
    end
  end
end
