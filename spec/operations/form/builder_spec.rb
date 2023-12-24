# frozen_string_literal: true

RSpec.describe Operations::Form::Builder do
  shared_examples "a form builder" do |base_class:|
    subject(:form_builder) { described_class.new(base_class: base_class) }

    describe "#build" do
      subject(:form_class) do
        form_builder.build(
          key_map: schema.key_map,
          namespace: namespace,
          class_name: "MyForm",
          model_map: model_map
        )
      end

      let(:schema) do
        Dry::Schema.Params do
          required(:name).filled(:string)
          optional(:posts).array(:hash) do
            required(:title).filled(:string)
            required(:tags).array(:string)
          end
          required(:translations).hash do
            required(:version).filled(:integer)
            required(:singular_attributes).hash do
              required(:text).filled(:string)
            end
            required(:plural_attributes).hash do
              required(:"0").hash do
                required(:text).filled(:string)
              end
              required(:"1").hash do
                required(:text).filled(:string)
              end
            end
            required(:en).hash do
              required(:text).filled(:string)
            end
            optional(:"zh-CN").hash do
              required(:text).filled(:string)
            end
          end
        end
      end
      let(:namespace) { stub_const("DummyNamespace", Module.new) }
      let(:model_map) { { ["name"] => "Dummy1", ["translations", %r{singular|plural}] => "Dummy2" } }

      it "defines attributes tree correctly" do
        expect(form_class).to be < base_class
        expect(form_class.name).to eq("DummyNamespace::MyForm")
        expect(form_class.attributes).to match(
          name: have_attributes(collection: false, form: nil, model_name: "Dummy1"),
          posts: have_attributes(collection: true, form: DummyNamespace::MyForm::Post, model_name: nil),
          translations: have_attributes(collection: false, form: DummyNamespace::MyForm::Translations, model_name: nil)
        )
        expect(DummyNamespace::MyForm::Post.attributes).to match(
          tags: have_attributes(collection: false, form: nil, model_name: nil),
          title: have_attributes(collection: false, form: nil, model_name: nil)
        )
        expect(DummyNamespace::MyForm::Translations.attributes).to match(
          version: have_attributes(collection: false, form: nil, model_name: nil),
          singular: have_attributes(
            collection: false,
            form: DummyNamespace::MyForm::Translations::Singular,
            model_name: "Dummy2"
          ),
          plural: have_attributes(
            collection: true,
            form: DummyNamespace::MyForm::Translations::Plural,
            model_name: "Dummy2"
          ),
          en: have_attributes(
            collection: false,
            form: DummyNamespace::MyForm::Translations::En,
            model_name: nil
          ),
          "zh-CN": have_attributes(
            collection: false,
            form: DummyNamespace::MyForm::Translations::ZhCn,
            model_name: nil
          )
        )
        expect(DummyNamespace::MyForm::Translations.instance_methods(false))
          .to include(:singular_attributes=, :plural_attributes=)
        expect(DummyNamespace::MyForm::Translations::Singular.attributes).to match(
          text: have_attributes(collection: false, form: nil, model_name: nil)
        )
        expect(DummyNamespace::MyForm::Translations::Plural.attributes).to match(
          text: have_attributes(collection: false, form: nil, model_name: nil)
        )
        expect(DummyNamespace::MyForm::Translations::En.attributes).to match(
          text: have_attributes(collection: false, form: nil, model_name: nil)
        )
        expect(DummyNamespace::MyForm::Translations::ZhCn.attributes).to match(
          text: have_attributes(collection: false, form: nil, model_name: nil)
        )
      end

      context "when called twice with the same params" do
        let(:form1) { form_class }
        let(:form2) do
          form_builder.build(
            key_map: schema.key_map,
            namespace: namespace,
            class_name: "MyForm",
            model_map: {}
          )
        end

        it "does not redefine the constant" do
          expect(form1).to equal(form2)
        end
      end
    end
  end

  it_behaves_like "a form builder", base_class: Operations::Form::Base
  it_behaves_like "a form builder", base_class: Operations::Form
end
