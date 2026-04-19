appraise "rails-7-2" do
  gem "rails", "~> 7.2.0"
end

appraise "rails-8-0" do
  gem "rails", "~> 8.0.0"
  # Ruby 3.3.x ships rdoc 7.1 as a default gem; Rails 8.x pulls in rdoc 7.2.
  # Pinning here forces Bundler to resolve a single version and silences the
  # "already initialized constant" warnings that appear when both are loaded.
  gem "rdoc", ">= 7.2"
end

appraise "rails-8-1" do
  gem "rails", "~> 8.1.0"
  # Ruby 3.3.x ships rdoc 7.1 as a default gem; Rails 8.x pulls in rdoc 7.2.
  # Pinning here forces Bundler to resolve a single version and silences the
  # "already initialized constant" warnings that appear when both are loaded.
  gem "rdoc", ">= 7.2"
end
