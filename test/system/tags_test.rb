require "test_helper"

class TagsTest < ApplicationSystemTestCase
  def setup
    super
    @job = rails_pulse_jobs(:mailer_job)

    # Configure tags for testing
    RailsPulse.configure do |config|
      config.tags = [ "critical", "monitoring", "scheduled" ]
    end
  end

  def teardown
    # Reset configuration
    RailsPulse.configure do |config|
      config.tags = []
    end
    super
  end

  test "can add and remove tags" do
    visit_rails_pulse_path "/jobs/#{@job.id}"

    # Wait for page to load
    assert_selector "body", wait: 5

    # === Add a tag ===
    # Click the "tag +" button to open the tag menu
    find(".tag-add-button", text: "tag +").click

    # Wait for popover menu to appear
    assert_selector ".popover", visible: true, wait: 3

    # Click on "Critical" tag in the menu
    within(".menu") do
      click_button "Critical"
    end

    # Wait for page to reload after adding tag
    assert_selector "body", wait: 5

    # Verify tag was added and appears in the tag list
    assert_selector ".badge", text: "Critical"

    # === Remove the tag ===
    # Find and click the remove button (X) on the tag
    within(".tag-list") do
      # The tag badge should have a remove button with class "tag-remove"
      tag_badge = find(".badge", text: "Critical")
      within(tag_badge) do
        find("button.tag-remove").click
      end
    end

    # Wait for page to reload after removing tag
    assert_selector "body", wait: 5

    # Verify tag was removed
    assert_no_selector ".badge", text: "Critical"

    # === Add multiple tags ===
    # Click the "tag +" button again
    find(".tag-add-button", text: "tag +").click

    assert_selector ".popover", visible: true, wait: 3

    within(".menu") do
      click_button "Monitoring"
    end

    assert_selector "body", wait: 5
    assert_selector ".badge", text: "Monitoring"

    # Add another tag
    find(".tag-add-button", text: "tag +").click

    assert_selector ".popover", visible: true, wait: 3

    within(".menu") do
      click_button "Scheduled"
    end

    assert_selector "body", wait: 5

    # Verify both tags are present
    assert_selector ".badge", text: "Monitoring"
    assert_selector ".badge", text: "Scheduled"

    # === Remove one of the tags ===
    within(".tag-list") do
      tag_badge = find(".badge", text: "Monitoring")
      within(tag_badge) do
        find("button.tag-remove").click
      end
    end

    assert_selector "body", wait: 5

    # Verify only one tag remains
    assert_no_selector ".badge", text: "Monitoring"
    assert_selector ".badge", text: "Scheduled"
  end
end
