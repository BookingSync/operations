# frozen_string_literal: true

RSpec.describe Operations::Sidekiq::Command do
  let(:dummy_operation) do
    Class.new do
      def self.default
        @default ||= new
      end

      def call!(_params, **_context)
        Dry::Monads::Success(foo: 42)
      end
      alias_method :try_call!, :call!
    end
  end
  let(:command) { described_class.new("DummyOperation", "default", **options) }
  let(:options) { { try_call: false } }
  let(:serialized_params) { { "name" => "Bruice", "$sidekiq_symbol_keys" => ["name"] } }
  let(:serialized_context) { { "context1" => "value1", "$sidekiq_symbol_keys" => ["context1"] } }

  before do
    stub_const("DummyOperation", dummy_operation)
    allow(DummyOperation.default).to receive(:call!).and_call_original
    allow(DummyOperation.default).to receive(:try_call!).and_call_original
  end

  describe "#in" do
    subject(:in_) { command.in(5.minutes) }

    it "returns a new command with the delay set" do
      expect(in_).to be_a(described_class)
      expect(in_).not_to eq(command)
      expect(in_.delay).to eq(5.minutes)
    end
  end

  describe "#at" do
    subject(:at) { command.at(time) }

    let(:time) { 5.minutes.from_now }

    it "returns a new command with the time set" do
      expect(at).to be_a(described_class)
      expect(at).not_to eq(command)
      expect(at.time).to eq(time)
    end
  end

  describe "#set" do
    subject(:set) { command.set(queue: :slow) }

    it "returns a new command with the sidekiq options set" do
      expect(set).to be_a(described_class)
      expect(set).not_to eq(command)
      expect(set.sidekiq_options).to eq(queue: :slow)
    end
  end

  describe "#call" do
    subject(:call) { command.call({ name: "Bruice" }, context1: "value1") }

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
      expect(DummyOperation.default).to have_received(:call!).with({ name: "Bruice" }, context1: "value1")
    end

    context "with try_call set" do
      let(:options) { { try_call: true } }

      it "schedules the job with try_call!" do
        expect(call).to be_success
        expect(Operations::Sidekiq::Job.jobs).to match([
          a_hash_including("args" => ["DummyOperation", "default", serialized_params, serialized_context, "try_call!"])
        ])
      end

      it "calls the operation in a job", :inline_jobs do
        expect(call).to be_success
        expect(DummyOperation.default).to have_received(:try_call!).with({ name: "Bruice" }, context1: "value1")
      end
    end

    context "with delay set" do
      let(:options) { { try_call: false, delay: 5.minutes } }

      it "schedules the job in the future" do
        expect(call).to be_success
        expect(Operations::Sidekiq::Job.jobs).to match([
          a_hash_including(
            "args" => ["DummyOperation", "default", serialized_params, serialized_context, "call!"],
            "at" => be_a(Float)
          )
        ])
      end
    end

    context "with time set" do
      let(:options) { { try_call: false, time: time } }
      let(:time) { 5.minutes.from_now }

      it "schedules the job at the given time" do
        expect(call).to be_success
        expect(Operations::Sidekiq::Job.jobs).to match([
          a_hash_including(
            "args" => ["DummyOperation", "default", serialized_params, serialized_context, "call!"],
            "at" => time.to_f
          )
        ])
      end
    end

    context "with sidekiq_options set" do
      let(:options) { { try_call: false, sidekiq_options: { queue: :slow } } }

      it "schedules the job on the given queue" do
        expect(call).to be_success
        expect(Operations::Sidekiq::Job.jobs).to match([a_hash_including("queue" => "slow")])
      end
    end
  end
end
