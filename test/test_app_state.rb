# frozen_string_literal: true

require "test_helper"

class TestAppState < Minitest::Test
  def sample_notification
    OctoboxTui::Models::Notification.from_api({
      "id" => 1,
      "github_id" => "1",
      "reason" => "mention",
      "unread" => true,
      "archived" => false,
      "starred" => false,
      "updated_at" => Time.now.iso8601,
      "subject" => { "title" => "Test notification", "type" => "Issue" },
      "repo" => { "name" => "test/repo", "owner" => "test" }
    })
  end

  def test_initial_creates_default_state
    state = OctoboxTui::Models::AppState.initial

    assert_equal [], state.notifications
    assert_equal :inbox, state.filter
    assert_equal 0, state.selected_index
    refute state.search_mode
    assert_equal "", state.search_query
    refute state.loading
    refute state.syncing
    assert_nil state.error
    refute state.show_help
    assert_equal({}, state.counts)
  end

  def test_initial_with_notifications
    notifications = [sample_notification]
    counts = { inbox: 1, starred: 0, archived: 0 }
    state = OctoboxTui::Models::AppState.initial(notifications: notifications, counts: counts)

    assert_equal 1, state.notifications.size
    assert_equal 1, state.counts[:inbox]
  end

  def test_filtered_notifications_returns_all_when_no_search
    notifications = [sample_notification]
    state = OctoboxTui::Models::AppState.initial(notifications: notifications)

    assert_equal 1, state.filtered_notifications.size
  end

  def test_filtered_notifications_filters_by_search_query
    n1 = OctoboxTui::Models::Notification.from_api({
      "id" => 1, "subject" => { "title" => "Bug fix" }, "repo" => { "name" => "a/b" }
    })
    n2 = OctoboxTui::Models::Notification.from_api({
      "id" => 2, "subject" => { "title" => "New feature" }, "repo" => { "name" => "c/d" }
    })
    state = OctoboxTui::Models::AppState.initial(notifications: [n1, n2])
      .with(search_mode: true, search_query: "bug")

    assert_equal 1, state.filtered_notifications.size
    assert_equal "Bug fix", state.filtered_notifications.first.subject_title
  end

  def test_selected_notification_returns_notification_at_index
    notifications = [sample_notification]
    state = OctoboxTui::Models::AppState.initial(notifications: notifications)

    assert_equal notifications.first, state.selected_notification
  end

  def test_selected_notification_returns_nil_when_empty
    state = OctoboxTui::Models::AppState.initial

    assert_nil state.selected_notification
  end

  def test_clamp_selection_clamps_to_bounds
    notifications = [sample_notification]
    state = OctoboxTui::Models::AppState.initial(notifications: notifications)
      .with(selected_index: 10)

    clamped = state.clamp_selection
    assert_equal 0, clamped.selected_index
  end

  def test_clamp_selection_handles_empty_list
    state = OctoboxTui::Models::AppState.initial.with(selected_index: 5)

    clamped = state.clamp_selection
    assert_equal 0, clamped.selected_index
  end

  def test_with_returns_new_state
    state = OctoboxTui::Models::AppState.initial
    new_state = state.with(loading: true)

    refute state.loading
    assert new_state.loading
  end

  def test_sidebar_items_includes_tabs_even_when_no_data
    state = OctoboxTui::Models::AppState.initial
    items = state.sidebar_items
    assert items.any? { |i| i[:type] == :tab && i[:value] == :inbox }
    assert items.any? { |i| i[:type] == :tab && i[:value] == :starred }
    assert items.any? { |i| i[:type] == :tab && i[:value] == :archived }
  end

  def test_sidebar_items_includes_repos
    sidebar_data = {
      "owner_counts" => { "foo" => 5 },
      "repos_by_owner" => { "foo" => ["bar"] },
      "repo_counts" => { "foo/bar" => 5 }
    }
    state = OctoboxTui::Models::AppState.initial(sidebar_data: sidebar_data)

    items = state.sidebar_items
    assert items.any? { |i| i[:type] == :header && i[:label] == "Owners" }
    assert items.any? { |i| i[:type] == :owner && i[:value] == "foo" }
    assert items.any? { |i| i[:type] == :repo && i[:value] == "foo/bar" && i[:indent] }
  end

  def test_sidebar_items_includes_types
    sidebar_data = { "types" => { "PullRequest" => 10, "Issue" => 5 } }
    state = OctoboxTui::Models::AppState.initial(sidebar_data: sidebar_data)

    items = state.sidebar_items
    assert items.any? { |i| i[:type] == :header && i[:label] == "Type" }
    assert items.any? { |i| i[:type] == :subject_type && i[:value] == "PullRequest" }
  end

  def test_sidebar_items_includes_reasons
    sidebar_data = { "reasons" => { "mention" => 3, "author" => 2 } }
    state = OctoboxTui::Models::AppState.initial(sidebar_data: sidebar_data)

    items = state.sidebar_items
    assert items.any? { |i| i[:type] == :header && i[:label] == "Reason" }
    assert items.any? { |i| i[:type] == :reason && i[:value] == "mention" }
  end

  def test_selectable_sidebar_items_excludes_headers
    sidebar_data = { "types" => { "PullRequest" => 10 } }
    state = OctoboxTui::Models::AppState.initial(sidebar_data: sidebar_data)

    selectable = state.selectable_sidebar_items
    refute selectable.any? { |i| i[:type] == :header }
    assert selectable.any? { |i| i[:type] == :subject_type }
  end

  def test_filtered_notifications_by_repo
    n1 = OctoboxTui::Models::Notification.from_api({
      "id" => 1, "subject" => { "title" => "One" }, "repo" => { "name" => "foo/bar" }
    })
    n2 = OctoboxTui::Models::Notification.from_api({
      "id" => 2, "subject" => { "title" => "Two" }, "repo" => { "name" => "baz/qux" }
    })
    state = OctoboxTui::Models::AppState.initial(notifications: [n1, n2])
      .with(sidebar_filter: { type: :repo, value: "foo/bar" })

    assert_equal 1, state.filtered_notifications.size
    assert_equal "foo/bar", state.filtered_notifications.first.repo_name
  end

  def test_filtered_notifications_by_reason
    n1 = OctoboxTui::Models::Notification.from_api({
      "id" => 1, "reason" => "mention", "subject" => { "title" => "One" }, "repo" => {}
    })
    n2 = OctoboxTui::Models::Notification.from_api({
      "id" => 2, "reason" => "author", "subject" => { "title" => "Two" }, "repo" => {}
    })
    state = OctoboxTui::Models::AppState.initial(notifications: [n1, n2])
      .with(sidebar_filter: { type: :reason, value: "mention" })

    assert_equal 1, state.filtered_notifications.size
    assert_equal "mention", state.filtered_notifications.first.reason
  end

  def test_filtered_notifications_by_subject_type
    n1 = OctoboxTui::Models::Notification.from_api({
      "id" => 1, "subject" => { "title" => "One", "type" => "PullRequest" }, "repo" => {}
    })
    n2 = OctoboxTui::Models::Notification.from_api({
      "id" => 2, "subject" => { "title" => "Two", "type" => "Issue" }, "repo" => {}
    })
    state = OctoboxTui::Models::AppState.initial(notifications: [n1, n2])
      .with(sidebar_filter: { type: :subject_type, value: "Issue" })

    assert_equal 1, state.filtered_notifications.size
    assert_equal "Issue", state.filtered_notifications.first.subject_type
  end
end
