module RailsPulse
  # Finds the deployment a regression most plausibly belongs to.
  #
  # Deliberately derived at read time rather than stored on the finding. A
  # deployment is often recorded by CI moments after the code is live, and
  # sometimes late or retroactively; correlating on read means a deployment
  # recorded after detection still lines up, where a column written once would
  # be permanently wrong. The inputs — the change point and the deployment
  # timeline — are both already persisted, so nothing is lost by deriving it.
  #
  # This states adjacency, not causation. A deployment shortly before a
  # regression is worth looking at; it is not proof, and the UI should not
  # phrase it as one.
  class DeploymentCorrelator
    # How far before a change point a deployment can sit and still be considered
    # related. Wide enough to absorb the lag between deploying and the metric
    # moving, narrow enough that an unrelated deploy days earlier is not blamed.
    DEFAULT_WINDOW = 6.hours

    # A day-granularity change point could be anywhere in that day, so a
    # deployment slightly after midnight on the identified day is still a
    # candidate.
    DAY_GRANULARITY_LOOKAHEAD = 1.day

    def self.for(finding, window: DEFAULT_WINDOW)
      new(finding, window: window).call
    end

    # Correlates a batch in one query rather than one per finding, for the index.
    #
    # @return [Hash{Integer => RailsPulse::Deployment}] keyed by finding id
    def self.for_all(findings, window: DEFAULT_WINDOW)
      findings = findings.select(&:change_point_known?)
      return {} if findings.empty?

      earliest = findings.map(&:changed_at).min - window
      latest   = findings.map(&:changed_at).max + DAY_GRANULARITY_LOOKAHEAD

      deployments = RailsPulse::Deployment
        .where(started_at: earliest..latest)
        .order(started_at: :asc)
        .to_a

      findings.each_with_object({}) do |finding, correlated|
        match = new(finding, window: window, deployments: deployments).call
        correlated[finding.id] = match if match
      end
    end

    def initialize(finding, window: DEFAULT_WINDOW, deployments: nil)
      @finding     = finding
      @window      = window
      @deployments = deployments
    end

    def call
      return nil unless finding.change_point_known?

      candidates.max_by(&:started_at)
    end

    private

    attr_reader :finding, :window, :deployments

    def candidates
      range = search_range

      if deployments
        deployments.select { |deployment| range.cover?(deployment.started_at) }
      else
        RailsPulse::Deployment.where(started_at: range).to_a
      end
    end

    # An hourly change point is accurate, so only look backwards. A daily one
    # only identifies the day, so a deployment anywhere in that day qualifies.
    def search_range
      changed_at = finding.changed_at

      if finding.hourly_change_point?
        (changed_at - window)..changed_at
      else
        (changed_at - window)..(changed_at + DAY_GRANULARITY_LOOKAHEAD)
      end
    end
  end
end
