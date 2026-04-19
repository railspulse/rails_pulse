module RailsPulse
  module Suggestions
    class Base
      attr_reader :operation, :parent

      def initialize(operation, parent = nil)
        @operation = operation
        @parent = parent
      end

      def generate
        raise NotImplementedError, "#{self.class.name} must implement #generate method"
      end

      private

      def build_suggestion(type:, icon:, title:, description:, priority:)
        {
          type: type,
          icon: icon,
          title: title,
          description: description,
          priority: priority
        }
      end
    end
  end
end
