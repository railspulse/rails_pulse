module RailsPulse
  module DetailCaptureHelper
    # The panel info (see components/_panel) for a panel built from
    # individual requests while store_full_details names a threshold: those rows are the
    # captured subset, but every aggregate still counts all traffic
    # (decision 0022). nil while store_full_details is :all.
    #
    # subject is the route or query the page is about, or nil for all requests.
    def detail_capture_info(text, subject: nil)
      return unless RailsPulse.configuration.detail_capture_settings

      rate = DetailCaptureRate.for(subject)
      lines = [ text, detail_capture_rate_sentence(rate, subject) ]
      lines << detail_capture_retune_sentence if detail_capture_rate_high?(rate, subject)

      { heading: "Full details", lines: lines.compact }
    end

    private

    # Only the overall share says the settings need retuning: a route that is
    # always slow is meant to be captured in full.
    def detail_capture_rate_high?(rate, subject = nil)
      subject.nil? && rate.present? && rate.high?
    end

    def detail_capture_retune_sentence
      advice = DetailCaptureRate.retune_advice(RailsPulse.configuration.detail_capture_settings)
      "That's over a quarter of them, so little storage is saved. To store less, #{advice}."
    end

    def detail_capture_rate_sentence(rate, subject)
      return unless rate

      noun = case subject
      when Route then "of this route's requests"
      when Query then "of this query's executions"
      else "of all requests"
      end
      "Captured in the last day: #{rate.share_label} #{noun}."
    end
  end
end
