# frozen_string_literal: true

RSpec.describe Operations::Convenience do
  let(:dummy_command) do
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
  let(:dummy_operation) do
    Class.new do
      extend Operations::Convenience

      def self.default(arg)
        DummyCommand.new(arg)
      end
    end
  end

  before do
    stub_const("DummyCommand", dummy_command)
    stub_const("DummyOperation", dummy_operation)
  end

  describe "#method_missing" do
    specify do
      expect(dummy_operation.default(42).call(43)).to eq(call: [42, 43])
      expect(dummy_operation.default!(42).call(43)).to eq(call!: [42, 43])
    end
  end

  describe "#respond_to_missing?" do
    specify do
      expect(dummy_operation).to respond_to(:default)
      expect(dummy_operation).to respond_to(:default!)
      expect(dummy_operation).not_to respond_to(:foobar!)
    end
  end

  describe "#contract" do
    subject(:contract) do
      dummy_operation.contract do
        schema do
          required(:name).filled(:string)
        end
      end
    end

    let(:operation_contract_class) { Class.new(Operations::Contract) }

    before { stub_const("OperationContract", operation_contract_class) }

    specify do
      expect(contract).to eq(DummyOperation::Contract)
      expect(contract.config.messages.namespace).to eq("dummy_operation")
      expect(contract.schema.key_map.keys.map(&:name)).to eq([:name])
    end
  end
end
