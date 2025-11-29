# frozen_string_literal: true

%w[7.2 8.0 8.1].each do |version|
  appraise "rails.#{version}" do
    gem "activerecord", "~> #{version}.0"
    gem "activesupport", "~> #{version}.0"
  end
end
