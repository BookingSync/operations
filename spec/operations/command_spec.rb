# frozen_string_literal: true

RSpec.describe Operations::Command do
  subject(:command) do
    described_class.new(
      operation,
      contract: contract,
      policies: policies,
      preconditions: preconditions,
      idempotency: idempotency_checks,
      on_success: on_success,
      on_failure: on_failure,
      **command_options
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
  let(:on_failure) { [on_failure_callback] }
  let(:on_failure_callback) { ->(_, **) { Dry::Monads::Success(:wow) } }
  let(:command_options) { {} }

  describe ".new" do
    context "without policy and policies options" do
      subject(:command) do
        described_class.new(
          operation,
          contract: contract,
          preconditions: preconditions,
          on_success: on_success,
          on_failure: on_failure
        )
      end

      specify { expect { command }.to raise_error(KeyError) }
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

    it "initializes command operation with all the nested classes" do
      expect(build).to have_attributes(
        operation: an_instance_of(operation_class) & have_attributes(repo: repo),
        contract: an_instance_of(operation_class::Contract) & have_attributes(repo: repo),
        policies: [an_instance_of(operation_class::Policy) & have_attributes(repo: repo)],
        preconditions: [],
        on_success: [],
        on_failure: [],
        form_class: be < Operations::Form::Base
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

      it "initializes command operation also with precondition" do
        expect(build).to have_attributes(
          operation: an_instance_of(operation_class) & have_attributes(repo: repo),
          contract: an_instance_of(operation_class::Contract) & have_attributes(repo: repo),
          policies: [an_instance_of(operation_class::Policy) & have_attributes(repo: repo)],
          preconditions: [an_instance_of(operation_class::Precondition) & have_attributes(repo: repo)],
          on_success: [],
          on_failure: [],
          form_class: be < Operations::Form::Base
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

      it "initializes command operation with all the nested classes and the alternative contract" do
        expect(build).to have_attributes(
          operation: an_instance_of(operation_class) & have_attributes(repo: repo),
          contract: an_instance_of(alternative_contract_class) & have_attributes(repo: repo),
          policies: [an_instance_of(operation_class::Policy) & have_attributes(repo: repo)],
          preconditions: [],
          on_success: [],
          on_failure: [],
          form_class: be < Operations::Form::Base
        )
      end
    end
  end

  describe "#merge" do
    subject(:merge) { command.merge(**changes) }

    let(:new_on_success) { ->(**) {} }
    let(:changes) do
      {
        operation: :ignored,
        policies: [policy, additional_policy],
        on_success: [new_on_success]
      }
    end

    specify do
      expect(merge).to have_attributes(
        operation: operation,
        contract: contract,
        policies: [policy, additional_policy],
        preconditions: preconditions,
        on_success: [new_on_success],
        on_failure: on_failure
      )
    end
  end

  describe "#form_class" do
    subject(:form_class) { command.form_class }

    let(:contract) do
      Operations::Contract.build do
        schema do
          required(:name).filled(:string)
          required(:age).filled(:integer)
        end
      end
    end
    let(:command_options) { { form_model_map: { name: "Dummy" } } }

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

    it { is_expected.to eq(command) }
    it { is_expected.not_to eq(build(policies: [policy])) }
    it { is_expected.not_to eq(build(policy: -> {}, preconditions: preconditions)) }

    specify do
      expect(command).to eq(
        build(
          policies: [policy],
          preconditions: preconditions,
          after: on_success,
          on_failure: on_failure
        )
      )
    end
  end

  describe "#call" do
    subject(:call) { command.call(params, **context) }

    let(:params) { { name: "Batman" } }
    let(:context) { {} }

    context "when contract failed" do
      let(:params) { {} }

      it "returns a failed validation result" do
        expect { call }.not_to change { User.count }
        expect(call)
          .to be_failure
          .and have_attributes(
            operation: command,
            component: :contract,
            params: {},
            context: {},
            on_success: [],
            on_failure: [],
            errors: have_attributes(
              to_h: { name: ["is missing"] }
            )
          )
      end
    end

    context "when policy failed even if contract failed and preconditions are not callable" do
      let(:params) { {} }
      let(:context) { { admin: false } }

      it "returns a failed policy result" do
        expect { call }.not_to change { User.count }
        expect(call)
          .to be_failure
          .and have_attributes(
            operation: command,
            component: :policies,
            params: {},
            context: { admin: false },
            on_success: [],
            on_failure: [],
            errors: have_attributes(
              to_h: {
                nil => [
                  text: "Unauthorized",
                  code: :unauthorized
                ]
              }
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
            operation: command,
            component: :policies,
            params: { name: "Batman" },
            context: { admin: false, owner: true },
            on_success: [],
            on_failure: [],
            errors: have_attributes(
              to_h: {
                nil => [
                  text: "Unauthorized",
                  code: :unauthorized
                ]
              }
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
            operation: command,
            component: :preconditions,
            params: { name: "Batman" },
            context: { admin: true, error: "Error" },
            on_success: [],
            on_failure: [],
            errors: have_attributes(
              to_h: { nil => ["Error"] }
            )
          )
      end
    end

    context "when idempotency check failed" do
      let(:context) { { admin: true, error: "Error" } }
      let(:idempotency_checks) { [->(_, **) { Dry::Monads::Failure(additional: :value) }] }
      let(:operation) { ->(**) { raise } }

      it "returns a successful result and stops on idempotency check stage" do
        expect { call }.not_to change { User.count }
        expect(call)
          .to be_success
          .and have_attributes(
            operation: command,
            component: :idempotency,
            params: { name: "Batman" },
            context: { admin: true, error: "Error", additional: :value },
            on_success: [],
            on_failure: [],
            errors: be_empty
          )
      end
    end

    context "when idempotency check succeeded" do
      let(:context) { { admin: true, error: nil } }
      let(:idempotency_checks) { [->(_, **) { Dry::Monads::Success() }] }
      let(:operation) { ->(**) { Dry::Monads::Success({ additional: :value }) } }

      it "calls the operation and goes through all the stages" do
        expect { call }.to change { User.count }
        expect(call)
          .to be_success
          .and have_attributes(
            operation: command,
            component: :operation,
            params: { name: "Batman" },
            context: { admin: true, error: nil, additional: :value },
            on_success: [Dry::Monads::Success(:yay)],
            on_failure: [],
            errors: be_empty
          )
      end
    end

    context "when idempotency check succeeded but precondition failed" do
      let(:context) { { admin: true, error: "Error" } }
      let(:idempotency_checks) { [->(_, **) { Dry::Monads::Success() }] }
      let(:operation) { ->(**) { Dry::Monads::Success({ additional: :value }) } }

      it "calls the operation and goes through all the stages" do
        expect { call }.not_to change { User.count }
        expect(call)
          .to be_failure
          .and have_attributes(
            operation: command,
            component: :preconditions,
            params: { name: "Batman" },
            context: { admin: true, error: "Error" },
            on_success: [],
            on_failure: [],
            errors: have_attributes(
              to_h: { nil => ["Error"] }
            )
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
            operation: command,
            component: :contract,
            params: {},
            context: { admin: true },
            on_success: [],
            on_failure: [],
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

        before { allow(on_failure_callback).to receive(:call).and_call_original }

        it "returns a normalized operation result" do
          expect { call }.not_to change { User.count }
          expect(call)
            .to be_failure
            .and have_attributes(
              operation: command,
              component: :operation,
              params: { name: "Batman" },
              context: { admin: true, error: nil },
              on_success: [],
              on_failure: [Dry::Monads::Success(:wow)],
              errors: have_attributes(
                to_h: { nil => ["Error"] }
              )
            )
        end

        context "when on_failure callback failed" do
          let(:on_failure_callback) { ->(_, **) { Dry::Monads::Failure(:wow) } }
          let(:command_options) { { configuration: Operations.default_config.new(error_reporter: error_reporter) } }
          let(:error_reporter) { -> {} }

          before { allow(error_reporter).to receive(:call) }

          it "returns a normalized operation result" do
            expect { call }.not_to change { User.count }
            expect(call)
              .to be_failure
              .and have_attributes(
                operation: command,
                component: :operation,
                params: { name: "Batman" },
                context: { admin: true, error: nil },
                on_success: [],
                on_failure: [Dry::Monads::Failure(:wow)],
                errors: have_attributes(
                  to_h: { nil => ["Error"] }
                )
              )
            expect(on_failure_callback).to have_received(:call).with(
              { name: "Batman" },
              { admin: true, error: nil, operation_failure: { nil => ["Error"] } }
            )
            expect(error_reporter).to have_received(:call).with(
              "Operation on_failure side-effects went sideways",
              include(:result)
            )
          end
        end
      end

      it "returns a successful result" do
        expect { call }.to change { User.count }.by(1)
        expect(call)
          .to be_success
          .and have_attributes(
            operation: command,
            component: :operation,
            params: { name: "Batman" },
            context: { admin: true, error: nil, additional: :value },
            on_success: [Dry::Monads::Success(:yay)],
            on_failure: [],
            errors: be_empty
          )
      end

      context "when on_success callback failed but there is a wrapping transaction" do
        let(:on_success) { [->(**) { Dry::Monads::Failure(:yay) }] }
        let(:command_options) { { configuration: Operations.default_config.new(error_reporter: error_reporter) } }
        let(:error_reporter) { -> {} }

        before { allow(error_reporter).to receive(:call) }

        it "returns a normalized operation result" do
          ActiveRecord::Base.transaction do
            expect { call }.to change { User.count }.by(1)
            expect(call)
              .to be_success
              .and have_attributes(
                operation: command,
                component: :operation,
                params: { name: "Batman" },
                context: { admin: true, error: nil, additional: :value },
                on_success: [],
                on_failure: [],
                errors: be_empty
              )
            expect(error_reporter).not_to have_received(:call)
          end

          expect(error_reporter).to have_received(:call).with(
            "Operation on_success side-effects went sideways",
            include(:result)
          )
        end
      end

      context "when on_success callback failed" do
        let(:on_success) { [->(**) { Dry::Monads::Failure(:yay) }] }
        let(:command_options) { { configuration: Operations.default_config.new(error_reporter: error_reporter) } }
        let(:error_reporter) { -> {} }

        before { allow(error_reporter).to receive(:call) }

        it "returns a normalized operation result" do
          expect { call }.to change { User.count }.by(1)
          expect(call)
            .to be_success
            .and have_attributes(
              operation: command,
              component: :operation,
              params: { name: "Batman" },
              context: { admin: true, error: nil, additional: :value },
              on_success: [Dry::Monads::Failure(:yay)],
              on_failure: [],
              errors: be_empty
            )
          expect(error_reporter).to have_received(:call).with(
            "Operation on_success side-effects went sideways",
            include(:result)
          )
        end
      end
    end
  end

  describe "#call!" do
    subject(:call!) { command.call!(params, **context) }

    let(:params) { { name: "Batman" } }
    let(:context) { { admin: true, error: nil } }

    context "when operation failed" do
      let(:params) { {} }

      specify do
        expect { call! }.to raise_error do |error|
          expect(error).to be_a(Operations::Command::OperationFailed)
          expect(error.message).to eq("Proc failed on contract\nname - is missing\n")
          expect(error.sentry_context).to include(errors: { name: ["name is missing"] })
        end
      end
    end

    it { is_expected.to be_success }
  end

  describe "#try_call!" do
    subject(:try_call!) { command.try_call!(params, **context) }

    let(:params) { { name: "Batman" } }
    let(:context) { { admin: true, error: nil } }

    context "when contract failed" do
      let(:params) { {} }

      specify do
        expect { try_call! }.to raise_error do |error|
          expect(error).to be_a(Operations::Command::OperationFailed)
          expect(error.message).to eq("Proc failed on contract\nname - is missing\n")
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
          expect(error.message).to eq("Proc failed on operation\n - Runtime error\n")
          expect(error.sentry_context).to include(errors: { nil => ["Runtime error"] })
        end
      end
    end

    it { is_expected.to be_success }
  end

  describe "#validate" do
    subject(:validate) { command.validate(params, **context) }

    let(:context) { { admin: true, error: nil } }
    let(:params) { { name: "TEST" } }

    it "returns a successful result" do
      expect(validate)
        .to be_success
        .and have_attributes(
          operation: command,
          component: :contract,
          params: { name: "TEST" },
          context: { admin: true, error: nil },
          on_success: [],
          on_failure: [],
          errors: be_empty
        )
    end

    context "with invalid params and sufficient context" do
      let(:params) { { name: nil } }

      it "returns a failed validation result" do
        expect(validate)
          .to be_failure
          .and have_attributes(
            operation: command,
            component: :contract,
            params: { name: nil },
            context: { admin: true, error: nil },
            on_success: [],
            on_failure: [],
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
            operation: command,
            component: :contract,
            params: {},
            context: { admin: true },
            on_success: [],
            on_failure: [],
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
            operation: command,
            component: :policies,
            params: { name: "TEST" },
            context: { admin: false, error: nil },
            on_success: [],
            on_failure: [],
            errors: have_attributes(
              to_h: {
                nil => [
                  text: "Unauthorized",
                  code: :unauthorized
                ]
              }
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
            operation: command,
            component: :preconditions,
            params: { name: "TEST" },
            context: { admin: true, error: "Error" },
            on_success: [],
            on_failure: [],
            errors: have_attributes(
              to_h: { nil => ["Error"] }
            )
          )
      end
    end
  end

  describe "#valid?" do
    subject(:valid?) { command.valid?(params, **context) }

    let(:context) { { admin: true, error: nil } }
    let(:params) { { name: "TEST" } }

    it { is_expected.to be true }

    context "when check failed" do
      let(:params) { { name: nil } }

      it { is_expected.to be false }
    end
  end

  describe "#callable" do
    subject(:callable) { command.callable(**context) }

    let(:context) { { admin: true, error: nil } }

    context "with insufficient context" do
      let(:context) { { admin: true } }

      it "returns a failed validation result" do
        expect(callable)
          .to be_failure
          .and have_attributes(
            operation: command,
            component: :contract,
            params: {},
            context: { admin: true },
            on_success: [],
            on_failure: [],
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
            operation: command,
            component: :policies,
            params: {},
            context: { admin: false, error: nil },
            on_success: [],
            on_failure: [],
            errors: have_attributes(
              to_h: {
                nil => [
                  text: "Unauthorized",
                  code: :unauthorized
                ]
              }
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
            operation: command,
            component: :preconditions,
            params: {},
            context: { admin: true, error: "Error" },
            on_success: [],
            on_failure: [],
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
          operation: command,
          component: :preconditions,
          params: {},
          context: { admin: true, error: nil },
          on_success: [],
          on_failure: [],
          errors: be_empty
        )
    end
  end

  describe "#callable?" do
    subject(:callable?) { command.callable?(**context) }

    let(:context) { { admin: true, error: nil } }

    context "when check failed" do
      let(:context) { { admin: false } }

      it { is_expected.to be false }
    end

    it { is_expected.to be true }
  end

  describe "#allowed" do
    subject(:allowed) { command.allowed(**context) }

    let(:context) { { admin: true } }

    context "when policy failed" do
      let(:context) { { admin: false } }

      it "returns a failed policy result" do
        expect(allowed)
          .to be_failure
          .and have_attributes(
            operation: command,
            component: :policies,
            params: {},
            context: { admin: false },
            on_success: [],
            on_failure: [],
            errors: have_attributes(
              to_h: {
                nil => [
                  text: "Unauthorized",
                  code: :unauthorized
                ]
              }
            )
          )
      end
    end

    it "returns a successful result" do
      expect(allowed)
        .to be_success
        .and have_attributes(
          operation: command,
          component: :policies,
          params: {},
          context: { admin: true },
          on_success: [],
          on_failure: [],
          errors: be_empty
        )
    end
  end

  describe "#allowed?" do
    subject(:allowed?) { command.allowed?(**context) }

    let(:context) { { admin: true } }

    context "when check failed" do
      let(:context) { { admin: false } }

      it { is_expected.to be false }
    end

    it { is_expected.to be true }
  end

  describe "#possible" do
    subject(:possible) { command.possible(**context) }

    let(:context) { { error: nil } }

    context "when preconditions failed" do
      let(:context) { { error: "Error" } }

      it "returns a failed preconditions result" do
        expect(possible)
          .to be_failure
          .and have_attributes(
            operation: command,
            component: :preconditions,
            params: {},
            context: { error: "Error" },
            on_success: [],
            on_failure: [],
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
          operation: command,
          component: :preconditions,
          params: {},
          context: { error: nil },
          on_success: [],
          on_failure: [],
          errors: be_empty
        )
    end
  end

  describe "#possible?" do
    subject(:possible?) { command.possible?(**context) }

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
            on_failure: [DummyOperation::OnFailure.new],
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
        const_set(:OnFailure, Class.new do
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
        "operation" => "DummyOperation",
        "contract" => "DummyOperation::Contract",
        "policies" => ["DummyOperation::Policy"],
        "preconditions" => ["DummyOperation::Precondition"],
        "idempotency" => ["DummyOperation::IdempotencyCheck"],
        "on_success" => ["DummyOperation::OnSuccess"],
        "on_failure" => ["DummyOperation::OnFailure"],
        "form_base" => "DummyOperation::FormBase",
        "form_class" => "DummyOperation::FormClass",
        "form_hydrator" => "DummyOperation::FormHydrator",
        "form_model_map" => { "[:attribute]" => "attribute_map" },
        "configuration" => { "after_commit" => {}, "error_reporter" => {}, "transaction" => {} }
      )
    end
  end

  describe "#pretty_inspect" do
    subject(:pretty_inspect) { normalize_inspect(command.pretty_inspect) }

    specify do
      expect(pretty_inspect).to eq(<<~INSPECT)
        #<Operations::Command
         operation=#<Proc:0x>,
         contract=#<#<Class:0x> schema=#<Dry::Schema::Processor keys=[:name] rules={name: "key?(:name) \
        AND key[name](str? AND filled?)"}> rules=[#<Dry::Validation::Rule keys=[]>]>,
         policies=[#<Proc:0x>],
         idempotency=[],
         preconditions=[#<Proc:0x>],
         on_success=[#<Proc:0x>],
         on_failure=[#<Proc:0x>],
         form_model_map={},
         form_base=#<Class attributes={}>,
         form_class=#<Class
           attributes={name:
              #<Operations::Form::Attribute
               name=:name,
               collection=false,
               model_class=nil,
               model_attribute=nil,
               form=nil>}>,
         form_hydrator=#<Proc:0x>,
         configuration=#<Operations::Configuration info_reporter=nil \
        error_reporter=#<Proc:0x> transaction=#<Proc:0x> after_commit=#<Proc:0x>>>
      INSPECT
    end
  end
end
