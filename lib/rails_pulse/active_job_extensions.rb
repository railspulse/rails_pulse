module RailsPulse
  module ActiveJobExtensions
    extend ActiveSupport::Concern

    included do
      around_perform do |job, block|
        RailsPulse::JobRunCollector.track(job) do
          block.call
        end
      end
    end
  end
end
