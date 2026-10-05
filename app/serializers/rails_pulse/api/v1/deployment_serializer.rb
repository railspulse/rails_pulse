module RailsPulse
  module Api
    module V1
      class DeploymentSerializer
        # `comparison` is the deployment's DeploymentComparison, computed by
        # the caller so a page of deployments is compared in one query.
        def self.serialize(deployment, comparison: nil)
          {
            id:               deployment.id,
            revision:         deployment.revision,
            short_revision:   deployment.short_revision,
            started_at:       deployment.started_at,
            finished_at:      deployment.finished_at,
            duration_seconds: deployment.duration&.round(1),
            in_progress:      deployment.in_progress?,
            metadata:         deployment.metadata_hash,
            comparison:       comparison
          }
        end
      end
    end
  end
end
