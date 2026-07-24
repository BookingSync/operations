# frozen_string_literal: true

RSpec.describe Operations::Sidekiq do
  describe ".operation_container" do
    subject(:operation_container) { described_class.operation_container(operation) }

    let(:dummy_operation) do
      Class.new do
        def self.default
          @default ||= Operations::Command.new(
            new,
            contract: Class.new(Operations::Contract) { schema { required(:name).filled(:string) } }.new,
            policy: nil
          )
        end

        def call(_params, **_context)
          Dry::Monads::Success(foo: 42)
        end
      end
    end
    let(:operation) { DummyOperation.default }

    before { stub_const("DummyOperation", dummy_operation) }

    it { is_expected.to eq([DummyOperation, :default]) }

    context "when the operation is not wrapped in a command" do
      let(:dummy_operation) do
        Class.new do
          def self.default
            @default ||= new
          end
        end
      end

      it { is_expected.to eq([DummyOperation, :default]) }
    end

    context "when no singleton method returns the operation" do
      let(:dummy_operation) do
        Class.new do
          def self.default
            new
          end
        end
      end

      it "raises" do
        expect { operation_container }.to raise_error(%r{Unable to find the appropriate command})
      end
    end

    context "when the operation is anonymous" do
      let(:operation) { Class.new.new }

      it "raises" do
        expect { operation_container }.to raise_error(%r{anonymous operation})
      end
    end
  end
end
