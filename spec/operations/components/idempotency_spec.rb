# frozen_string_literal: true

RSpec.describe Operations::Components::Idempotency do
  subject(:component) { described_class.new(idempotency_checks, info_reporter: info_reporter) }

  let(:idempotency_checks) { [->(_, **) { Dry::Monads::Success(unused: :value) }] }
  let(:info_reporter) { instance_double(Proc) }

  before { allow(info_reporter).to receive(:call) }

  describe "#call" do
    subject(:call) { component.call(params, context) }

    let(:params) { { name: "Batman" } }
    let(:context) { { subject: 42 } }

    context "with idempotency checks failure" do
      let(:idempotency_checks) do
        [
          ->(_, **) { Dry::Monads::Success() },
          ->(_, **) { Dry::Monads::Failure(additional: :value) }
        ]
      end

      it "returns a failure result" do
        expect(call)
          .to be_failure
          .and have_attributes(
            failure: have_attributes(
              component: :idempotency,
              params: { name: "Batman" },
              context: { subject: 42, additional: :value },
              on_success: [],
              errors: be_empty
            )
          )
        expect(info_reporter).to have_received(:call).with(
          "Idempotency check failed",
          {
            failed_check: %r{#<Proc:},
            result: {
              command: nil,
              component: :idempotency,
              context: { additional: ":value", subject: "42" },
              errors: {},
              on_failure: [],
              on_success: [],
              params: { name: "Batman" }
            }
          }
        )
      end
    end

    context "when no idempotency checks" do
      let(:idempotency_checks) { [] }

      it "returns a successful result" do
        expect(call)
          .to be_success
          .and have_attributes(
            value!: have_attributes(
              component: :idempotency,
              params: { name: "Batman" },
              context: { subject: 42 },
              on_success: [],
              errors: be_empty
            )
          )
        expect(info_reporter).not_to have_received(:call)
      end
    end

    it "returns a successful result" do
      expect(call)
        .to be_success
        .and have_attributes(
          value!: have_attributes(
            component: :idempotency,
            params: { name: "Batman" },
            context: { subject: 42 },
            on_success: [],
            errors: be_empty
          )
        )
      expect(info_reporter).not_to have_received(:call)
    end
  end
end
