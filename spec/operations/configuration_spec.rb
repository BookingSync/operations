# frozen_string_literal: true

RSpec.describe Operations::Configuration do
  subject(:configuration) { described_class.new(**options) }

  let(:error_reporter) { -> {} }
  let(:transaction) { -> {} }
  let(:after_commit) { -> {} }
  let(:options) { { error_reporter: error_reporter, transaction: transaction, after_commit: after_commit } }

  describe "#to_h" do
    subject(:to_h) { configuration.to_h }

    it { is_expected.to eq(error_reporter: error_reporter, transaction: transaction, after_commit: after_commit) }
  end
end
