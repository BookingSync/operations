# frozen_string_literal: true

RSpec.describe Operations::Form::Attribute do
  subject(:attribute) { described_class.new(name, **attribute_options) }

  let(:name) { "name" }
  let(:attribute_options) { {} }

  describe "#model_type" do
    subject(:model_type) { attribute.model_type }

    it { is_expected.to be_nil }

    context "with model_name present" do
      let(:attribute_options) { { model_name: "User" } }

      it { is_expected.to have_attributes(type: :string) }
    end
  end

  describe "#model_human_name" do
    subject(:model_human_name) { attribute.model_human_name }

    it { is_expected.to be_nil }

    context "with model_name present" do
      let(:attribute_options) { { model_name: "User" } }

      it { is_expected.to eq "Name" }
    end
  end

  describe "#model_validators" do
    subject(:model_validators) { attribute.model_validators }

    it { is_expected.to eq [] }

    context "with model_name present" do
      let(:attribute_options) { { model_name: User } }

      it { is_expected.to eq(User.validators_on(:name)) }
    end
  end

  describe "#model_localized_attr_name" do
    subject(:model_localized_attr_name) { attribute.model_localized_attr_name(:fr) }

    it { is_expected.to be_nil }

    context "with model_name present" do
      let(:attribute_options) { { model_name: User } }

      it { is_expected.to eq "name_fr" }
    end
  end
end
