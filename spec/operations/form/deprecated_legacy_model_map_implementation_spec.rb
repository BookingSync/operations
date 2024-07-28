# frozen_string_literal: true

RSpec.describe Operations::Form::DeprecatedLegacyModelMapImplementation do
  subject(:model_map) { described_class.new(model_map_hash) }

  let(:model_map_hash) { { ["name"] => "Dummy1", ["translations", %r{singular|plural}] => "Dummy2" } }

  describe "#call" do
    subject(:call) { model_map.call(path) }

    context "with non-existing path" do
      let(:path) { ["foobar"] }

      it { is_expected.to be_nil }
    end

    context "with simple path" do
      let(:path) { ["name"] }

      it { is_expected.to eq("Dummy1") }
    end

    context "with unfinished path" do
      let(:path) { ["translations"] }

      it { is_expected.to be_nil }
    end

    context "with regexp-matched path" do
      let(:path) { %w[translations singular] }

      it { is_expected.to eq("Dummy2") }
    end
  end
end
