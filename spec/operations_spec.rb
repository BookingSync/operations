# frozen_string_literal: true

RSpec.describe Operations do
  it "has a version number" do
    expect(Operations::VERSION).not_to be_nil
  end

  describe "#default_config" do
    it "returns the default default_config values by default" do
      expect(described_class.default_config).to have_attributes(
        error_reporter: Operations::DEFAULT_ERROR_REPORTER,
        transaction: Operations::DEFAULT_TRANSACTION
      )
    end
  end
end
