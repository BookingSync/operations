# frozen_string_literal: true

RSpec.describe Operations::Form::Builder do
  shared_examples "a form builder" do |base_class:|
    subject(:form_builder) { described_class.new(base_class: base_class) }

    describe "#build" do
      subject(:form_class) do
        form_builder.build(
          key_map: schema.key_map,
          model_map: model_map,
          **options
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
      let(:model_map_hash) { { ["name"] => "Dummy1", ["translations", %r{singular|plural}] => "Dummy2" } }
      let(:model_map) { Operations::Form::DeprecatedLegacyModelMapImplementation.new(model_map_hash) }

      context "with param_key" do
        let(:options) { { param_key: "my_form" } }

        it "defines attributes tree correctly" do
          expect(form_class).to have_attributes(
            name: nil,
            model_name: "my_form",
            attributes: {
              name: have_attributes(collection: false, form: nil, model_name: "Dummy1"),
              posts: have_attributes(
                collection: true,
                form: have_attributes(
                  name: nil,
                  model_name: "posts",
                  attributes: {
                    tags: have_attributes(collection: false, form: nil, model_name: nil),
                    title: have_attributes(collection: false, form: nil, model_name: nil)
                  }
                ),
                model_name: nil
              ),
              translations: have_attributes(
                collection: false,
                form: have_attributes(
                  name: nil,
                  model_name: "translation",
                  attributes: {
                    version: have_attributes(collection: false, form: nil, model_name: nil),
                    singular: have_attributes(
                      collection: false,
                      form: have_attributes(
                        name: nil,
                        model_name: "singular",
                        attributes: { text: have_attributes(collection: false, form: nil, model_name: nil) }
                      ),
                      model_name: "Dummy2"
                    ),
                    plural: have_attributes(
                      collection: true,
                      form: have_attributes(
                        name: nil,
                        model_name: "plural",
                        attributes: { text: have_attributes(collection: false, form: nil, model_name: nil) }
                      ),
                      model_name: "Dummy2"
                    ),
                    en: have_attributes(
                      collection: false,
                      form: have_attributes(
                        name: nil,
                        model_name: "en",
                        attributes: { text: have_attributes(collection: false, form: nil, model_name: nil) }
                      ),
                      model_name: nil
                    ),
                    "zh-CN": have_attributes(
                      collection: false,
                      form: have_attributes(
                        name: nil,
                        model_name: "zh-CN",
                        attributes: { text: have_attributes(collection: false, form: nil, model_name: nil) }
                      ),
                      model_name: nil
                    )
                  }
                ),
                model_name: nil
              )
            }
          )
          expect(form_class.attributes[:translations].form.instance_methods(false))
            .to include(:singular_attributes=, :plural_attributes=)
        end

        context "when called twice with the same params" do
          let(:form1) { form_class }
          let(:form2) do
            form_builder.build(
              key_map: schema.key_map,
              model_map: model_map,
              **options
            )
          end

          it "does not return the same class" do
            expect(form1).not_to equal(form2)
          end
        end
      end

      context "with namespace and class_name" do
        let(:options) { { namespace: namespace, class_name: "MyForm" } }
        let(:namespace) { stub_const("DummyNamespace", Module.new) }

        it "defines attributes tree correctly" do
          expect(form_class).to have_attributes(
            name: "DummyNamespace::MyForm",
            model_name: "DummyNamespace::MyForm",
            attributes: {
              name: have_attributes(collection: false, form: nil, model_name: "Dummy1"),
              posts: have_attributes(collection: true, form: DummyNamespace::MyForm::Post, model_name: nil),
              translations: have_attributes(collection: false,
                form: DummyNamespace::MyForm::Translations, model_name: nil)
            }
          )
          expect(DummyNamespace::MyForm::Post).to have_attributes(
            name: "DummyNamespace::MyForm::Post",
            model_name: "DummyNamespace::MyForm::Post",
            attributes: {
              tags: have_attributes(collection: false, form: nil, model_name: nil),
              title: have_attributes(collection: false, form: nil, model_name: nil)
            }
          )
          expect(DummyNamespace::MyForm::Translations).to have_attributes(
            name: "DummyNamespace::MyForm::Translations",
            model_name: "DummyNamespace::MyForm::Translations",
            attributes: {
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
            }
          )
          expect(DummyNamespace::MyForm::Translations.instance_methods(false))
            .to include(:singular_attributes=, :plural_attributes=)
          expect(DummyNamespace::MyForm::Translations::Singular).to have_attributes(
            name: "DummyNamespace::MyForm::Translations::Singular",
            model_name: "DummyNamespace::MyForm::Translations::Singular",
            attributes: { text: have_attributes(collection: false, form: nil, model_name: nil) }
          )
          expect(DummyNamespace::MyForm::Translations::Plural).to have_attributes(
            name: "DummyNamespace::MyForm::Translations::Plural",
            model_name: "DummyNamespace::MyForm::Translations::Plural",
            attributes: { text: have_attributes(collection: false, form: nil, model_name: nil) }
          )
          expect(DummyNamespace::MyForm::Translations::En).to have_attributes(
            name: "DummyNamespace::MyForm::Translations::En",
            model_name: "DummyNamespace::MyForm::Translations::En",
            attributes: { text: have_attributes(collection: false, form: nil, model_name: nil) }
          )
          expect(DummyNamespace::MyForm::Translations::ZhCn).to have_attributes(
            name: "DummyNamespace::MyForm::Translations::ZhCn",
            model_name: "DummyNamespace::MyForm::Translations::ZhCn",
            attributes: { text: have_attributes(collection: false, form: nil, model_name: nil) }
          )
        end

        context "when called twice with the same params" do
          let(:form1) { form_class }
          let(:form2) do
            form_builder.build(
              key_map: schema.key_map,
              model_map: model_map,
              **options
            )
          end

          it "does not redefine the constant" do
            expect(form1).to equal(form2)
          end
        end
      end
    end
  end

  it_behaves_like "a form builder", base_class: Operations::Form::Base
  it_behaves_like "a form builder", base_class: Operations::Form
end
