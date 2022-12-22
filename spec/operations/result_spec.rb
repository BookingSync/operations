# frozen_string_literal: true

RSpec.describe Operations::Result do
  subject(:result) do
    described_class.new(
      operation: operation,
      component: component,
      params: params,
      context: context,
      on_success: on_success,
      on_failure: on_failure,
      **{ errors: errors }.compact
    )
  end

  let(:operation) { instance_double(Operations::Command) }
  let(:component) { :contract }
  let(:params) { {} }
  let(:context) { {} }
  let(:errors) { nil }
  let(:on_success) { [] }
  let(:on_failure) { [] }
  let(:message) { instance_double(Dry::Validation::Message) }

  before do
    allow(operation).to receive(:is_a?).and_return(false)
    allow(operation).to receive(:is_a?).with(Operations::Command).and_return(true)
  end

  describe "#==" do
    def build(**kwargs)
      described_class.new(
        operation: operation,
        component: component,
        params: params,
        context: context,
        **kwargs
      )
    end

    it { is_expected.to eq(result) }
    it { is_expected.to eq(build(errors: Dry::Validation::MessageSet.new([]))) }
    it { is_expected.not_to eq(build(errors: Dry::Validation::MessageSet.new([message]))) }
    it { is_expected.not_to eq(build(component: :policies)) }
    it { is_expected.not_to eq(build(params: { foo: 42 })) }
    it { is_expected.not_to eq(build(context: { foo: 42 })) }
  end

  describe "#merge" do
    subject(:merge) { result.merge(**changes) }

    let(:changes) { { params: { foo: 42 } } }

    specify do
      expect(merge).to have_attributes(
        operation: operation,
        component: component,
        params: { foo: 42 },
        context: context,
        on_success: [],
        on_failure: []
      )
    end
  end

  describe "#errors" do
    let(:message) do
      Dry::Validation::Message::Localized.new(
        ->(full:, **) { [full ? "Full message" : "Simple message", {}] },
        path: "column"
      )
    end
    let(:errors) { Dry::Validation::MessageSet.new([message]).freeze }

    it "renders messages with different options" do
      expect(result.errors.to_h).to eq("column" => ["Simple message"])
      expect(result.errors(full: true).to_h).to eq("column" => ["Full message"])
    end
  end

  describe "#success?" do
    it { is_expected.to be_success }

    context "with errors" do
      let(:errors) { Dry::Validation::MessageSet.new([message]) }

      it { is_expected.not_to be_success }
    end
  end

  describe "#callable?" do
    it { is_expected.to be_callable }

    context "with errors" do
      let(:errors) { Dry::Validation::MessageSet.new([message]) }

      it { is_expected.not_to be_callable }
    end
  end

  describe "#failure?" do
    it { is_expected.not_to be_failure }

    context "with errors" do
      let(:errors) { Dry::Validation::MessageSet.new([message]) }

      it { is_expected.to be_failure }
    end
  end

  describe "#failed_policy?" do
    let(:message) { instance_double(Dry::Validation::Message, meta: { code: :unauthorized }) }
    let(:errors) { Dry::Validation::MessageSet.new([message]) }

    specify do
      expect(result).not_to be_failed_policy
      expect(result).not_to be_failed_precheck
    end

    context "with policies failure" do
      let(:component) { :policies }

      specify do
        expect(result).to be_failed_policy
        expect(result).to be_failed_precheck
        expect(result).to be_failed_policy(:unauthorized)
        expect(result).to be_failed_precheck(:unauthorized)
        expect(result).to be_failed_policy(:unauthorized, :unrelated)
        expect(result).to be_failed_precheck(:unauthorized, :unrelated)
        expect(result).not_to be_failed_policy(:unrelated)
        expect(result).not_to be_failed_precheck(:unrelated)
      end
    end
  end

  describe "#failed_precondition?" do
    let(:message1) { instance_double(Dry::Validation::Message, meta: { code: :precondition1 }) }
    let(:message2) { instance_double(Dry::Validation::Message, meta: { code: :precondition2 }) }
    let(:errors) { Dry::Validation::MessageSet.new([message1, message2]) }

    specify do
      expect(result).not_to be_failed_precondition
      expect(result).not_to be_failed_precheck
    end

    context "with preconditions failure" do
      let(:component) { :preconditions }

      specify do
        expect(result).to be_failed_precondition
        expect(result).to be_failed_precheck
        expect(result).to be_failed_precondition(:precondition1)
        expect(result).to be_failed_precheck(:precondition1)
        expect(result).to be_failed_precondition(:precondition1, :precondition2)
        expect(result).to be_failed_precheck(:precondition1, :precondition2)
        expect(result).to be_failed_precondition(:precondition1, :unrelated)
        expect(result).to be_failed_precheck(:precondition1, :unrelated)
        expect(result).not_to be_failed_precondition(:unrelated)
        expect(result).not_to be_failed_precheck(:unrelated)
      end
    end
  end

  describe "#to_monad" do
    subject(:to_monad) { result.to_monad }

    it { is_expected.to eq Dry::Monads::Success(result) }

    context "with errors" do
      let(:errors) { Dry::Validation::MessageSet.new([message]) }

      it { is_expected.to eq Dry::Monads::Failure(result) }
    end
  end

  describe "#form" do
    subject(:form) { result.form }

    let(:operation) do
      instance_double(
        Operations::Command,
        form_class: form_class,
        form_hydrator: lambda do |form_class, params, **context|
          { form_class: form_class, params: params, context: context }
        end
      )
    end
    let(:form_class) do
      Class.new do
        attr_reader :params, :messages

        def initialize(params, messages:)
          @params = params
          @messages = messages
        end
      end
    end
    let(:params) { { key: "value" } }
    let(:context) { { entity: "object" } }
    let(:errors) { instance_double(Dry::Validation::MessageSet, is_a?: true, to_h: { name: ["error"] }) }

    it "returns the form instance" do
      expect(form).to be_a(form_class)
        .and have_attributes(
          params: { form_class: form_class, params: { key: "value" }, context: { entity: "object" } },
          messages: { name: ["error"] }
        )
    end
  end

  describe "#as_json" do
    subject(:as_json) { result.as_json }

    let(:traceable_object) { Struct.new(:id, :name) }
    let(:anonymous_object) { Struct.new(:name) }
    let(:params) { { id: 123, name: "Jon", lastname: "Snow" } }
    let(:context) { { record: TraceableObject.new(1, "Some name"), object: AnonymousObject.new("Some name") } }
    let(:message) do
      Dry::Validation::Message::Localized.new(
        ->(**) { ["Error message", {}] },
        path: "column"
      )
    end
    let(:on_success) { [Dry::Monads::Success(Entity: "Model#1"), Dry::Monads::Failure(additional: :value)] }
    let(:on_failure) { [Dry::Monads::Success(Entity: "Model#1"), Dry::Monads::Failure(additional: :value)] }
    let(:errors) { Dry::Validation::MessageSet.new([message]).freeze }
    let(:command_json) do
      {
        operation: "DummyOperation",
        contract: "DummyOperation::Contract",
        policies: ["DummyOperation::Policy"],
        preconditions: ["DummyOperation::Precondition"],
        idempotency: ["DummyOperation::IdempotencyCheck"],
        on_success: ["DummyOperation::OnSuccess"],
        on_failure: ["DummyOperation::OnFailure"],
        form_model_map: { [:attribute] => "attribute_map" },
        form_base: "Operations::Form",
        form_class: "DummyOperation::Form",
        form_hydrator: "Hydrator",
        info_reporter: "InfoReporter",
        error_reporter: "ErrorReporter",
        transaction: "TransactionClass"
      }
    end

    before do
      stub_const("TraceableObject", traceable_object)
      stub_const("AnonymousObject", anonymous_object)

      allow(operation).to receive(:as_json).and_return(command_json)
    end

    specify do
      expect(as_json).to include(
        component: :contract,
        command: command_json,
        params: { id: 123, name: "Jon", lastname: "Snow" },
        context: { record: "TraceableObject#1", object: '#<struct AnonymousObject name="Some name">' },
        on_success: match([
          { "value" => { "Entity" => "Model#1" } },
          include("trace", "value" => { "additional" => "value" })
        ]),
        on_failure: match([
          { "value" => { "Entity" => "Model#1" } },
          include("trace", "value" => { "additional" => "value" })
        ]),
        errors: { "column" => ["Error message"] }
      )
    end
  end
end
