module RailsPulse
  module BreadcrumbsHelper
    def breadcrumbs
      # Get the engine's mount point by removing the leading slash and splitting
      mount_point = RailsPulse::Engine.routes.find_script_name({}).sub(/^\//, "")

      # Split the full path and remove empty segments
      path_segments = request.path.split("/").reject(&:empty?)

      # Find the index of the mount point in the path segments
      mount_point_index = path_segments.index(mount_point)

      # If we can't find the mount point or it's the last segment, return empty
      return [] if mount_point_index.nil? || mount_point_index == path_segments.length - 1

      # Only keep segments after the mount point
      path_segments = path_segments[(mount_point_index + 1)..-1]

      # Start with the Home link
      crumbs = [ {
        title: "Home",
        path: main_app.rails_pulse_path,
        current: path_segments.empty?
      } ]

      return crumbs if path_segments.empty?

      current_path = main_app.rails_pulse_path.chomp("/")

      path_segments.each_with_index do |segment, index|
        current_path += "/#{segment}"

        # Convert segment to a more readable format
        title = if segment =~ /^\d+$/
          # If it's a numeric ID, try to find a title from the resource
          resource_name = path_segments[index - 1]&.singularize
          # Look up the class in the RailsPulse namespace
          resource_class = "RailsPulse::#{resource_name&.classify}".safe_constantize
          if resource_class
            resource = resource_class.find(segment)
            # Try to_breadcrumb first, fall back to to_s
            resource.try(:to_breadcrumb) || resource.to_s
          else
            segment
          end
        else
          segment.titleize
        end

        is_last = index == path_segments.length - 1

        # For nested resources, if this is a collection name followed by an ID,
        # link to the parent resource's show page instead of the nested index
        breadcrumb_path = if !is_last &&
                            segment !~ /^\d+$/ &&
                            index > 0 &&
                            path_segments[index - 1] =~ /^\d+$/ &&
                            path_segments[index + 1] =~ /^\d+$/
          # This is a nested collection (e.g., /jobs/5/runs/291)
          # Link to parent show page (e.g., /jobs/5)
          path_segments[0..index-1].inject(main_app.rails_pulse_path.chomp("/")) { |path, seg| path + "/#{seg}" }
        else
          current_path
        end

        crumbs << {
          title: title,
          path: breadcrumb_path,
          current: is_last
        }
      end

      crumbs
    end
  end
end
