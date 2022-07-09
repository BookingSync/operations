# frozen_string_literal: true

RSpec.describe Operations::Command do
  subject(:composite) do
    described_class.new(
      operation,
      contract: contract,
      policies: policies,
      preconditions: preconditions,
      idempotency: idempotency_checks,
      after: on_success,
      **composite_options
    )
  end

  let(:operation) { ->(**) { Dry::Monads::Success(additional: :value) } }
  let(:contract) do
    Operations::Contract.build do
      config.messages.load_paths << "spec/fixtures/locale.yml"
      schema { required(:name).filled(:string) }
      rule { User.create!(name: "transaction test") }
    end
  end
  let(:policy) { ->(admin:, **) { admin } }
  let(:additional_policy) { ->(owner:, **) { owner } }
  let(:policies) { [policy] }
  let(:preconditions) { [->(error:, **) { error }] }
  let(:idempotency_checks) { [] }
  let(:on_success) { [->(**) { Dry::Monads::Success(:yay) }] }
  let(:composite_options) { {} }

  describe ".new" do
    context "without policy and policies options" do
      subject(:composite) do
        described_class.new(
          operation,
          contract: contract,
          preconditions: preconditions,
          after: on_success
        )
      end

      specify { expect { composite }.to raise_error(KeyError) }
    end
  end

  describe ".build" do
    subject(:build) { described_class.build(operation_class, repo: repo) }

    let(:operation_class) do
      Class.new do
        extend Dry::Initializer
        option :repo

        def call; end

        const_set(:Contract, Class.new(Dry::Validation::Contract) do
          option :repo
          schema { nil }
        end)
        const_set(:Policy, Class.new do
          extend Dry::Initializer
          option :repo

          def call; end
        end)
      end
    end
    let(:repo) { double }

    it "initializes composite operation with all the nested classes" do
      expect(build).to have_attributes(
        operation: an_instance_of(operation_class) & have_attributes(repo: repo),
        contract: an_instance_of(operation_class::Contract) & have_attributes(repo: repo),
        policies: [an_instance_of(operation_class::Policy) & have_attributes(repo: repo)],
        preconditions: [],
        on_success: [],
        form_class: be < Operations::Form
      )
    end

    context "when Precondition is defined" do
      before do
        operation_class.const_set(:Precondition, Class.new do
          extend Dry::Initializer
          option :repo

          def call; end
        end)
      end

      it "initializes composite operation also with precondition" do
        expect(build).to have_attributes(
          operation: an_instance_of(operation_class) & have_attributes(repo: repo),
          contract: an_instance_of(operation_class::Contract) & have_attributes(repo: repo),
          policies: [an_instance_of(operation_class::Policy) & have_attributes(repo: repo)],
          preconditions: [an_instance_of(operation_class::Precondition) & have_attributes(repo: repo)],
          on_success: [],
          form_class: be < Operations::Form
        )
      end
    end

    context "when alternative contract is passed explicitly" do
      subject(:build) { described_class.build(operation_class, alternative_contract_class, repo: repo) }

      let(:alternative_contract_class) do
        Class.new(Dry::Validation::Contract) do
          option :repo
          schema { nil }
        end
      end

      it "initializes composite operation with all the nested classes and the alternative contract" do
        expect(build).to have_attributes(
          operation: an_instance_of(operation_class) & have_attributes(repo: repo),
          contract: an_instance_of(alternative_contract_class) & have_attributes(repo: repo),
          policies: [an_instance_of(operation_class::Policy) & have_attributes(repo: repo)],
          preconditions: [],
          on_success: [],
          form_class: be < Operations::Form
        )
      end
    end
  end

  describe "#form_class" do
    subject(:form_class) { composite.form_class }

    let(:contract) do
      Operations::Contract.build do
        schema do
          required(:name).filled(:string)
          required(:age).filled(:integer)
        end
      end
    end
    let(:composite_options) { { form_model_map: { name: "Dummy" } } }

    it "passes model map to builder" do
      expect(form_class).to have_attributes(attributes: {
        name: have_attributes(name: :name, model_name: "Dummy"),
        age: have_attributes(name: :age, model_name: nil)
      })
    end
  end

  describe "#==" do
    def build(**kwargs)
      described_class.new(operation, contract: contract, **kwargs)
    end

    it { is_expected.to eq(composite) }
    it { is_expected.to eq(build(policies: [policy], preconditions: preconditions, after: on_success)) }
    it { is_expected.not_to eq(build(policies: [policy])) }
    it { is_expected.not_to eq(build(policy: -> {}, preconditions: preconditions)) }
  end

  describe "#call" do
    subject(:call) { composite.call(params, **context) }

    let(:params) { { name: "Batman" } }
    let(:context) { {} }

    context "when contract failed" do
      let(:params) { {} }

      it "returns a failed validation result" do
        expect { call }.not_to change { User.count }
        expect(call)
          .to be_failure
          .and have_attributes(
            operation: composite,
            component: :contract,
            params: {},
            context: {},
            on_success: [],
            errors: have_attributes(
              to_h: { name: ["is missing"] }
            )
          )
      end
    end

    context "when policy failed" do
      let(:context) { { admin: false } }

      it "returns a failed policy result" do
        expect { call }.not_to change { User.count }
        expect(call)
          .to be_failure
          .and have_attributes(
            operation: composite,
            component: :policies,
            params: { name: "Batman" },
            context: { admin: false },
            on_success: [],
            errors: have_attributes(
              to_h: { nil => [
                text: "Unauthorized",
                code: :unauthorized
              ] }
            )
          )
      end
    end

    context "when one of the policies failed" do
      let(:context) { { admin: false, owner: true } }
      let(:policies) { [policy, additional_policy] }

      it "returns a failed policy result" do
        expect { call }.not_to change { User.count }
        expect(call)
          .to be_failure
          .and have_attributes(
            operation: composite,
            component: :policies,
            params: { name: "Batman" },
            context: { admin: false, owner: true },
            on_success: [],
            errors: have_attributes(
              to_h: { nil => [
                text: "Unauthorized",
                code: :unauthorized
              ] }
            )
          )
      end
    end

    context "when preconditions failed" do
      let(:context) { { admin: true, error: "Error" } }

      it "returns a failed preconditions result" do
        expect { call }.not_to change { User.count }
        expect(call)
          .to be_failure
          .and have_attributes(
            operation: composite,
            component: :preconditions,
            params: { name: "Batman" },
            context: { admin: true, error: "Error" },
            on_success: [],
            errors: have_attributes(
              to_h: { nil => ["Error"] }
            )
          )
      end
    end

    context "when idempotency check failed" do
      let(:context) { { admin: true, error: nil } }
      let(:idempotency_checks) { [->(_, **) { Dry::Monads::Failure(additional: :value) }] }
      let(:operation) { ->(**) { raise } }

      it "returns a successful result and stops on idempotency check stage" do
        expect { call }.not_to change { User.count }
        expect(call)
          .to be_success
          .and have_attributes(
            operation: composite,
            component: :idempotency,
            params: { name: "Batman" },
            context: { admin: true, error: nil, additional: :value },
            on_success: [],
            errors: be_empty
          )
      end
    end

    context "with insufficient context" do
      let(:params) { {} }
      let(:context) { { admin: true } }

      it "returns a failed validation result" do
        expect { call }.not_to change { User.count }
        expect(call)
          .to be_failure
          .and have_attributes(
            operation: composite,
            component: :contract,
            params: {},
            context: { admin: true },
            on_success: [],
            errors: have_attributes(
              to_h: { name: ["is missing"] }
            )
          )
      end
    end

    context "with correct context" do
      let(:context) { { admin: true, error: nil } }

      context "when operation failed" do
        let(:operation) { ->(**) { Dry::Monads::Failure("Error") } }

        it "returns a normalized operation result" do
          expect { call }.not_to change { User.count }
          expect(call)
            .to be_failure
            .and have_attributes(
              operation: composite,
              component: :operation,
              params: { name: "Batman" },
              context: { admin: true, error: nil },
              on_success: [],
              errors: have_attributes(
                to_h: { nil => ["Error"] }
              )
            )
        end
      end

      it "returns a successful result" do
        expect { call }.to change { User.count }.by(1)
        expect(call)
          .to be_success
          .and have_attributes(
            operation: composite,
            component: :operation,
            params: { name: "Batman" },
            context: { admin: true, error: nil, additional: :value },
            on_success: [Dry::Monads::Success(:yay)],
            errors: be_empty
          )
      end
    end
  end

  describe "#call!" do
    subject(:call!) { composite.call!(params, **context) }

    let(:params) { { name: "Batman" } }
    let(:context) { { admin: true, error: nil } }

    context "when operation failed" do
      let(:params) { {} }

      specify do
        expect { call! }.to raise_error do |error|
          expect(error).to be_a(Operations::Command::OperationFailed)
          expect(error.message).to eq("Proc failed on contract")
          expect(error.sentry_context).to include(errors: { name: ["name is missing"] })
        end
      end
    end

    it { is_expected.to be_success }
  end

  describe "#try_call!" do
    subject(:try_call!) { composite.try_call!(params, **context) }

    let(:params) { { name: "Batman" } }
    let(:context) { { admin: true, error: nil } }

    context "when contract failed" do
      let(:params) { {} }

      specify do
        expect { try_call! }.to raise_error do |error|
          expect(error).to be_a(Operations::Command::OperationFailed)
          expect(error.message).to eq("Proc failed on contract")
          expect(error.sentry_context).to include(errors: { name: ["name is missing"] })
        end
      end
    end

    context "when policy failed" do
      let(:context) { { admin: false, error: nil } }

      it { is_expected.to be_failure & have_attributes(component: :policies) }
    end

    context "when precondition failed" do
      let(:context) { { admin: true, error: "Error" } }

      it { is_expected.to be_failure & have_attributes(component: :preconditions) }
    end

    context "when operation failed" do
      let(:operation) { ->(**) { Dry::Monads::Failure("Runtime error") } }

      specify do
        expect { try_call! }.to raise_error do |error|
          expect(error).to be_a(Operations::Command::OperationFailed)
          expect(error.message).to eq("Proc failed on operation")
          expect(error.sentry_context).to include(errors: { nil => ["Runtime error"] })
        end
      end
    end

    it { is_expected.to be_success }
  end

  describe "#validate" do
    subject(:validate) { composite.validate(params, **context) }

    let(:context) { { admin: true, error: nil } }
    let(:params) { { name: "TEST" } }

    it "returns a successful result" do
      expect(validate)
        .to be_success
        .and have_attributes(
          operation: composite,
          component: :contract,
          params: { name: "TEST" },
          context: { admin: true, error: nil },
          on_success: [],
          errors: be_empty
        )
    end

    context "with invalid params and sufficient context" do
      let(:params) { { name: nil } }

      it "returns a failed validation result" do
        expect(validate)
          .to be_failure
          .and have_attributes(
            operation: composite,
            component: :contract,
            params: { name: nil },
            context: { admin: true, error: nil },
            on_success: [],
            errors: have_attributes(
              to_h: { name: ["must be a string"] }
            )
          )
      end
    end

    context "with insufficient context" do
      let(:context) { { admin: true } }
      let(:params) { {} }

      it "returns a failed validation result" do
        expect(validate)
          .to be_failure
          .and have_attributes(
            operation: composite,
            component: :contract,
            params: {},
            context: { admin: true },
            on_success: [],
            errors: have_attributes(
              to_h: { name: ["is missing"] }
            )
          )
      end
    end

    context "when policy failed" do
      let(:context) { { admin: false, error: nil } }

      it "returns a failed policy result" do
        expect(validate)
          .to be_failure
          .and have_attributes(
            operation: composite,
            component: :policies,
            params: { name: "TEST" },
            context: { admin: false, error: nil },
            on_success: [],
            errors: have_attributes(
              to_h: { nil => [
                text: "Unauthorized",
                code: :unauthorized
              ] }
            )
          )
      end
    end

    context "when preconditions failed" do
      let(:context) { { admin: true, error: "Error" } }

      it "returns a failed preconditions result" do
        expect(validate)
          .to be_failure
          .and have_attributes(
            operation: composite,
            component: :preconditions,
            params: { name: "TEST" },
            context: { admin: true, error: "Error" },
            on_success: [],
            errors: have_attributes(
              to_h: { nil => ["Error"] }
            )
          )
      end
    end
  end

  describe "#valid?" do
    subject(:valid?) { composite.valid?(params, **context) }

    let(:context) { { admin: true, error: nil } }
    let(:params) { { name: "TEST" } }

    it { is_expected.to be true }

    context "when check failed" do
      let(:params) { { name: nil } }

      it { is_expected.to be false }
    end
  end

  describe "#callable" do
    subject(:callable) { composite.callable(**context) }

    let(:context) { { admin: true, error: nil } }

    context "with insufficient context" do
      let(:context) { { admin: true } }

      it "returns a failed validation result" do
        expect(callable)
          .to be_failure
          .and have_attributes(
            operation: composite,
            component: :contract,
            params: {},
            context: { admin: true },
            on_success: [],
            errors: have_attributes(
              to_h: { name: ["is missing"] }
            )
          )
      end
    end

    context "when policy failed" do
      let(:context) { { admin: false, error: nil } }

      it "returns a failed policy result" do
        expect(callable)
          .to be_failure
          .and have_attributes(
            operation: composite,
            component: :policies,
            params: {},
            context: { admin: false, error: nil },
            on_success: [],
            errors: have_attributes(
              to_h: { nil => [
                text: "Unauthorized",
                code: :unauthorized
              ] }
            )
          )
      end
    end

    context "when preconditions failed" do
      let(:context) { { admin: true, error: "Error" } }

      it "returns a failed preconditions result" do
        expect(callable)
          .to be_failure
          .and have_attributes(
            operation: composite,
            component: :preconditions,
            params: {},
            context: { admin: true, error: "Error" },
            on_success: [],
            errors: have_attributes(
              to_h: { nil => ["Error"] }
            )
          )
      end
    end

    it "returns a successful result" do
      expect(callable)
        .to be_success
        .and have_attributes(
          operation: composite,
          component: :preconditions,
          params: {},
          context: { admin: true, error: nil },
          on_success: [],
          errors: be_empty
        )
    end
  end

  describe "#callable?" do
    subject(:callable?) { composite.callable?(**context) }

    let(:context) { { admin: true, error: nil } }

    context "when check failed" do
      let(:context) { { admin: false } }

      it { is_expected.to be false }
    end

    it { is_expected.to be true }
  end

  describe "#allowed" do
    subject(:allowed) { composite.allowed(**context) }

    let(:context) { { admin: true } }

    context "when policy failed" do
      let(:context) { { admin: false } }

      it "returns a failed policy result" do
        expect(allowed)
          .to be_failure
          .and have_attributes(
            operation: composite,
            component: :policies,
            params: {},
            context: { admin: false },
            on_success: [],
            errors: have_attributes(
              to_h: { nil => [
                text: "Unauthorized",
                code: :unauthorized
              ] }
            )
          )
      end
    end

    it "returns a successful result" do
      expect(allowed)
        .to be_success
        .and have_attributes(
          operation: composite,
          component: :policies,
          params: {},
          context: { admin: true },
          on_success: [],
          errors: be_empty
        )
    end
  end

  describe "#allowed?" do
    subject(:allowed?) { composite.allowed?(**context) }

    let(:context) { { admin: true } }

    context "when check failed" do
      let(:context) { { admin: false } }

      it { is_expected.to be false }
    end

    it { is_expected.to be true }
  end

  describe "#possible" do
    subject(:possible) { composite.possible(**context) }

    let(:context) { { error: nil } }

    context "when preconditions failed" do
      let(:context) { { error: "Error" } }

      it "returns a failed preconditions result" do
        expect(possible)
          .to be_failure
          .and have_attributes(
            operation: composite,
            component: :preconditions,
            params: {},
            context: { error: "Error" },
            on_success: [],
            errors: have_attributes(
              to_h: { nil => ["Error"] }
            )
          )
      end
    end

    it "returns a successful result" do
      expect(possible)
        .to be_success
        .and have_attributes(
          operation: composite,
          component: :preconditions,
          params: {},
          context: { error: nil },
          on_success: [],
          errors: be_empty
        )
    end
  end

  describe "#possible?" do
    subject(:possible?) { composite.possible?(**context) }

    let(:context) { { error: nil } }

    context "when check failed" do
      let(:context) { { error: "Error" } }

      it { is_expected.to be false }
    end

    it { is_expected.to be true }
  end

  describe "#as_json" do
    subject(:as_json) { command.as_json }

    let(:command) { DummyOperation.instance }
    let(:command_implementation) do
      Class.new do
        def self.instance
          Operations::Command.new(
            new,
            contract: DummyOperation::Contract.new,
            policy: DummyOperation::Policy.new,
            precondition: DummyOperation::Precondition.new,
            idempotency: [DummyOperation::IdempotencyCheck.new],
            on_success: [DummyOperation::OnSuccess.new],
            form_base: DummyOperation::FormBase,
            form_class: DummyOperation::FormClass,
            form_model_map: { attribute: "attribute_map" },
            form_hydrator: DummyOperation::FormHydrator.new,
            info_reporter: DummyOperation::InfoReporter.new,
            error_reporter: DummyOperation::ErrorReporter.new,
            transaction: DummyOperation::Transaction.new
          )
        end

        def call; end

        const_set(:Contract, Class.new(Dry::Validation::Contract) do
          schema { nil }
        end)
        const_set(:Policy, Class.new do
          def call; end
        end)
        const_set(:Precondition, Class.new do
          def call; end
        end)
        const_set(:OnSuccess, Class.new do
          def call; end
        end)
        const_set(:IdempotencyCheck, Class.new do
          def call; end
        end)
        const_set(:FormBase, Class.new)
        const_set(:FormClass, Class.new)
        const_set(:FormHydrator, Class.new do
          def call; end
        end)
        const_set(:InfoReporter, Class.new do
          def call; end
        end)
        const_set(:ErrorReporter, Class.new do
          def call; end
        end)
        const_set(:Transaction, Class.new do
          def call; end
        end)
      end
    end

    before do
      stub_const("DummyOperation", command_implementation)
    end

    specify do
      expect(as_json).to eq(
        operation: "DummyOperation",
        contract: "DummyOperation::Contract",
        policies: ["DummyOperation::Policy"],
        preconditions: ["DummyOperation::Precondition"],
        idempotency: ["DummyOperation::IdempotencyCheck"],
        on_success: ["DummyOperation::OnSuccess"],
        form_base: "DummyOperation::FormBase",
        form_class: "DummyOperation::FormClass",
        form_hydrator: "DummyOperation::FormHydrator",
        form_model_map: { [:attribute] => "attribute_map" },
        info_reporter: "DummyOperation::InfoReporter",
        error_reporter: "DummyOperation::ErrorReporter",
        transaction: "DummyOperation::Transaction"
      )
    end
  end
end
