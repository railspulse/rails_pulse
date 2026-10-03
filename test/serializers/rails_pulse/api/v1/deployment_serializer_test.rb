require "test_helper"

module RailsPulse
  module Api
    module V1
      class DeploymentSerializerTest < ActiveSupport::TestCase
        setup do
          @deployment = RailsPulse::Deployment.create!(
            revision: "0123456789abcdef", started_at: 2.hours.ago, finished_at: 2.hours.ago + 75.5,
            metadata: { "branch" => "main" }.to_json
          )
        end

        test "serializes deployment fields" do
          result = DeploymentSerializer.serialize(@deployment)

          assert_equal @deployment.id, result[:id]
          assert_equal "0123456789abcdef", result[:revision]
          assert_equal "0123456789ab", result[:short_revision]
          assert_in_delta 75.5, result[:duration_seconds]
          assert_not result[:in_progress]
          assert_equal({ "branch" => "main" }, result[:metadata])
        end

        test "returns a hash with exactly the expected keys" do
          result = DeploymentSerializer.serialize(@deployment)

          assert_equal %i[id revision short_revision started_at finished_at duration_seconds in_progress metadata comparison], result.keys
        end

        test "includes the comparison it is given" do
          comparison = { outcome: "clean" }
          result = DeploymentSerializer.serialize(@deployment, comparison: comparison)

          assert_equal comparison, result[:comparison]
        end

        test "serializes an in-progress deployment" do
          @deployment.update!(finished_at: nil)
          result = DeploymentSerializer.serialize(@deployment)

          assert result[:in_progress]
          assert_nil result[:duration_seconds]
        end
      end
    end
  end
end
