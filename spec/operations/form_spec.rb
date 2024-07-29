# frozen_string_literal: true

RSpec.describe Operations::Form do
  subject(:form) { described_class.new(command, **options) }

  let(:contract) do
    Operations::Contract.build do
      schema do
        required(:entities).array(:hash) do
          required(:id).filled(:integer)
        end
        optional(:name).filled(:string)
      end
    end
  end
  let(:operation) do
    Class.new do
      def call(_, **)
        Dry::Monads::Success({})
      end
    end
  end
  let(:command) do
    Operations::Command.new(
      operation.new,
      contract: contract,
      policy: nil
    )
  end
  let(:default_options) do
    {
      model_map: proc { |_path| "DummyModel" },
      hydrator: proc { |_form_class, params, **_context| { ignored: 42, name: "Batman" }.merge(params) }
    }
  end
  let(:options) { default_options }

  before do
    stub_const("DummyOperation", operation)
  end

  describe "#build" do
    subject(:build) { form.build(params, **context) }

    let(:params) { {} }
    let(:context) { {} }

    specify do
      expect(build).to be_a(Operations::Form::Base) & have_attributes(
        entities: [],
        name: "Batman",
        attributes: { entities: [], name: "Batman" }
      )
      expect(build.errors.to_hash).to be_empty
    end

    context "when model_map and hydrator are missing but persisted is false" do
      let(:options) { { persisted: false } }

      specify do
        expect(build).to be_a(Operations::Form::Base) & have_attributes(
          persisted?: false,
          entities: [],
          name: nil,
          attributes: { entities: [], name: nil }
        )
        expect(build.errors.to_hash).to be_empty
      end
    end

    context "when params are given" do
      let(:params) do
        double(to_unsafe_hash: {
          entities: [{ "id" => 42 }], "dummy_operation_form" => { name: "Superman" }
        })
      end

      specify do
        expect(build).to be_a(Operations::Form::Base) & have_attributes(
          persisted?: true,
          entities: [be_a(Operations::Form::Base) & have_attributes(
            id: 42,
            attributes: { id: 42 },
            errors: be_empty
          )],
          name: "Superman",
          attributes: {
            entities: [be_a(Operations::Form::Base) & have_attributes(
              id: 42,
              attributes: { id: 42 },
              errors: be_empty
            )],
            name: "Superman"
          },
          errors: be_empty
        )
      end
    end
  end

  describe "#persist" do
    subject(:persist) { form.persist(params, **context) }

    let(:params) { {} }
    let(:context) { {} }
    let(:options) do
      default_options.merge(
        model_name: "dummy_form",
        params_transformations: lambda { |_form_class, params, **_context|
          params.transform_keys { |key| key == :alias_name ? :name : key }
        }
      )
    end

    specify do
      expect(persist).to be_a(Operations::Form::Base) & have_attributes(
        entities: [],
        name: "Batman",
        attributes: { entities: [], name: "Batman" }
      )
      expect(persist.errors.to_hash).to eq({ entities: ["is missing"] })
    end

    context "when model_map and hydrator are missing but persisted is false" do
      let(:options) { { persisted: false } }

      specify do
        expect(persist).to be_a(Operations::Form::Base) & have_attributes(
          persisted?: false,
          entities: [],
          name: nil,
          attributes: { entities: [], name: nil }
        )
        expect(persist.errors.to_hash).to eq({ entities: ["is missing"] })
      end
    end

    context "when params are given" do
      let(:params) { { entities: [{ "id" => 42 }], "dummy_form" => { alias_name: "Superman" } } }

      specify do
        expect(persist).to be_a(Operations::Form::Base) & have_attributes(
          persisted?: true,
          entities: [be_a(Operations::Form::Base) & have_attributes(
            id: 42,
            attributes: { id: 42 },
            errors: be_empty
          )],
          name: "Superman",
          attributes: {
            entities: [be_a(Operations::Form::Base) & have_attributes(
              id: 42,
              attributes: { id: 42 },
              errors: be_empty
            )],
            name: "Superman"
          },
          errors: be_empty
        )
      end
    end
  end

  describe "#pretty_print" do
    subject(:pretty_inspect) { form.pretty_inspect }

    specify do
      expect(pretty_inspect.gsub(%r{Proc:0x[^>]+}, "Proc:0x")).to eq(<<~INSPECT)
        #<Operations::Form
         model_name="dummy_operation_form",
         model_map=#<Proc:0x>,
         persisted=true,
         params_transformations=[],
         hydrator=#<Proc:0x>,
         form_class=#<Class
           attributes={:entities=>
              #<Operations::Form::Attribute
               name=:entities,
               collection=true,
               model_name="DummyModel",
               form=#<Class
                 attributes={:id=>
                    #<Operations::Form::Attribute
                     name=:id,
                     collection=false,
                     model_name="DummyModel",
                     form=nil>}>>,
             :name=>
              #<Operations::Form::Attribute
               name=:name,
               collection=false,
               model_name="DummyModel",
               form=nil>}>>
      INSPECT
    end
  end
end
