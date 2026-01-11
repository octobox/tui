# frozen_string_literal: true

require "test_helper"
require "tempfile"

class TestCache < Minitest::Test
  def setup
    @temp_dir = Dir.mktmpdir
    @db_path = File.join(@temp_dir, "test_cache.db")
    @cache = OctoboxTui::Services::Cache.new(@db_path)
  end

  def teardown
    FileUtils.rm_rf(@temp_dir)
  end

  def sample_notification(id: 1, archived: false, starred: false, muted: false)
    OctoboxTui::Models::Notification.from_api({
      "id" => id,
      "github_id" => id.to_s,
      "reason" => "mention",
      "unread" => true,
      "archived" => archived,
      "starred" => starred,
      "muted" => muted,
      "updated_at" => Time.now.iso8601,
      "subject" => { "title" => "Notification #{id}", "type" => "Issue" },
      "repo" => { "name" => "test/repo", "owner" => "test" }
    })
  end

  def test_save_and_load_notifications
    notifications = [sample_notification(id: 1), sample_notification(id: 2)]
    @cache.save_notifications(notifications)

    loaded = @cache.load_notifications(filter: :inbox)
    assert_equal 2, loaded.size
  end

  def test_load_notifications_filters_by_inbox
    notifications = [
      sample_notification(id: 1, archived: false),
      sample_notification(id: 2, archived: true)
    ]
    @cache.save_notifications(notifications)

    loaded = @cache.load_notifications(filter: :inbox)
    assert_equal 1, loaded.size
    assert_equal 1, loaded.first.id
  end

  def test_load_notifications_filters_by_starred
    notifications = [
      sample_notification(id: 1, starred: false),
      sample_notification(id: 2, starred: true)
    ]
    @cache.save_notifications(notifications)

    loaded = @cache.load_notifications(filter: :starred)
    assert_equal 1, loaded.size
    assert_equal 2, loaded.first.id
  end

  def test_load_notifications_filters_by_archived
    notifications = [
      sample_notification(id: 1, archived: false),
      sample_notification(id: 2, archived: true)
    ]
    @cache.save_notifications(notifications)

    loaded = @cache.load_notifications(filter: :archived)
    assert_equal 1, loaded.size
    assert_equal 2, loaded.first.id
  end

  def test_load_notifications_excludes_muted_from_inbox
    notifications = [
      sample_notification(id: 1, muted: false),
      sample_notification(id: 2, muted: true)
    ]
    @cache.save_notifications(notifications)

    loaded = @cache.load_notifications(filter: :inbox)
    assert_equal 1, loaded.size
    assert_equal 1, loaded.first.id
  end

  def test_update_notification
    @cache.save_notifications([sample_notification(id: 1, starred: false)])

    @cache.update_notification(1, starred: true)

    loaded = @cache.load_notifications(filter: :starred)
    assert_equal 1, loaded.size
  end

  def test_counts_returns_correct_counts
    notifications = [
      sample_notification(id: 1, archived: false, starred: false),
      sample_notification(id: 2, archived: false, starred: true),
      sample_notification(id: 3, archived: true, starred: false)
    ]
    @cache.save_notifications(notifications)

    counts = @cache.counts
    assert_equal 2, counts[:inbox]
    assert_equal 1, counts[:starred]
    assert_equal 1, counts[:archived]
  end

  def test_clear_and_save_notifications_replaces_all
    @cache.save_notifications([sample_notification(id: 1)])
    assert_equal 1, @cache.load_notifications.size

    @cache.clear_and_save_notifications([sample_notification(id: 2), sample_notification(id: 3)])
    loaded = @cache.load_notifications
    assert_equal 2, loaded.size
    assert_equal [2, 3], loaded.map(&:id).sort
  end

  def test_stale_returns_true_when_no_sync
    assert @cache.stale?
  end

  def test_stale_returns_false_after_recent_sync
    @cache.update_sync_status(:notifications)
    refute @cache.stale?
  end

  def test_last_sync_time_returns_nil_when_no_sync
    assert_nil @cache.last_sync_time
  end

  def test_last_sync_time_returns_time_after_sync
    @cache.update_sync_status(:notifications)
    assert_instance_of Time, @cache.last_sync_time
  end
end
