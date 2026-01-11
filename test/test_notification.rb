# frozen_string_literal: true

require "test_helper"

class TestNotification < Minitest::Test
  def sample_api_data
    {
      "id" => 123,
      "github_id" => "456",
      "reason" => "mention",
      "unread" => true,
      "archived" => false,
      "starred" => true,
      "url" => "https://api.github.com/notifications/threads/456",
      "web_url" => "https://github.com/octobox/octobox/pull/320",
      "last_read_at" => "2024-01-20 10:00:00 UTC",
      "created_at" => "2024-01-20T09:00:00.000Z",
      "updated_at" => "2024-01-20T11:00:00.000Z",
      "subject" => {
        "title" => "Add new feature",
        "url" => "https://api.github.com/repos/octobox/octobox/pulls/320",
        "type" => "PullRequest",
        "state" => "open"
      },
      "repo" => {
        "id" => 789,
        "name" => "octobox/octobox",
        "owner" => "octobox",
        "repo_url" => "https://github.com/octobox/octobox"
      }
    }
  end

  def test_from_api_creates_notification
    notification = OctoboxTui::Models::Notification.from_api(sample_api_data)

    assert_equal 123, notification.id
    assert_equal "456", notification.github_id
    assert_equal "mention", notification.reason
    assert notification.unread
    refute notification.archived
    assert notification.starred
    assert_equal "Add new feature", notification.subject_title
    assert_equal "PullRequest", notification.subject_type
    assert_equal "open", notification.subject_state
    assert_equal "octobox/octobox", notification.repo_name
    assert_equal "octobox", notification.repo_owner
  end

  def test_type_label_for_pull_request
    notification = OctoboxTui::Models::Notification.from_api(sample_api_data)
    assert_equal "[PR]", notification.type_label
  end

  def test_type_label_for_issue
    data = sample_api_data.merge("subject" => { "type" => "Issue", "title" => "Bug" })
    notification = OctoboxTui::Models::Notification.from_api(data)
    assert_equal "[IS]", notification.type_label
  end

  def test_type_label_for_release
    data = sample_api_data.merge("subject" => { "type" => "Release", "title" => "v1.0" })
    notification = OctoboxTui::Models::Notification.from_api(data)
    assert_equal "[RL]", notification.type_label
  end

  def test_state_style_for_open
    notification = OctoboxTui::Models::Notification.from_api(sample_api_data)
    assert_equal :open, notification.state_style
  end

  def test_state_style_for_closed
    data = sample_api_data.merge("subject" => sample_api_data["subject"].merge("state" => "closed"))
    notification = OctoboxTui::Models::Notification.from_api(data)
    assert_equal :closed, notification.state_style
  end

  def test_state_style_for_merged
    data = sample_api_data.merge("subject" => sample_api_data["subject"].merge("state" => "merged"))
    notification = OctoboxTui::Models::Notification.from_api(data)
    assert_equal :merged, notification.state_style
  end

  def test_reason_icon_for_mention
    notification = OctoboxTui::Models::Notification.from_api(sample_api_data)
    assert_equal "\u25cb", notification.reason_icon
  end

  def test_reason_icon_for_review_requested
    data = sample_api_data.merge("reason" => "review_requested")
    notification = OctoboxTui::Models::Notification.from_api(data)
    assert_equal "\u25cf", notification.reason_icon
  end

  def test_reason_icon_for_author
    data = sample_api_data.merge("reason" => "author")
    notification = OctoboxTui::Models::Notification.from_api(data)
    assert_equal "\u25c6", notification.reason_icon
  end

  def test_display_ref
    notification = OctoboxTui::Models::Notification.from_api(sample_api_data)
    assert_equal "octobox/octobox", notification.display_ref
  end

  def test_display_status_with_star
    notification = OctoboxTui::Models::Notification.from_api(sample_api_data)
    assert_includes notification.display_status, "\u2605"
  end

  def test_display_status_without_star
    data = sample_api_data.merge("starred" => false)
    notification = OctoboxTui::Models::Notification.from_api(data)
    assert_equal "", notification.display_status
  end

  def test_search_text_includes_title_and_repo
    notification = OctoboxTui::Models::Notification.from_api(sample_api_data)
    assert_includes notification.search_text, "Add new feature"
    assert_includes notification.search_text, "octobox/octobox"
    assert_includes notification.search_text, "mention"
  end

  def test_age_returns_days_for_old_notifications
    old_time = (Time.now - 86400 * 5).iso8601
    data = sample_api_data.merge("updated_at" => old_time)
    notification = OctoboxTui::Models::Notification.from_api(data)
    assert_match(/\d+d/, notification.age)
  end

  def test_to_db_returns_hash
    notification = OctoboxTui::Models::Notification.from_api(sample_api_data)
    db_hash = notification.to_db

    assert_kind_of Hash, db_hash
    assert_equal 123, db_hash[:id]
    assert_equal "mention", db_hash[:reason]
    assert db_hash.key?(:fetched_at)
  end
end
