module RailsPulse
  module ApplicationHelper
    include Pagy::Frontend
    include BreadcrumbsHelper
    include ChartHelper
    include StatusHelper
    include FormattingHelper
  end
end
