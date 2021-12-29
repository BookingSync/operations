# frozen_string_literal: true

RSpec.describe Operations::Contract do
  subject(:contract) do
    Class.new(described_class) do
      schema
    end
  end

  describe ".inherited" do
    before do
      stub_const("Foo::Bar::Baz", contract)
      # simulating inheritance
      described_class.inherited(contract)
    end

    it "has a proper configuration set" do
      expect(contract.config.messages.to_h).to include(
        backend: :yaml,
        top_namespace: "operations",
        namespace: "foo/bar"
      )
    end
  end

  describe ".ensure_presence" do
    subject(:errors) { contract.new.call(params, **context).errors.to_h }

    let(:contract) do
      Class.new(described_class) do
        config.messages.load_paths << "spec/fixtures/locale.yml"

        params do
          optional(:user_id).filled(:integer)
        end

        ensure_presence :user
      end
    end
    let(:params) { {} }
    let(:context) { {} }

    it { is_expected.to eq(user_id: [{ code: :key?, text: "is missing" }]) }

    context "when id is invalid" do
      let(:params) { { user_id: "foobar" } }

      it { is_expected.to eq(user_id: ["must be an integer"]) }
    end

    context "when id is valid" do
      let(:params) { { user_id: 42 } }

      it { is_expected.to eq(user_id: [{ code: :not_found, text: "User does not exist" }]) }
    end

    context "when entity is present" do
      let(:context) { { user: :foobar } }

      it { is_expected.to be_empty }
    end
  end
end
