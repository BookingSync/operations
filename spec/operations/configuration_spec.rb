# frozen_string_literal: true

RSpec.describe Operations::Configuration do
  subject(:configuration) { Operations::Configuration.new(options) }

  let(:error_reporter) { ->() {} }
  let(:transaction) { ->() {} }
  let(:options) { { error_reporter: error_reporter, transaction: transaction } }

  describe '#to_h' do
    subject(:to_h) { configuration.to_h }

    it { is_expected.to eq(error_reporter: error_reporter, transaction: transaction) }
  end
end
