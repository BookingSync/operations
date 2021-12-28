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
end
