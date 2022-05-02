# frozen_string_literal: true

RSpec.describe Operations::Components::After do
  subject(:component) { described_class.new(after, transaction: transaction, error_reporter: error_reporter) }

  let(:after) do
    [
      ->(params, entity:, **) { Dry::Monads::Success([entity, params]) },
      ->(**) { raise "it hits the fan" },
      ->(**) { Dry::Monads::Failure(:error) }
    ]
  end
  let(:transaction) { instance_double(Proc) }
  let(:error_reporter) { instance_double(Proc) }

  before do
    allow(transaction).to receive(:call).and_yield
    allow(error_reporter).to receive(:call)
  end

  describe "#call" do
    subject(:call) { component.call(params, context) }

    let(:params) { { name: "Batman" } }
    let(:context) { { subject: 42, entity: "Entity" } }

    context "when no after failures" do
      let(:after) { [->(**) { Dry::Monads::Success({}) }] }

      it "doesn't report anything" do
        expect(call).to be_success
        expect(transaction).to have_received(:call).once
        expect(error_reporter).not_to have_received(:call)
      end
    end

    it "returns the results of after calls and always successful" do
      expect(call)
        .to be_success
        .and have_attributes(
          component: :operation,
          params: { name: "Batman" },
          context: { subject: 42, entity: "Entity" },
          after: [
            Dry::Monads::Success(["Entity", { name: "Batman" }]),
            an_instance_of(Dry::Monads::Failure) & have_attributes(failure: an_instance_of(RuntimeError)),
            Dry::Monads::Failure(:error)
          ],
          errors: be_empty
        )
      expect(transaction).to have_received(:call).exactly(3).times
      expect(error_reporter).to have_received(:call).with(
        "Operation side-effects went sideways",
        result: call.as_json
      ).once
    end
  end
end
