# frozen_string_literal: true

RSpec.describe Operations::Components::Callback do
  subject(:component) do
    described_class.new(
      callable,
      after_commit: after_commit,
      error_reporter: error_reporter,
      callback_type: callback_type
    )
  end

  let(:callable) do
    [
      ->(params, entity:, **) { Dry::Monads::Success([entity, params]) },
      ->(**) { raise "it hits the fan" },
      ->(**) { Dry::Monads::Failure(:error) }
    ]
  end
  let(:after_commit) { instance_double(Proc) }
  let(:error_reporter) { instance_double(Proc) }
  let(:callback_type) { :on_success }

  before do
    allow(after_commit).to receive(:call).and_yield
    allow(error_reporter).to receive(:call)
  end

  describe "#call" do
    subject(:call) { component.call(params, context) }

    let(:params) { { name: "Batman" } }
    let(:context) { { subject: 42, entity: "Entity" } }

    context "when callback does not failure" do
      let(:callable) { [->(**) { Dry::Monads::Success({}) }] }

      it "doesn't report anything" do
        expect(call).to be_success
        expect(after_commit).to have_received(:call).once
        expect(error_reporter).not_to have_received(:call)
      end
    end

    it "returns the results of callable calls and always successful" do
      expect(call)
        .to be_success
        .and have_attributes(
          component: :operation,
          params: { name: "Batman" },
          context: { subject: 42, entity: "Entity" },
          on_success: [
            Dry::Monads::Success(["Entity", { name: "Batman" }]),
            an_instance_of(Dry::Monads::Failure) & have_attributes(failure: an_instance_of(RuntimeError)),
            Dry::Monads::Failure(:error)
          ],
          errors: be_empty
        )
      expect(after_commit).to have_received(:call).exactly(3).times
      expect(error_reporter).to have_received(:call).with(
        "Operation on_success side-effects went sideways",
        result: call.as_json
      ).once
    end

    context "when on_failure" do
      let(:callback_type) { :on_failure }

      it "returns the results of callable calls" do
        expect(call)
          .to be_success
          .and have_attributes(
            component: :operation,
            params: { name: "Batman" },
            context: { subject: 42, entity: "Entity" },
            on_failure: [
              Dry::Monads::Success(["Entity", { name: "Batman" }]),
              an_instance_of(Dry::Monads::Failure) & have_attributes(failure: an_instance_of(RuntimeError)),
              Dry::Monads::Failure(:error)
            ],
            errors: be_empty
          )
        expect(after_commit).not_to have_received(:call)
        expect(error_reporter).to have_received(:call).with(
          "Operation on_failure side-effects went sideways",
          result: call.as_json
        ).once
      end
    end
  end
end
