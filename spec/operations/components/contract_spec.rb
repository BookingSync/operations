# frozen_string_literal: true

RSpec.describe Operations::Components::Contract do
  subject(:component) { described_class.new(contract) }

  let(:contract) do
    Operations::Contract.build do
      config.messages.load_paths << 'spec/fixtures/locale.yml'

      schema do
        required(:name).filled(:string)
      end

      rule do |context:|
        context[:object] ||= :foo
        base.failure("forcefully failed") if context[:forced_rule_error]
      end
    end
  end

  describe "#call" do
    subject(:call) { component.call(params, context) }

    let(:params) { { name: "Batman" } }
    let(:context) { { admin: true, object: :foo } }

    context "when contract validation failed" do
      let(:params) { {} }

      it "returns a failed validation result" do
        expect(call)
          .to be_failure
          .and have_attributes(
            component: :contract,
            params: {},
            context: { admin: true, object: :foo },
            after: [],
            errors: have_attributes(
              to_h: { name: ["is missing"] }
            )
          )
      end

      it "returns full and localized messages" do
        expect(call.errors(full: true).to_h).to eq(name: ["name is missing"])
        expect(call.errors(locale: :fr).to_h).to eq(name: ["est manquant"])
      end
    end

    context "when contract rule failed" do
      let(:context) { { admin: true, forced_rule_error: true } }

      it "returns a failed validation result" do
        expect(call)
          .to be_failure
          .and have_attributes(
            component: :contract,
            params: { name: "Batman" },
            context: { admin: true, forced_rule_error: true, object: :foo },
            after: [],
            errors: have_attributes(
              to_h: { nil => ["forcefully failed"] }
            )
          )
      end
    end

    it "returns a successful result" do
      expect(call)
        .to be_success
        .and have_attributes(
          component: :contract,
          params: { name: "Batman" },
          context: { admin: true, object: :foo },
          after: [],
          errors: be_empty
        )
    end
  end
end
