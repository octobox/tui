# frozen_string_literal: true

require "test_helper"

class TestSearchQuery < Minitest::Test
  def build_notification(attrs = {})
    defaults = {
      id: 1,
      subject_title: "Test notification",
      repo_name: "owner/repo",
      repo_owner: "owner",
      subject_author: nil,
      reason: "mention",
      subject_type: "Issue",
      subject_state: "open",
      unread: true,
      starred: false,
      archived: false,
      muted: false
    }
    merged = defaults.merge(attrs)
    OctoboxTui::Models::Notification.from_api({
      "id" => merged[:id],
      "subject" => {
        "title" => merged[:subject_title],
        "type" => merged[:subject_type],
        "state" => merged[:subject_state],
        "author" => merged[:subject_author]
      },
      "repo" => {
        "name" => merged[:repo_name],
        "owner" => merged[:repo_owner]
      },
      "reason" => merged[:reason],
      "unread" => merged[:unread],
      "starred" => merged[:starred],
      "archived" => merged[:archived],
      "muted" => merged[:muted]
    })
  end

  def test_empty_query_matches_all
    query = OctoboxTui::Models::SearchQuery.new("")
    assert query.empty?

    notification = build_notification
    assert query.matches?(notification)
  end

  def test_text_search
    query = OctoboxTui::Models::SearchQuery.new("test")
    notification = build_notification(subject_title: "Test notification")
    assert query.matches?(notification)

    query2 = OctoboxTui::Models::SearchQuery.new("foobar")
    refute query2.matches?(notification)
  end

  def test_repo_filter
    query = OctoboxTui::Models::SearchQuery.new("repo:owner/repo")
    notification = build_notification(repo_name: "owner/repo")
    assert query.matches?(notification)

    other = build_notification(repo_name: "other/repo")
    refute query.matches?(other)
  end

  def test_owner_filter
    query = OctoboxTui::Models::SearchQuery.new("owner:anthropic")
    notification = build_notification(repo_owner: "anthropic")
    assert query.matches?(notification)

    other = build_notification(repo_owner: "github")
    refute query.matches?(other)
  end

  def test_type_filter
    query = OctoboxTui::Models::SearchQuery.new("type:PullRequest")
    pr = build_notification(subject_type: "PullRequest")
    issue = build_notification(subject_type: "Issue")

    assert query.matches?(pr)
    refute query.matches?(issue)
  end

  def test_type_filter_aliases
    query = OctoboxTui::Models::SearchQuery.new("type:pr")
    pr = build_notification(subject_type: "PullRequest")
    assert query.matches?(pr)
  end

  def test_reason_filter
    query = OctoboxTui::Models::SearchQuery.new("reason:review_requested")
    notification = build_notification(reason: "review_requested")
    other = build_notification(reason: "mention")

    assert query.matches?(notification)
    refute query.matches?(other)
  end

  def test_state_filter
    query = OctoboxTui::Models::SearchQuery.new("state:open")
    open_notification = build_notification(subject_state: "open")
    closed_notification = build_notification(subject_state: "closed")

    assert query.matches?(open_notification)
    refute query.matches?(closed_notification)
  end

  def test_is_unread_filter
    query = OctoboxTui::Models::SearchQuery.new("is:unread")
    unread = build_notification(unread: true)
    read = build_notification(unread: false)

    assert query.matches?(unread)
    refute query.matches?(read)
  end

  def test_is_read_filter
    query = OctoboxTui::Models::SearchQuery.new("is:read")
    unread = build_notification(unread: true)
    read = build_notification(unread: false)

    refute query.matches?(unread)
    assert query.matches?(read)
  end

  def test_is_starred_filter
    query = OctoboxTui::Models::SearchQuery.new("is:starred")
    starred = build_notification(starred: true)
    not_starred = build_notification(starred: false)

    assert query.matches?(starred)
    refute query.matches?(not_starred)
  end

  def test_is_bot_filter
    query = OctoboxTui::Models::SearchQuery.new("is:bot")
    bot = build_notification(subject_author: "dependabot[bot]")
    human = build_notification(subject_author: "andrew")

    assert query.matches?(bot)
    refute query.matches?(human)
  end

  def test_is_human_filter
    query = OctoboxTui::Models::SearchQuery.new("is:human")
    bot = build_notification(subject_author: "dependabot[bot]")
    human = build_notification(subject_author: "andrew")

    refute query.matches?(bot)
    assert query.matches?(human)
  end

  def test_is_pr_filter
    query = OctoboxTui::Models::SearchQuery.new("is:pr")
    pr = build_notification(subject_type: "PullRequest")
    issue = build_notification(subject_type: "Issue")

    assert query.matches?(pr)
    refute query.matches?(issue)
  end

  def test_combined_filters
    query = OctoboxTui::Models::SearchQuery.new("repo:owner/repo is:unread type:pr")
    matching = build_notification(
      repo_name: "owner/repo",
      unread: true,
      subject_type: "PullRequest"
    )
    wrong_repo = build_notification(
      repo_name: "other/repo",
      unread: true,
      subject_type: "PullRequest"
    )

    assert query.matches?(matching)
    refute query.matches?(wrong_repo)
  end

  def test_filter_with_text
    query = OctoboxTui::Models::SearchQuery.new("is:unread bug fix")
    matching = build_notification(subject_title: "Bug fix for login", unread: true)
    wrong_title = build_notification(subject_title: "New feature", unread: true)

    assert query.matches?(matching)
    refute query.matches?(wrong_title)
  end

  def test_quoted_values
    query = OctoboxTui::Models::SearchQuery.new('repo:"owner/my repo"')
    assert_equal ["owner/my repo"], query.repo
  end

  def test_filter_notifications
    notifications = [
      build_notification(id: 1, unread: true),
      build_notification(id: 2, unread: false),
      build_notification(id: 3, unread: true)
    ]

    query = OctoboxTui::Models::SearchQuery.new("is:unread")
    filtered = query.filter_notifications(notifications)

    assert_equal 2, filtered.size
    assert filtered.all?(&:unread)
  end

  def test_inbox_filter
    query = OctoboxTui::Models::SearchQuery.new("inbox:true")
    inbox = build_notification(archived: false, muted: false)
    archived = build_notification(archived: true, muted: false)
    muted = build_notification(archived: false, muted: true)

    assert query.matches?(inbox)
    refute query.matches?(archived)
    refute query.matches?(muted)
  end
end
