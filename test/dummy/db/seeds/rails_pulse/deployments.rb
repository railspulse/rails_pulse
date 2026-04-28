module RailsPulse
  module Seeds
    module Deployments
      REVISIONS = %w[
        a1b2c3d e4f5g6h i7j8k9l m0n1o2p q3r4s5t u6v7w8x y9z0a1b c2d3e4f
      ].freeze

      def self.seed!(days_ago:)
        ::RailsPulse::Deployment.delete_all
        print "Generating deployments"

        # Spread deployments across the historical period — roughly every 1-3 days
        start_time = days_ago.days.ago
        current_time = Time.current

        # Generate one deployment per ~1.5 days on average
        deployment_count = [ (days_ago / 1.5).round, 2 ].max
        deployment_count = [ deployment_count, REVISIONS.size ].min

        # Space them out evenly with some jitter
        interval = (current_time - start_time) / deployment_count

        deployment_count.times do |i|
          started_at = if i == deployment_count - 1
            # Always place the last deployment within the default 24h view
            rand(2..8).hours.ago
          else
            base_time = start_time + (interval * i)
            jitter = rand(-2.hours.to_i..2.hours.to_i).seconds
            base_time + jitter
          end

          finished_at = started_at + rand(2..8).minutes
          ::RailsPulse::Deployment.create!(
            revision: REVISIONS[i],
            started_at: started_at,
            finished_at: finished_at,
            metadata: seed_metadata(i).to_json
          )
          print "."
        end

        puts " ✓ (#{deployment_count} deployments)"
        ::RailsPulse::Deployment.order(:started_at).to_a
      end

      private

      def self.seed_metadata(index)
        envs = %w[production production production staging]
        triggers = [ "github-actions", "manual", "github-actions", "github-actions", "heroku" ]
        {
          environment: envs[index % envs.size],
          triggered_by: triggers[index % triggers.size],
          branch: index.zero? ? "main" : [ "main", "release/v#{index}" ][index % 2]
        }
      end
    end
  end
end
