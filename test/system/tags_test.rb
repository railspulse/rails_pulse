require "test_helper"

class TagsTest < ApplicationSystemTestCase
  def setup
    super
    @job = rails_pulse_jobs(:mailer_job)

    # Configure tags for testing
    @original_tags = RailsPulse.configuration.tags
    RailsPulse.configure do |config|
      config.tags = [ "critical", "monitoring", "scheduled" ]
    end
  end

  def teardown
    # Restore the dummy app's configured tags
    RailsPulse.configure do |config|
      config.tags = @original_tags
    end
    super
  end

  test "can add and remove tags" do
    visit_rails_pulse_path "/jobs/#{@job.id}"

    # Wait for page to load
    assert_selector ".tag-manager", wait: 5

    # === Add a tag ===
    # Click the "tag +" button to open the tag menu
    find(".tag-add-button", text: "tag +").click

    # Wait for popover menu to appear
    assert_selector ".popover", visible: true, wait: 3

    # Click on "Critical" tag in the menu
    within(".menu") do
      click_button "Critical"
    end

    # Brief pause to allow full page redirect to complete
    sleep 0.1

    # Verify tag was added and appears in the tag list
    assert_selector ".badge", text: "Critical", wait: 5

    # === Remove the tag ===
    # Find and click the remove button (X) on the tag
    within(".tag-list") do
      # The tag badge should have a remove button with class "tag-remove"
      tag_badge = find(".badge", text: "Critical")
      within(tag_badge) do
        find("button.tag-remove").click
      end
    end

    # Brief pause to allow full page redirect to complete
    sleep 0.1

    # Verify tag was removed
    assert_no_selector ".badge", text: "Critical", wait: 5

    # === Add multiple tags ===
    # Click the "tag +" button again
    find(".tag-add-button", text: "tag +").click

    assert_selector ".popover", visible: true, wait: 3

    within(".menu") do
      click_button "Monitoring"
    end

    # Brief pause to allow full page redirect to complete
    sleep 0.1

    assert_selector ".badge", text: "Monitoring", wait: 5

    # Add another tag
    find(".tag-add-button", text: "tag +").click

    assert_selector ".popover", visible: true, wait: 3

    within(".menu") do
      click_button "Scheduled"
    end

    # Brief pause to allow full page redirect to complete
    sleep 0.1

    # Verify both tags are present
    assert_selector ".badge", text: "Monitoring", wait: 5
    assert_selector ".badge", text: "Scheduled"

    # === Remove one of the tags ===
    within(".tag-list") do
      tag_badge = find(".badge", text: "Monitoring")
      within(tag_badge) do
        find("button.tag-remove").click
      end
    end

    # Brief pause to allow full page redirect to complete
    sleep 0.1

    # Verify only one tag remains
    assert_no_selector ".badge", text: "Monitoring", wait: 5
    assert_selector ".badge", text: "Scheduled"
  end
end
