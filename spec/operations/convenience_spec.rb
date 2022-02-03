# frozen_string_literal: true

RSpec.describe Operations::Convenience do
  let(:dummy_operation) do
    Class.new do
      def initialize(arg)
        @arg = arg
      end

      def call(arg2)
        { call: [@arg, arg2] }
      end

      def call!(arg2)
        { call!: [@arg, arg2] }
      end
    end
  end
  let(:dummy_class) do
    Class.new do
      extend Operations::Convenience

      def self.default(arg)
        DummyOperation.new(arg)
      end
    end
  end

  before { stub_const("DummyOperation", dummy_operation) }

  describe "#method_missing" do
    specify do
      expect(dummy_class.default(42).call(43)).to eq(call: [42, 43])
      expect(dummy_class.default!(42).call(43)).to eq(call!: [42, 43])
    end
  end

  describe "#respond_to_missing?" do
    specify do
      expect(dummy_class).to respond_to(:default)
      expect(dummy_class).to respond_to(:default!)
      expect(dummy_class).not_to respond_to(:foobar!)
    end
  end
end
