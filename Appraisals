# frozen_string_literal: true

%w[7.1 7.2 8.0].each do |version|
  appraise "rails.#{version}" do
    gem "activerecord", "~> #{version}.0"
    gem "activesupport", "~> #{version}.0"
    gem "sqlite3", "~> 2.1"
  end
end
