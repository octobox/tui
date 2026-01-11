# frozen_string_literal: true

module OctoboxTui
  module Models
    Notification = Data.define(
      :id,
      :github_id,
      :reason,
      :unread,
      :archived,
      :starred,
      :url,
      :web_url,
      :last_read_at,
      :created_at,
      :updated_at,
      :subject_title,
      :subject_url,
      :subject_type,
      :subject_state,
      :repo_id,
      :repo_name,
      :repo_owner,
      :repo_url,
      :muted,
      :fetched_at
    ) do
      def self.from_api(data)
        subject = data["subject"] || {}
        repo = data["repo"] || {}

        new(
          id: data["id"],
          github_id: data["github_id"]&.to_s,
          reason: data["reason"],
          unread: data["unread"],
          archived: data["archived"],
          starred: data["starred"],
          url: data["url"],
          web_url: data["web_url"],
          last_read_at: parse_time(data["last_read_at"]),
          created_at: parse_time(data["created_at"]),
          updated_at: parse_time(data["updated_at"]),
          subject_title: subject["title"],
          subject_url: subject["url"],
          subject_type: subject["type"],
          subject_state: subject["state"],
          repo_id: repo["id"],
          repo_name: repo["name"],
          repo_owner: repo["owner"],
          repo_url: repo["repo_url"],
          muted: data["muted"] || false,
          fetched_at: Time.now
        )
      end

      def self.parse_time(value)
        return nil if value.nil?
        return value if value.is_a?(Time)
        Time.parse(value.to_s)
      rescue ArgumentError
        nil
      end

      def self.from_db(row)
        new(**row.except(:db_id))
      end

      def to_db
        to_h.except(:fetched_at).merge(fetched_at: Time.now)
      end

      def type_label
        case subject_type
        when "PullRequest" then "[PR]"
        when "Issue" then "[IS]"
        when "Release" then "[RL]"
        when "Commit" then "[CM]"
        when "Discussion" then "[DS]"
        when "CheckSuite" then "[CI]"
        else "[??]"
        end
      end

      def state_style
        case subject_state
        when "open" then :open
        when "closed" then :closed
        when "merged" then :merged
        else :default
        end
      end

      def reason_icon
        case reason
        when "review_requested" then "\u25cf"
        when "author" then "\u25c6"
        when "mention" then "\u25cb"
        when "subscribed", "manual" then "\u25c7"
        when "assign" then "\u25c8"
        when "ci_activity" then "\u26a1"
        when "state_change" then "\u21bb"
        when "comment" then "\u2709"
        else " "
        end
      end

      def display_ref
        if repo_name
          repo_name
        else
          "unknown"
        end
      end

      def display_status
        indicators = []
        indicators << "\u2605" if starred
        indicators << "MUTED" if muted
        indicators.join(" ")
      end

      def age
        return "?" unless updated_at
        seconds = Time.now - updated_at
        case seconds
        when 0..59 then "#{seconds.to_i}s"
        when 60..3599 then "#{(seconds / 60).to_i}m"
        when 3600..86399 then "#{(seconds / 3600).to_i}h"
        else "#{(seconds / 86400).to_i}d"
        end
      end

      def search_text
        [subject_title, repo_name, repo_owner, reason].compact.join(" ")
      end

      def bot_author?
        return false unless repo_owner
        repo_owner.end_with?("[bot]") ||
          repo_owner.downcase.start_with?("dependabot", "renovate", "github-actions")
      end
    end
  end
end
