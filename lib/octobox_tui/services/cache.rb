# frozen_string_literal: true

require "sequel"

module OctoboxTui
  module Services
    class Cache
      CACHE_TTL = 5 * 60

      attr_reader :db

      def initialize(db_path)
        @db = Sequel.sqlite(db_path)
        Db::Schema.migrate!(db)
        log.info "Cache initialized: #{db_path}"
      end

      def log
        Services.logger
      end

      def load_notifications(filter: :inbox)
        log.debug "Loading notifications (filter: #{filter})"
        result = case filter
        when :inbox
          db[:notifications]
            .where(archived: false, muted: false)
            .order(Sequel.desc(:updated_at))
            .all
            .map { |row| Models::Notification.from_db(row) }
        when :starred
          db[:notifications]
            .where(starred: true)
            .order(Sequel.desc(:updated_at))
            .all
            .map { |row| Models::Notification.from_db(row) }
        when :archived
          db[:notifications]
            .where(archived: true)
            .order(Sequel.desc(:updated_at))
            .all
            .map { |row| Models::Notification.from_db(row) }
        else
          db[:notifications]
            .order(Sequel.desc(:updated_at))
            .all
            .map { |row| Models::Notification.from_db(row) }
        end
        log.debug "  Loaded #{result.size} notifications"
        result
      end

      def save_notifications(notifications)
        log.info "Saving #{notifications.size} notifications"
        inserted = 0
        updated = 0

        db.transaction do
          notifications.each do |notification|
            existing = db[:notifications].where(id: notification.id).first
            if existing
              db[:notifications].where(id: notification.id).update(notification.to_db)
              updated += 1
            else
              db[:notifications].insert(notification.to_db)
              inserted += 1
              log.debug "  New: #{notification.subject_title}"
            end
          end
          update_sync_status(:notifications)
        end
        log.info "  Inserted: #{inserted}, Updated: #{updated}"
      end

      def clear_and_save_notifications(notifications)
        log.info "Clearing and saving #{notifications.size} notifications"
        db.transaction do
          db[:notifications].delete
          notifications.each do |notification|
            db[:notifications].insert(notification.to_db)
          end
          update_sync_status(:notifications)
        end
        log.info "  Saved #{notifications.size} notifications"
      end

      def update_notification(id, **updates)
        db[:notifications].where(id: id).update(updates)
      end

      def counts
        {
          inbox: db[:notifications].where(archived: false, muted: false).count,
          starred: db[:notifications].where(starred: true).count,
          archived: db[:notifications].where(archived: true).count
        }
      end

      def stale?(resource = :notifications)
        status = db[:sync_status].where(resource: resource.to_s).first
        return true unless status&.dig(:last_sync)
        Time.now - status[:last_sync] > CACHE_TTL
      end

      def update_sync_status(resource, error: nil)
        db[:sync_status].insert_conflict(
          target: :resource,
          update: { last_sync: Time.now, error: error }
        ).insert(resource: resource.to_s, last_sync: Time.now, error: error)
      end

      def last_sync_time
        status = db[:sync_status].where(resource: "notifications").first
        status&.dig(:last_sync)
      end

      def sidebar_data
        base = db[:notifications].where(archived: false, muted: false)

        # Build owner -> repos tree
        repos_by_owner = {}
        base.exclude(repo_name: nil)
          .select(:repo_owner, :repo_name)
          .distinct
          .each do |row|
            owner = row[:repo_owner]
            repo = row[:repo_name]
            next unless owner && repo
            repos_by_owner[owner] ||= []
            repo_short = repo.split("/").last
            repos_by_owner[owner] << repo_short unless repos_by_owner[owner].include?(repo_short)
          end

        # Count per owner
        owner_counts = base.exclude(repo_owner: nil)
          .group_and_count(:repo_owner)
          .order(Sequel.desc(:count))
          .all
          .to_h { |row| [row[:repo_owner], row[:count]] }

        # Count per repo
        repo_counts = base.exclude(repo_name: nil)
          .group_and_count(:repo_name)
          .all
          .to_h { |row| [row[:repo_name], row[:count]] }

        {
          "owner_counts" => owner_counts,
          "repos_by_owner" => repos_by_owner,
          "repo_counts" => repo_counts,
          "types" => base.exclude(subject_type: nil)
            .group_and_count(:subject_type)
            .order(Sequel.desc(:count))
            .all
            .to_h { |row| [row[:subject_type], row[:count]] },
          "reasons" => base.exclude(reason: nil)
            .group_and_count(:reason)
            .order(Sequel.desc(:count))
            .all
            .to_h { |row| [row[:reason], row[:count]] },
          "states" => base.exclude(subject_state: nil)
            .group_and_count(:subject_state)
            .order(Sequel.desc(:count))
            .all
            .to_h { |row| [row[:subject_state], row[:count]] },
          "unread" => base.where(unread: true).count,
          "read" => base.where(unread: false).count
        }
      end
    end
  end
end
