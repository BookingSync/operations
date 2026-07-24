# frozen_string_literal: true

RSpec.describe Operations::Sidekiq::Convenience do
  let(:dummy_operation) do
    Class.new do
      extend Operations::Sidekiq::Convenience

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
  let(:serialized_params) { { "name" => "Bruice", "$sidekiq_symbol_keys" => ["name"] } }
  let(:serialized_context) { { "context1" => "value1", "$sidekiq_symbol_keys" => ["context1"] } }

  describe ".default_async" do
    subject(:call) { dummy_operation.default_async.call({ name: "Bruice" }, context1: "value1") }

    before do
      stub_const("DummyOperation", dummy_operation)
      allow(dummy_operation.default).to receive(:call!).and_call_original
    end

    it "memoizes the async command" do
      expect(dummy_operation.default_async).to equal(dummy_operation.default_async)
    end

    it "schedules the job" do
      expect(call).to be_success
      expect(Operations::Sidekiq::Job.jobs).to match([
        a_hash_including(
          "args" => ["DummyOperation", "default", serialized_params, serialized_context, "call!"],
          "queue" => "default"
        )
      ])
    end

    it "calls the operation in a job", :inline_jobs do
      expect(call).to be_success
      expect(dummy_operation.default).to have_received(:call!).with({ name: "Bruice" }, context1: "value1")
    end
  end

  describe ".default_try_async" do
    subject(:call) { dummy_operation.default_try_async.call({ name: "Bruice" }, context1: "value1") }

    let(:dummy_operation) do
      Class.new do
        extend Operations::Sidekiq::Convenience[queue: :important]

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

    before do
      stub_const("DummyOperation", dummy_operation)
      allow(dummy_operation.default).to receive(:try_call!).and_call_original
    end

    it "memoizes the async command" do
      expect(dummy_operation.default_try_async).to equal(dummy_operation.default_try_async)
    end

    it "schedules the job on the configured queue with try_call!" do
      expect(call).to be_success
      expect(Operations::Sidekiq::Job.jobs).to match([
        a_hash_including(
          "args" => ["DummyOperation", "default", serialized_params, serialized_context, "try_call!"],
          "queue" => "important"
        )
      ])
    end

    it "calls the operation in a job", :inline_jobs do
      expect(call).to be_success
      expect(dummy_operation.default).to have_received(:try_call!).with({ name: "Bruice" }, context1: "value1")
    end
  end

  describe ".on_retries_exhausted" do
    subject(:on_retries_exhausted) { dummy_operation.on_retries_exhausted }

    let(:callback) { instance_double(Operations::Command) }
    let(:dummy_operation) do
      callback_instance = callback
      Class.new do
        extend Operations::Sidekiq::Convenience[retry: 3, on_retries_exhausted: callback_instance]

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

    before do
      stub_const("DummyOperation", dummy_operation)
      allow(callback).to receive(:call!)
    end

    it { is_expected.to eq(callback) }

    it "calls the callback when retries are exhausted" do
      msg = {
        "args" => ["DummyOperation", "default", serialized_params, serialized_context, "call!"]
      }

      Operations::Sidekiq::Job.sidekiq_retries_exhausted_block.call(msg, StandardError.new("test"))

      expect(callback).to have_received(:call!).with({ name: "Bruice" }, context1: "value1")
    end
  end
end
