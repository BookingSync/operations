# frozen_string_literal: true

RSpec.describe Operations::Form do
  subject(:form) { described_class.new(key_map_source, **options) }

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
  let(:key_map_source) { contract }
  let(:options) do
    {
      model_map: proc { |_path| "DummyModel" },
      hydrator: proc { |_form_class, _params, **_context| { id: 42, name: "Batman" } }
    }
  end

  describe "#call" do
    subject(:call) { form.call(operation_result) }

    let(:operation) do
      Operations::Command.new(
        ->(_, **) { Dry::Monads::Success({}) },
        contract: contract,
        policy: nil
      )
    end
    let(:operation_result) { operation.call(params) }
    let(:params) { {} }

    specify do
      expect(call).to be_a(Operations::Form::Base) & have_attributes(
        entities: [],
        name: "Batman",
        attributes: { entities: [], name: "Batman" }
      )
      expect(call.errors.to_hash).to eq({ entities: ["is missing"] })
    end

    context "when params are given" do
      let(:params) { { entities: [{ id: 42 }], name: "Superman" } }

      specify do
        expect(call).to be_a(Operations::Form::Base) & have_attributes(
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

  describe "#as_json" do
    subject(:as_json) { form.as_json }

    specify do
      expect(as_json).to match({
        "key_map" => [
          include("coercer" => {}, "id" => "entities", "name" => "entities", "member" => [
            include("coercer" => {}, "id" => "id", "name" => "id")
          ]),
          include("coercer" => {}, "id" => "name", "name" => "name")
        ],
        "model_map" => "Proc",
        "hydrator" => "Proc",
        "base_class" => "Operations::Form::Base"
      })
    end
  end

  describe "#pretty_print" do
    subject(:pretty_inspect) { form.pretty_inspect }

    specify do
      expect(pretty_inspect.gsub(%r{Proc:0x[^>]+}, "Proc:0x")).to eq(<<~INSPECT)
        #<Operations::Form
         key_map=#<Dry::Schema::KeyMap[[:entities, [:id]], :name]>,
         model_map=#<Proc:0x>,
         hydrator=#<Proc:0x>,
         base_class=#<Class attributes={}>,
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
