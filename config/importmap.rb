pin "application", to: "rails_pulse/application.js"

# echarts is a dependency of the rails_charts gem
pin "echarts", to: "echarts.min.js"
# pin "echarts/theme/inspired", to: "echarts/theme/inspired.js"
pin "rails_pulse/theme", to: "rails_pulse/theme.js"

pin "@hotwired/turbo-rails", to: "turbo.min.js", preload: true

# pin "@hotwired/stimulus", to: "https://unpkg.com/@hotwired/stimulus/dist/stimulus.js"
pin "@hotwired/stimulus", to: "https://cdn.jsdelivr.net/npm/@hotwired/stimulus@3.2.2/dist/stimulus.js"
pin_all_from File.expand_path("../app/javascript/rails_pulse", __dir__), under: "rails_pulse"
