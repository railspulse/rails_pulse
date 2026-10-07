module RailsPulse
  module Cloud
    # Items for exception groups and deployments, the two records Cloud
    # keeps whole rather than as hourly numbers. Each is sent when it
    # changes: a group when its status or counts move, a deployment when it
    # is recorded or finished.
    module RecordItems
      # Larger metadata is replaced rather than cut, so Cloud never shows a
      # half of what the deploy script recorded.
      METADATA_LIMIT = 4.kilobytes
      TRUNCATED = { "truncated" => true }.freeze

      module_function

      # Items for the groups whose rows changed inside `window`.
      def exception_groups_updated(window)
        ExceptionGroup.where(updated_at: window).order(:id).map { |record| exception_group(record) }
      end

      # Items for the deployments recorded or finished inside `window`.
      def deployments_updated(window)
        Deployment.where(updated_at: window).order(:started_at, :id).map { |record| deployment(record) }
      end

      # The message is never sent: it is built from runtime values and can
      # carry anything a user typed.
      def exception_group(group)
        {
          type: "exception_group",
          fingerprint: group.fingerprint,
          exception_class: group.exception_class,
          location: group.location,
          status: group.status,
          first_seen_at: group.first_seen_at&.utc&.iso8601,
          last_seen_at: group.last_seen_at&.utc&.iso8601,
          resolved_at: group.resolved_at&.utc&.iso8601,
          occurrence_count: group.occurrence_count.to_i
        }
      end

      # Metadata is sent as recorded: the deploy script decides what goes in
      # it, and the preview task says so.
      def deployment(deployment)
        {
          type: "deployment",
          revision: deployment.revision,
          started_at: deployment.started_at.utc.iso8601,
          finished_at: deployment.finished_at&.utc&.iso8601,
          metadata: metadata(deployment.metadata_hash)
        }
      end

      def metadata(value)
        return {} unless value.is_a?(Hash)

        value.to_json.bytesize > METADATA_LIMIT ? TRUNCATED : value
      end
    end
  end
end
