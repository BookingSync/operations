# frozen_string_literal: true

%w[5.2 6.0 6.1 7.0 7.1 7.2 8.0].each do |version|
  appraise "rails.#{version}" do
    gem "activerecord", "~> #{version}.0"
    gem "activesupport", "~> #{version}.0"
    gem "sqlite3", version > "7.0" ? "~> 2.1" : "~> 1.4"
  end
end
