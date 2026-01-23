require "ostruct"

module RailsPulse
  module Adapters
    class JobWrapper
      attr_reader :job_id, :queue_name, :arguments, :enqueued_at, :executions

      def initialize(job_id:, class_name:, queue_name:, arguments:, enqueued_at:, executions:)
        @job_id = job_id
        @class_name = class_name
        @queue_name = queue_name
        @arguments = arguments
        @enqueued_at = enqueued_at
        @executions = executions
      end

      def class
        OpenStruct.new(name: @class_name)
      end
    end
  end
end
