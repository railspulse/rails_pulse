namespace :rails_pulse do
  desc "Copy pre-built dashboard assets into public/assets without running the host JS compressor"
  task install_assets: :environment do
    entries = RailsPulse::PackagedAssets.install!
    puts "[RailsPulse] Installed #{entries.size} dashboard assets into public/assets"
  end
end

# Copy after the host pipeline finishes so asset_sync / CDN uploads include
# the files, but never register them for Sprockets compression (#190).
if Rake::Task.task_defined?("assets:precompile")
  Rake::Task["assets:precompile"].enhance do
    Rake::Task["rails_pulse:install_assets"].invoke
  end
end
