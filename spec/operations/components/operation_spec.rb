# frozen_string_literal: true

require "rails_helper"

RSpec.describe Operation::Components::Operation do
  subject(:component) { described_class.new(operation, message_resolver: message_resolver) }

  let(:operation) { ->(entity, **params) { Dry::Monads::Success({ passed: [entity, params] }) } }
  let(:message_resolver) { Operation::Contract::MessagesResolver.new(backend) }
  let(:backend) { Dry::Schema::Messages::YAML.build.merge(translations) }
  let(:translations) do
    {
      en: {
        dry_schema: {
          errors: {
            rules: {
              failure: "Failure"
            }
          }
        }
      }.deep_stringify_keys
    }
  end

  describe "#call" do
    subject(:call) { component.call(params, context) }

    let(:params) { { name: "Batman" } }
    let(:context) { { subject: 42, entity: "Entity" } }

    context "when operation returns a failure" do
      let(:operation) { ->(**) { Dry::Monads::Failure([error: :failure]) } }

      it "renders it as an error" do
        expect(call)
          .to be_failure
          .and have_attributes(
            component: :operation,
            params: { name: "Batman" },
            context: { subject: 42, entity: "Entity" },
            after: [],
            errors: have_attributes(
              to_h: { nil => [{ text: "Failure", code: :failure }] }
            )
          )
      end
    end

    it "merges the returned result to the context" do
      expect(call)
        .to be_success
        .and have_attributes(
          component: :operation,
          params: { name: "Batman" },
          context: { subject: 42, entity: "Entity", passed: ["Entity", { name: "Batman" }] },
          after: [],
          errors: be_empty
        )
    end
  end
end
