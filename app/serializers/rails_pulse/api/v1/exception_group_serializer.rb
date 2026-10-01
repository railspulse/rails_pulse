module RailsPulse
  module Api
    module V1
      class ExceptionGroupSerializer
        def self.serialize(group)
          {
            id:               group.id,
            fingerprint:      group.fingerprint,
            exception_class:  group.exception_class,
            location:         group.location,
            message:          group.message,
            status:           group.status,
            occurrence_count: group.occurrence_count,
            first_seen_at:    group.first_seen_at,
            last_seen_at:     group.last_seen_at,
            resolved_at:      group.resolved_at,
            preserve:         group.preserve
          }
        end
      end
    end
  end
end
