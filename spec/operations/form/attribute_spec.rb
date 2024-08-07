# frozen_string_literal: true

RSpec.describe Operations::Form::Attribute do
  subject(:attribute) { described_class.new(name, **options) }

  let(:name) { "name" }
  let(:options) { {} }

  describe "#model_class" do
    subject(:model_class) { attribute.model_class }

    it { is_expected.to be_nil }

    context "with model_name class" do
      let(:options) { { model_name: User } }

      it { is_expected.to eq User }
    end

    context "with model_name present" do
      let(:options) { { model_name: "User" } }

      it { is_expected.to eq User }
    end

    context "with model_name column present" do
      let(:options) { { model_name: "User#age" } }

      it { is_expected.to eq User }
    end
  end

  describe "#model_attribute" do
    subject(:model_attribute) { attribute.model_attribute }

    it { is_expected.to be_nil }

    context "with model_name class" do
      let(:options) { { model_name: User } }

      it { is_expected.to eq "name" }
    end

    context "with model_name present" do
      let(:options) { { model_name: "User" } }

      it { is_expected.to eq "name" }
    end

    context "with model_name column present" do
      let(:options) { { model_name: "User#age" } }

      it { is_expected.to eq "age" }
    end
  end

  describe "#model_type" do
    subject(:model_type) { attribute.model_type }

    it { is_expected.to be_nil }

    context "with model_name class" do
      let(:options) { { model_name: User } }

      it { is_expected.to have_attributes(type: :string) }
    end

    context "with model_name present" do
      let(:options) { { model_name: "User" } }

      it { is_expected.to have_attributes(type: :string) }
    end

    context "with model_name column present" do
      let(:options) { { model_name: "User#age" } }

      it { is_expected.to have_attributes(type: :integer) }
    end
  end

  describe "#model_human_name" do
    subject(:model_human_name) { attribute.model_human_name }

    it { is_expected.to be_nil }

    context "with model_name class" do
      let(:options) { { model_name: User } }

      it { is_expected.to eq "Name" }
    end

    context "with model_name present" do
      let(:options) { { model_name: "User" } }

      it { is_expected.to eq "Name" }
    end

    context "with model_name column present" do
      let(:options) { { model_name: "User#age" } }

      it { is_expected.to eq "Age" }
    end
  end

  describe "#model_validators" do
    subject(:model_validators) { attribute.model_validators }

    it { is_expected.to eq [] }

    context "with model_name class" do
      let(:options) { { model_name: User } }

      it { is_expected.to eq(User.validators_on(:name)) }
    end

    context "with model_name present" do
      let(:options) { { model_name: "User" } }

      it { is_expected.to eq(User.validators_on(:name)) }
    end

    context "with model_name column present" do
      let(:options) { { model_name: "User#age" } }

      it { is_expected.to be_empty }
    end
  end
end
