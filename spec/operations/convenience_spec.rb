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

  describe "#component" do
    subject(:component) { dummy_operation.component(name, **options) { :foobar } }

    let(:name) { :custom_hydrator }
    let(:options) { {} }

    specify do
      expect(component.name).to eq("DummyOperation::CustomHydrator")
      expect(component).not_to be_a(Dry::Initializer)
      expect(component).not_to include(Dry::Monads[:result])
      expect(component.new.call).to eq(:foobar)
    end

    context "with options given" do
      let(:options) { { dry_initializer: true, dry_monads_result: true } }

      specify do
        expect(component.name).to eq("DummyOperation::CustomHydrator")
        expect(component).to be_a(Dry::Initializer)
        expect(component).to include(Dry::Monads[:result])
        expect(component.new.call).to eq(:foobar)
      end
    end
  end

  %w[policy precondition callback].each do |kind|
    describe "##{kind}" do
      subject(:component) { dummy_operation.public_send(kind) { :foobar } }

      specify do
        expect(component.name).to eq("DummyOperation::#{kind.camelize}")
        expect(component).to be_a(Dry::Initializer)
        expect(component).to include(Dry::Monads[:result])
        expect(component.new.call).to eq(:foobar)
      end

      context "with a superclass" do
        subject(:component) { dummy_operation.public_send(kind, from: parent) { other_method } }

        let(:parent) do
          Class.new do
            def other_method
              :foobar
            end
          end
        end

        specify do
          expect(component.name).to eq("DummyOperation::#{kind.camelize}")
          expect(component).to be < parent
          expect(component).to be_a(Dry::Initializer)
          expect(component).to include(Dry::Monads[:result])
          expect(component.new.call).to eq(:foobar)
        end
      end

      context "with prefix" do
        subject(:component) { dummy_operation.public_send(kind, :prefix) { :foobar } }

        specify do
          expect(component.name).to eq("DummyOperation::Prefix#{kind.camelize}")
          expect(component.new.call).to eq(:foobar)
        end
      end
    end
  end
end
