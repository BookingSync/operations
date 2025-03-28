# frozen_string_literal: true

RSpec.describe Operations::Components::Preconditions do
  subject(:component) { described_class.new(preconditions, message_resolver: message_resolver) }

  let(:preconditions) { [->(**) {}] }
  let(:message_resolver) { Operations::Contract::MessagesResolver.new(backend) }
  let(:backend) { Dry::Schema::Messages::YAML.build.merge(translations) }
  let(:translations) do
    {
      en: {
        dry_schema: {
          errors: {
            rules: {
              failure1: "Failure 1"
            }
          }
        }
      },
      fr: {
        dry_schema: {
          errors: {
            rules: {
              failure1: "Échec 1"
            }
          }
        }
      }
    }.deep_stringify_keys
  end

  describe "#call" do
    subject(:call) { component.call(params, context) }

    let(:params) { { name: "Batman" } }
    let(:context) { { subject: 42 } }

    context "with multiple preconditions" do
      let(:preconditions) do
        [
          lambda { |**|
            [
              :failure1,
              { message: :failure1, path: nil },
              { message: "failure2", path: [:name] },
              "failure3",
              { text: "Failure 4", path: [:name, 1], code: :foobar }
            ]
          },
          ->(params, **) { { error: "Failure", path: [nil], **params } },
          ->(**) {}
        ]
      end

      it "aggregates failures" do
        expect(call)
          .to be_failure
          .and have_attributes(
            component: :preconditions,
            params: { name: "Batman" },
            context: { subject: 42 },
            on_success: [],
            errors: have_attributes(
              to_h: {
                nil => [
                  { text: "Failure 1", code: :failure1 },
                  { text: "Failure 1", code: :failure1 },
                  "failure3",
                  { text: "Failure", name: "Batman" }
                ],
                name: [["failure2"], { 1 => [{ text: "Failure 4", code: :foobar }] }]
              }
            )
          )
      end

      it "returns full and localized messages" do
        expect(call.errors(full: true).to_h).to eq(
          nil => [
            { text: "Failure 1", code: :failure1 },
            { text: "Failure 1", code: :failure1 },
            "failure3",
            { text: "Failure", name: "Batman" }
          ],
          name: [["name failure2"], { 1 => [{ code: :foobar, text: "1 Failure 4" }] }]
        )
        expect(call.errors(locale: :fr).to_h).to eq(
          nil => [
            { text: "Échec 1", code: :failure1 },
            { text: "Échec 1", code: :failure1 },
            "failure3",
            { text: "Failure", name: "Batman" }
          ],
          name: [["failure2"], { 1 => [{ code: :foobar, text: "Failure 4" }] }]
        )
      end
    end

    context "when preconditions return monads" do
      let(:preconditions) do
        [
          ->(**) { Dry::Monads::Success() },
          ->(**) { Dry::Monads::Failure(:failure1) }
        ]
      end

      it "handles them as well" do
        expect(call)
          .to be_failure
          .and have_attributes(
            component: :preconditions,
            params: { name: "Batman" },
            context: { subject: 42 },
            on_success: [],
            errors: have_attributes(
              to_h: {
                nil => [
                  { text: "Failure 1", code: :failure1 }
                ]
              }
            )
          )
      end
    end

    context "when no preconditions" do
      let(:preconditions) { [] }

      it "returns a successful result" do
        expect(call)
          .to be_success
          .and have_attributes(
            component: :preconditions,
            params: { name: "Batman" },
            context: { subject: 42 },
            on_success: [],
            errors: be_empty
          )
      end
    end

    it "returns a successful result" do
      expect(call)
        .to be_success
        .and have_attributes(
          component: :preconditions,
          params: { name: "Batman" },
          context: { subject: 42 },
          on_success: [],
          errors: be_empty
        )
    end
  end

  describe "#callable?" do
    subject(:callable?) { component.callable?(context) }

    let(:preconditions) do
      [
        ->(foo, subject1:, subject2:, **) {},
        ->(subject1:, subject3: nil, **) {}
      ]
    end
    let(:context) { { subject1: 42 } }

    it { is_expected.to be(false) }

    context "with required context" do
      let(:context) { { subject1: 42, subject2: 43 } }

      it { is_expected.to be(true) }
    end
  end

  describe "#required_context" do
    subject(:required_context) { component.required_context }

    let(:preconditions) do
      [
        ->(foo, subject1:, subject2:, **) {},
        ->(subject1:, subject3: nil, **) {}
      ]
    end

    it { is_expected.to eq(%i[subject1 subject2]) }

    context "with no policy given" do
      let(:preconditions) { [] }

      it { is_expected.to eq([]) }
    end

    context "with context_key/context_keys defined" do
      let(:preconditions) do
        [
          Class.new do
            def self.call(foo, subject1:, subject2:, **); end

            def self.context_key
              :subject3
            end
          end,
          Class.new do
            def self.call(subject1:, subject3: nil, **); end

            def self.context_keys
              %i[subject1 subject4]
            end
          end
        ]
      end

      it { is_expected.to eq(%i[subject1 subject2 subject3 subject4]) }
    end
  end
end
