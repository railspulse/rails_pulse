module DeploymentMarkersConcern
  def populate_deployment_markers
    @deployment_markers = RailsPulse::Deployment
      .for_range(Time.zone.at(@start_time), Time.zone.at(@end_time))
      .map(&:to_chart_marker)
  end
end
