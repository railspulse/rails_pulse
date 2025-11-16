class TestJob < ApplicationJob
  queue_as :default

  def perform(value)
    User.create!(email: "job-#{value}@example.com", name: "Test User #{value}")
  end
end
