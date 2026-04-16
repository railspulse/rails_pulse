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
    parts = route.path.split("/").reject { |p| p.empty? || p.start_with?(":") }
    controller_name = (parts.last || "home").split("_").map(&:capitalize).join
    action = case route.method
             when "GET"    then route.path.include?(":id") ? "show" : "index"
             when "POST"   then "create"
             when "PUT", "PATCH" then "update"
             when "DELETE" then "destroy"
             else "index"
             end
    "#{controller_name}Controller##{action}"
  end
end
