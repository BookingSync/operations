# frozen_string_literal: true

RSpec.describe Operations::Form do
  subject(:form) { form_class.new(attributes, messages: messages) }

  let(:form_class) do
    local_author_class = author_class
    local_post_class = post_class

    Class.new(described_class) do
      attribute :name
      attribute :tags, collection: true
      attribute :author, form: local_author_class
      attribute :posts, collection: true, form: local_post_class
    end
  end
  let(:author_class) do
    Class.new(described_class) do
      attribute :title
    end
  end
  let(:post_class) do
    Class.new(author_class) do
      attribute :text
    end
  end
  let(:attributes) { {} }
  let(:messages) { {} }

  before do
    stub_const("Dummy::Form", form_class)
    stub_const("Dummy::Author", author_class)
    stub_const("Dummy::Post", post_class)
  end

  context "where there is a field with model_name attached" do
    let(:form_class) do
      Class.new(described_class) do
        attribute :name, model_name: "User"
      end
    end

    describe ".human_attribute_name" do
      subject(:human_attribute_name) { form_class.human_attribute_name("name") }

      it { is_expected.to eq("Name") }

      context "with non-existing attribute" do
        subject(:human_attribute_name) { form_class.human_attribute_name("foobar") }

        it { is_expected.to eq("Foobar") }
      end
    end

    describe ".validators_on" do
      subject(:validators_on) { form_class.validators_on("name") }

      it { is_expected.not_to be_empty }
    end

    describe "#type_for_attribute" do
      subject(:type_for_attribute) { form.type_for_attribute("name") }

      it { is_expected.to have_attributes(type: :string) }
    end

    describe "#localized_attr_name_for" do
      subject(:localized_attr_name_for) { form.localized_attr_name_for("name", :fr) }

      it { is_expected.to eq "name_fr" }
    end
  end

  describe "has_attribute?" do
    specify do
      expect(form).to have_attribute(:name)
      expect(form).not_to have_attribute(:foobar)
    end
  end

  describe "#attributes" do
    it "has all the attributes blank by default" do
      expect(form.attributes).to match(
        name: nil,
        tags: [],
        author: have_attributes(class: author_class, attributes: { title: nil }),
        posts: []
      )
    end

    context "when invalid data is passed" do
      let(:random_object) { double }
      let(:attributes) do
        {
          name: [],
          tags: "string",
          author: random_object,
          posts: false,
          unknown: 42
        }
      end

      it "handles it gracefully" do
        expect(form.attributes).to eq(
          name: [],
          tags: "string",
          author: random_object,
          posts: false
        )
      end
    end

    context "when valid data is passed" do
      let(:attributes) do
        {
          name: 42,
          tags: ["tag1"],
          author: { title: "Batman", ignored: 42 },
          posts: [
            { title: "Post1", ignored: 42 },
            "wtf",
            {}
          ]
        }
      end

      it "handles it gracefully" do
        expect(form.attributes).to match(
          name: 42,
          tags: ["tag1"],
          author: have_attributes(class: author_class, attributes: { title: "Batman" }),
          posts: [
            have_attributes(class: post_class, attributes: { title: "Post1", text: nil }),
            "wtf",
            have_attributes(class: post_class, attributes: { title: nil, text: nil })
          ]
        )
      end
    end

    context "when nested attributes are passed" do
      let(:attributes) do
        {
          author_attributes: { title: "Batman" },
          posts_attributes: { 0 => { title: "Post1" } }
        }
      end

      it "assigns them appropriately" do
        expect(form.attributes).to include(
          author: have_attributes(class: author_class, attributes: { title: "Batman" }),
          posts: [
            have_attributes(class: post_class, attributes: { title: "Post1", text: nil })
          ]
        )
      end
    end
  end

  describe "#assigned_attributes" do
    subject(:assigned_attributes) { form.assigned_attributes }

    it { is_expected.to eq({}) }

    context "when some params passed" do
      let(:attributes) do
        {
          name: "Name",
          author: { ignored: 42 },
          ignored: 42
        }
      end

      it "returns only attributes passed to the intializer" do
        expect(assigned_attributes).to match(
          name: "Name",
          author: have_attributes(class: author_class, assigned_attributes: {})
        )
      end
    end
  end

  describe "#model_name" do
    specify { expect(subject.model_name).to be_a(ActiveModel::Name) }
    specify { expect(subject.model_name.to_s).to eq "Dummy::Form" }
  end

  describe "#errors" do
    let(:attributes) do
      {
        author: {},
        posts: [{ title: "Post1" }, { title: "Post2" }]
      }
    end

    specify { expect(subject.errors).to be_a(ActiveModel::Errors) & be_empty }

    context "with messages provided" do
      let(:messages) do
        {
          nil => ["base1"],
          name: [{ text: "error1" }, "error2"]
        }
      end

      specify { expect(subject.errors).to be_present }
      specify { expect(subject.errors.messages).to eq(name: %w[error1 error2], base: ["base1"]) }
    end

    context "with codes provided" do
      let(:messages) do
        {
          nil => [{ text: "base1", code: :base1 }],
          name: [
            { text: "error1", code: :error1 },
            { text: "error2", code: :error2 }
          ]
        }
      end

      specify { expect(subject.errors).to be_present }
      specify { expect(subject.errors.messages).to eq(name: %w[error1 error2], base: ["base1"]) }
    end

    context "with unknown attributes" do
      let(:messages) { { unknown: ["error"] } }

      specify { expect(subject.errors).to be_blank }
      specify { expect(subject.errors.messages).to eq({}) }
    end

    context "with nested errors" do
      let(:messages) do
        {
          author: { title: ["error1"] },
          posts: { 0 => { text: ["error2"] } }
        }
      end

      it "nests the errors correctly" do
        expect(form.errors).to be_blank & have_attributes(messages: {})
        expect(form.author.errors).to be_present & have_attributes(messages: { title: ["error1"] })
        expect(form.posts.map(&:errors)).to match(
          [
            be_present & have_attributes(messages: { text: ["error2"] }),
            be_blank & have_attributes(messages: {})
          ]
        )
      end
    end

    context "with errors on nested objects" do
      let(:messages) do
        {
          author: [{ text: "error1" }],
          posts: ["error2"]
        }
      end

      it "assigns errors to the parent object" do
        expect(form.errors).to be_present & have_attributes(
          messages: {
            author: ["error1"],
            posts: ["error2"]
          }
        )
        expect(form.author.errors).to be_blank
        expect(form.posts.map(&:errors)).to match([be_blank, be_blank])
      end
    end

    context "when there is a mess in error messages" do
      let(:messages) do
        {
          posts: { 0 => { text: ["error2"] }, 1 => ["error3"], 2 => ["ignored"] }
        }
      end

      it "the messy message is ignored" do
        expect(form.errors).to be_present & have_attributes(messages: { "posts[1]": ["error3"] })
        expect(form.author.errors).to be_blank
        expect(form.posts.map(&:errors)).to match(
          [
            be_present & have_attributes(messages: { text: ["error2"] }),
            be_blank
          ]
        )
      end
    end
  end

  describe "#valid?" do
    it { is_expected.to be_valid }

    context "with messages provided" do
      let(:messages) { { name: ["should be present"] } }

      it { is_expected.not_to be_valid }
    end

    context "with unknown attributes" do
      let(:messages) { { unknown: ["error"] } }

      it { is_expected.to be_valid }
    end
  end
end
