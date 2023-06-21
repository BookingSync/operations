# frozen_string_literal: true

RSpec.describe Operations::Components::Policies do
  subject(:component) { described_class.new(policies, message_resolver: message_resolver) }

  let(:policy) { ->(admin:, **) { admin } }
  let(:additional_policy) { ->(owner:, **) { owner } }
  let(:policies) { [policy] }
  let(:message_resolver) { Operations::Contract::MessagesResolver.new(backend) }
  let(:backend) { Dry::Schema::Messages::YAML.build.merge(translations) }
  let(:translations) do
    {
      en: {
        dry_schema: {
          errors: {
            rules: {
              failure1: "Failure 1",
              unauthorized: "Unauthorized!"
            }
          }
        }
      },
      fr: {
        dry_schema: {
          errors: {
            rules: {
              failure1: "Échec 1",
              unauthorized: "Non autorisé!"
            }
          }
        }
      }
    }.deep_stringify_keys
  end

  describe "#call" do
    subject(:call) { component.call(params, context) }

    let(:params) { { name: "Batman" } }
    let(:context) { { admin: true } }

    context "when policy returns false" do
      let(:context) { { admin: false } }

      it "returns a failed policy result" do
        expect(call)
          .to be_failure
          .and have_attributes(
            component: :policies,
            params: { name: "Batman" },
            context: { admin: false },
            on_success: [],
            errors: have_attributes(
              to_h: {
                nil => [
                  text: "Unauthorized!",
                  code: :unauthorized
                ]
              }
            )
          )
      end

      it "returns full and localized messages" do
        expect(call.errors(full: true).to_h)
          .to eq(nil => [{ text: "Unauthorized!", code: :unauthorized }])
        expect(call.errors(locale: :fr).to_h)
          .to eq(nil => [{ text: "Non autorisé!", code: :unauthorized }])
      end
    end

    context "when policy returns Failure" do
      let(:context) { { admin: Dry::Monads::Failure(:failure1) } }

      it "returns a failed policy result" do
        expect(call)
          .to be_failure
          .and have_attributes(
            component: :policies,
            params: { name: "Batman" },
            context: { admin: Dry::Monads::Failure(:failure1) },
            on_success: [],
            errors: have_attributes(
              to_h: {
                nil => [
                  text: "Failure 1",
                  code: :failure1
                ]
              }
            )
          )
      end

      it "returns full and localized messages" do
        expect(call.errors(full: true).to_h)
          .to eq(nil => [{ text: "Failure 1", code: :failure1 }])
        expect(call.errors(locale: :fr).to_h)
          .to eq(nil => [{ text: "Échec 1", code: :failure1 }])
      end
    end

    context "when one of the policies failed" do
      let(:context) { { admin: Dry::Monads::Success(), owner: false } }
      let(:policies) { [policy, additional_policy] }

      it "returns a failed policy result" do
        expect(call)
          .to be_failure
          .and have_attributes(
            component: :policies,
            params: { name: "Batman" },
            context: { admin: Dry::Monads::Success(), owner: false },
            on_success: [],
            errors: have_attributes(
              to_h: {
                nil => [
                  text: "Unauthorized!",
                  code: :unauthorized
                ]
              }
            )
          )
      end
    end

    context "when multiple policies failed" do
      let(:context) { { admin: Dry::Monads::Failure(:failure1), owner: false } }
      let(:policies) { [policy, additional_policy] }

      it "returns only the first failure" do
        expect(call)
          .to be_failure
          .and have_attributes(
            component: :policies,
            params: { name: "Batman" },
            context: { admin: Dry::Monads::Failure(:failure1), owner: false },
            on_success: [],
            errors: have_attributes(
              to_h: {
                nil => [
                  text: "Failure 1",
                  code: :failure1
                ]
              }
            )
          )
      end
    end

    context "when no policy given" do
      let(:policies) { [] }
      let(:context) { { admin: false } }

      it "returns a successful result" do
        expect(call)
          .to be_success
          .and have_attributes(
            component: :policies,
            params: { name: "Batman" },
            context: { admin: false },
            on_success: [],
            errors: be_empty
          )
      end
    end

    it "returns a successful result" do
      expect(call)
        .to be_success
        .and have_attributes(
          component: :policies,
          params: { name: "Batman" },
          context: { admin: true },
          on_success: [],
          errors: be_empty
        )
    end
  end

  describe "#callable?" do
    subject(:callable?) { component.callable?(context) }

    let(:policy) { ->(foo, bar:, baz: nil) {} }
    let(:context) { { foo: 42 } }

    it { is_expected.to be(false) }

    context "with required context" do
      let(:context) { { bar: 42 } }

      it { is_expected.to be(true) }
    end
  end

  describe "#required_context" do
    subject(:required_context) { component.required_context }

    let(:policy) { ->(foo, bar:, baz: nil) {} }

    it { is_expected.to eq([:bar]) }

    context "with no policies given" do
      let(:policies) { [] }

      it { is_expected.to eq([]) }
    end

    context "with context_key defined" do
      let(:policy) do
        Class.new do
          def self.context_key
            :boo
          end

          def self.call(foo, bar:, baz: nil); end
        end
      end

      it { is_expected.to eq(%i[bar boo]) }
    end

    context "with context_keys defined" do
      let(:policy) do
        Class.new do
          def self.context_keys
            %i[bar baz boo]
          end

          def self.call(foo, bar:, baz: nil); end
        end
      end

      it { is_expected.to eq(%i[bar baz boo]) }
    end
  end
end
