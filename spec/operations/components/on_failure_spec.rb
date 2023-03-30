# frozen_string_literal: true

RSpec.describe Operations::Components::OnFailure do
  subject(:component) do
    described_class.new(
      callable,
      error_reporter: error_reporter
    )
  end

  let(:callable) do
    [
      ->(params, entity:, **) { Dry::Monads::Success([entity, params]) },
      ->(**) { raise "it hits the fan" },
      ->(**) { Dry::Monads::Failure(:error) }
    ]
  end
  let(:error_reporter) { instance_double(Proc) }

  before do
    allow(error_reporter).to receive(:call)
  end

  describe "#call" do
    subject(:call) { component.call(operation_result) }

    let(:params) { { name: "Batman" } }
    let(:context) { { subject: 42, entity: "Entity" } }
    let(:errors) do
      instance_double(Dry::Validation::MessageSet,
        is_a?: true, empty?: false,
        with: { nil => ["error"] },
        to_h: { nil => ["error"] })
    end
    let(:operation_result) do
      Operations::Result.new(component: :preconditions, params: params, context: context, errors: errors)
    end

    context "when callback does not fail" do
      let(:callable) do
        [->(operation_result) { Dry::Monads::Success({ operation_errors: operation_result.errors.to_h }) }]
      end

      it "doesn't report anything" do
        expect(call)
          .to be_failure
          .and have_attributes(
            component: :preconditions,
            params: { name: "Batman" },
            context: { subject: 42, entity: "Entity" },
            on_failure: [
              Dry::Monads::Success({ operation_errors: { nil => ["error"] } })
            ],
            errors: errors
          )
        expect(error_reporter).not_to have_received(:call)
      end
    end

    it "returns the results of callbacks calls" do
      expect(call)
        .to be_failure
        .and have_attributes(
          component: :preconditions,
          params: { name: "Batman" },
          context: { subject: 42, entity: "Entity" },
          on_failure: [
            Dry::Monads::Success(["Entity", { name: "Batman" }]),
            an_instance_of(Dry::Monads::Failure) & have_attributes(failure: an_instance_of(RuntimeError)),
            Dry::Monads::Failure(:error)
          ],
          errors: errors
        )
      expect(error_reporter).to have_received(:call).with(
        "Operation on_failure side-effects went sideways",
        result: call.as_json(include_command: true)
      ).once
    end
  end
end
