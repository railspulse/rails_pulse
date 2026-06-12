module SeedHelpers
  def self.percentile(values, fraction)
    return nil if values.empty?

    index = (fraction * (values.length - 1)).floor
    fraction_part = (fraction * (values.length - 1)) - index

    return values[index] if fraction_part.zero? || index + 1 >= values.length

    values[index] + (values[index + 1] - values[index]) * fraction_part
  end

  def self.stddev(values, mean)
    return nil if values.length < 2 || mean.nil?

    sum_of_squares = values.sum { |value| (value - mean) ** 2 }
    Math.sqrt(sum_of_squares / (values.length - 1))
  end

  def self.controller_action_for(route)
    return route.controller_action if route.controller_action.present?

    # Fallback for routes without a stored controller_action (e.g. long/unrecognized paths).
    # Uses lowercase "controller#action" format consistent with path_params derivation.
    parts = route.path.split("/").reject { |p| p.empty? || p.start_with?(":") }
    controller = (parts.last || "home").downcase
    action = case route.http_methods_list.first
    when "GET"    then route.path.include?(":") ? "show" : "index"
    when "POST"   then "create"
    when "PUT", "PATCH" then "update"
    when "DELETE" then "destroy"
    else "index"
    end
    "#{controller}##{action}"
  end
end
