# frozen_string_literal: true

RSpec.describe Operations::Components::OnSuccess do
  subject(:component) do
    described_class.new(
      callable,
      error_reporter: error_reporter,
      after_commit: after_commit
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

  before do
    allow(after_commit).to receive(:call).and_yield
    allow(error_reporter).to receive(:call)
  end

  describe "#call" do
    subject(:call) { component.call(operation_result) }

    let(:params) { { name: "Batman" } }
    let(:context) { { subject: 42, entity: "Entity" } }
    let(:operation_result) do
      Operations::Result.new(component: :operation, params: params, context: context)
    end

    context "when callback does not failure" do
      let(:callable) do
        [->(operation_result) { Dry::Monads::Success({ operation_params: operation_result.params }) }]
      end

      it "doesn't report anything" do
        expect(call)
          .to be_success
          .and have_attributes(
            component: :operation,
            params: { name: "Batman" },
            context: { subject: 42, entity: "Entity" },
            on_success: [Dry::Monads::Success({ operation_params: { name: "Batman" } })],
            errors: be_empty
          )
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
      expect(after_commit).to have_received(:call).once
      expect(error_reporter).to have_received(:call).with(
        "Operation on_success side-effects went sideways",
        result: call.as_json(include_command: true)
      ).once
    end
  end
end
