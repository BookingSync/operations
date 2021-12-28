# frozen_string_literal: true

require "rails_helper"

RSpec.describe Operation::Contract do
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
        backend: :i18n,
        top_namespace: :operations,
        namespace: "foo/bar"
      )
    end
  end

  describe ".find" do
    subject(:result) { contract.new.call(params, **context) }

    let(:contract) do
      Class.new(described_class) do
        params do
          optional(:rental_id).filled(:integer)
        end

        find :rental
      end
    end
    let!(:rental) { create(:rental) }
    let(:params) { { rental_id: rental.id } }
    let(:context) { {} }

    it "returns the requested rental" do
      expect(result.errors.to_h).to be_empty
      expect(result.context.each.to_h).to eq(rental: rental)
    end

    context "with non-existing id" do
      let(:params) { { rental_id: 0 } }

      it "returns not_found error" do
        expect(result.errors.to_h).to eq(rental_id: [{ code: :not_found, text: "Rental does not exist" }])
        expect(result.context.each.to_h).to eq(rental: nil)
      end
    end

    context "with invalid id" do
      let(:params) { { rental_id: "foobar" } }

      it "returns a validation error" do
        expect(result.errors.to_h).to eq(rental_id: ["must be an integer"])
        expect(result.context.each.to_h).to eq(rental: nil)
      end
    end

    context "with id not passed" do
      let(:params) { {} }

      it "returns missing error" do
        expect(result.errors.to_h).to eq(rental_id: [{ code: :key?, text: "is missing" }])
        expect(result.context.each.to_h).to eq(rental: nil)
      end
    end

    context "with only context given" do
      let(:params) { {} }
      let(:context) { { rental: rental } }

      it "returns no errors" do
        expect(result.errors.to_h).to be_empty
        expect(result.context.each.to_h).to eq(rental: rental)
      end

      context "when aggregate is requested" do
        subject(:result) { contract.new(rental_repository: rental_repository.new).call(params, **context) }

        let(:contract) do
          Class.new(described_class) do
            option :rental_repository

            params do
              optional(:rental_id).filled(:integer)
            end

            find :rental, aggregate: Struct.new(:entity)
          end
        end
        let(:rental_repository) do
          Class.new do
            def self.from_db(record)
              { id: record.id }
            end
          end
        end

        it "returns an entity and a wrapped entity" do
          expect(result.errors.to_h).to be_empty
          expect(result.context.each.to_h).to match(
            rental: { id: rental.id },
            rental_aggregate: have_attributes(entity: { id: rental.id })
          )
        end
      end
    end

    context "with `by:` given" do
      let(:contract) do
        Class.new(described_class) do
          params do
            optional(:name).filled(:string)
          end

          find :rental, by: :name
        end
      end
      let(:params) { { name: rental.name } }

      it "returns the rental by name" do
        expect(result.errors.to_h).to be_empty
        expect(result.context.each.to_h).to eq(rental: rental)
      end

      context "when record does not exist" do
        let(:params) { { name: "nonexistant" } }

        it "returns not_found error" do
          expect(result.errors.to_h).to eq(name: [{ code: :not_found, text: "Rental does not exist" }])
          expect(result.context.each.to_h).to eq(rental: nil)
        end
      end
    end

    context "with optional: true" do
      let(:contract) do
        Class.new(described_class) do
          params do
            optional(:rental_id).filled(:integer)
          end

          find :rental, optional: true
        end
      end

      it "returns the requested rental" do
        expect(result.errors.to_h).to be_empty
        expect(result.context.each.to_h).to eq(rental: rental)
      end

      context "with non-existing id" do
        let(:params) { { rental_id: 0 } }

        it "returns not_found error" do
          expect(result.errors.to_h).to eq(rental_id: [{ code: :not_found, text: "Rental does not exist" }])
          expect(result.context.each.to_h).to eq(rental: nil)
        end
      end

      context "with id not passed" do
        let(:params) { {} }

        it "returns no errors" do
          expect(result.errors.to_h).to be_empty
          expect(result.context.each.to_h).to eq(rental: nil)
        end
      end
    end
  end

  describe ".params" do
    describe "UUID type" do
      subject(:contract) do
        Class.new(described_class) do
          params do
            required(:param).filled(Types::UUID)
          end
        end
      end

      it "returns errors for invalid values" do
        expect(contract.new.call(param: nil).errors.to_h).to eq({ param: ["must be filled"] })
        expect(contract.new.call(param: 1).errors.to_h).to eq({ param: ["must be a string"] })
        expect(contract.new.call(param: "foobar").errors.to_h).to eq({ param: ["is in invalid format"] })
      end

      it "returns success for valid values" do
        expect(contract.new.call(param: SecureRandom.uuid)).to be_success
      end
    end

    describe "Params::Percentage type" do
      subject(:contract) do
        Class.new(described_class) do
          params do
            required(:param).filled(Types::Params::Percentage)
          end
        end
      end

      it "returns errors for invalid params" do
        expect(contract.new.call(param: nil).errors.to_h).to eq({ param: ["must be filled"] })
        expect(contract.new.call(param: "-1").errors.to_h).to eq({ param: ["must be greater than or equal to 0"] })
        expect(contract.new.call(param: "101").errors.to_h).to eq({ param: ["must be less than or equal to 100"] })
        expect(contract.new.call(param: "foobar").errors.to_h).to eq({ param: ["must be a decimal"] })
      end

      it "returns success for valid values" do
        expect(contract.new.call(param: "0")).to be_success
        expect(contract.new.call(param: 50)).to be_success
        expect(contract.new.call(param: BigDecimal("100"))).to be_success
      end
    end

    describe "Params::Money type" do
      subject(:contract) do
        Class.new(described_class) do
          params do
            required(:param).filled(Types::Params::Money)
          end
        end
      end

      it "returns errors for invalid params" do
        expect(contract.new.call(param: nil).errors.to_h).to eq({ param: ["must be filled"] })
        expect(contract.new.call(param: "foobar").errors.to_h).to eq({ param: ["must be Money"] })
      end

      it "returns success for valid values" do
        expect(contract.new.call(param: "-100")).to be_success
        expect(contract.new.call(param: 100)).to be_success
        expect(contract.new.call(param: Money.new(100, "EUR"))).to be_success
      end
    end

    describe "Params::Currency type" do
      subject(:contract) do
        Class.new(described_class) do
          params do
            required(:param).filled(Types::Params::Currency)
          end
        end
      end

      it "returns errors for invalid params" do
        expect(contract.new.call(param: nil).errors.to_h).to eq({ param: ["must be filled"] })
        expect(contract.new.call(param: 42).errors.to_h).to eq({ param: ["must be filled"] })
        expect(contract.new.call(param: "foobar").errors.to_h).to eq({ param: ["must be filled"] })
      end

      it "returns success for valid values" do
        expect(contract.new.call(param: "USD")).to be_success
        expect(contract.new.call(param: Money::Currency.new("EUR"))).to be_success
      end
    end
  end
end
