# frozen_string_literal: true

require "strscan"

module OctoboxTui
  module Models
    # Parser for Octobox search queries - ported from octobox/lib/search_parser.rb
    class SearchParser
      attr_accessor :freetext, :operators

      def initialize(query)
        query = query.to_s
        @operators = {}

        ss = StringScanner.new(query)

        loop do
          # scan for key
          ss.scan_until(/([^'"]?\-?\w+):\s?/)
          if ss.captures
            key = ss.captures[0].strip.to_sym
            @operators[key] ||= []

            # scan for value
            value = ss.scan(/(("|')[^"']+('|")|(\+))|[^"'\s]+/)
            break if value.nil?
            value.split(",").each { |v| @operators[key] << v.strip }
          else
            break
          end
        end

        @freetext = ss.rest.strip
      end

      def [](key)
        values = @operators[key.to_sym] || []
        values.map do |value|
          if ["'", '"'].include?(value[0])
            value[1, value.length - 2]
          else
            value
          end
        end
      end

      def []=(key, value)
        @operators[key.to_sym] = value
      end
    end

    # Search query that filters notifications client-side
    class SearchQuery
      BOT_PATTERNS = %w[[bot] dependabot renovate github-actions].freeze

      attr_reader :parsed_query

      def initialize(query)
        @parsed_query = SearchParser.new(query)
      end

      def empty?
        parsed_query.operators.empty? && parsed_query.freetext.empty?
      end

      def filter_notifications(notifications)
        return notifications if empty?

        result = notifications

        # Text search on title
        if !parsed_query.freetext.empty?
          query_text = parsed_query.freetext.downcase
          result = result.select { |n| n.search_text.downcase.include?(query_text) }
        end

        # Apply filters
        result = filter_by_repo(result)
        result = filter_by_owner(result)
        result = filter_by_type(result)
        result = filter_by_reason(result)
        result = filter_by_state(result)
        result = filter_by_unread(result)
        result = filter_by_starred(result)
        result = filter_by_archived(result)
        result = filter_by_inbox(result)
        result = filter_by_bot(result)
        result = filter_by_muted(result)

        result
      end

      def matches?(notification)
        filter_notifications([notification]).any?
      end

      def repo
        parsed_query[:repo]
      end

      def exclude_repo
        parsed_query[:"-repo"]
      end

      def owner
        values = parsed_query[:owner]
        return values if values.any?
        values = parsed_query[:org]
        return values if values.any?
        parsed_query[:user]
      end

      def exclude_owner
        values = parsed_query[:"-owner"]
        return values if values.any?
        values = parsed_query[:"-org"]
        return values if values.any?
        parsed_query[:"-user"]
      end

      def type
        parsed_query[:type].map { |t| classify_type(t) }
      end

      def exclude_type
        parsed_query[:"-type"].map { |t| classify_type(t) }
      end

      def reason
        parsed_query[:reason].map { |r| r.downcase.tr(" ", "_") }
      end

      def exclude_reason
        parsed_query[:"-reason"].map { |r| r.downcase.tr(" ", "_") }
      end

      def state
        parsed_query[:state].map(&:downcase)
      end

      def exclude_state
        parsed_query[:"-state"].map(&:downcase)
      end

      def unread
        is_filter(:unread) || boolean_filter(:unread)
      end

      def starred
        is_filter(:starred) || boolean_filter(:starred)
      end

      def archived
        is_filter(:archived) || boolean_filter(:archived)
      end

      def inbox
        boolean_filter(:inbox)
      end

      def bot
        is_filter(:bot) || boolean_filter(:bot)
      end

      def muted
        is_filter(:muted) || boolean_filter(:muted)
      end

      # Check if is:value matches a known filter
      def is_filter(name)
        is_values = parsed_query[:is]
        return nil if is_values.empty?
        is_values.any? { |v| v.downcase == name.to_s } ? true : nil
      end

      def filter_by_repo(notifications)
        if repo.any?
          notifications = notifications.select { |n| repo.any? { |r| n.repo_name&.downcase == r.downcase } }
        end
        if exclude_repo.any?
          notifications = notifications.reject { |n| exclude_repo.any? { |r| n.repo_name&.downcase == r.downcase } }
        end
        notifications
      end

      def filter_by_owner(notifications)
        if owner.any?
          notifications = notifications.select { |n| owner.any? { |o| n.repo_owner&.downcase == o.downcase } }
        end
        if exclude_owner.any?
          notifications = notifications.reject { |n| exclude_owner.any? { |o| n.repo_owner&.downcase == o.downcase } }
        end
        notifications
      end

      def filter_by_type(notifications)
        # Handle is:pr and is:issue shortcuts
        is_values = parsed_query[:is]
        if is_values.any? { |v| %w[pr pullrequest].include?(v.downcase) }
          notifications = notifications.select { |n| n.subject_type == "PullRequest" }
        end
        if is_values.any? { |v| v.downcase == "issue" }
          notifications = notifications.select { |n| n.subject_type == "Issue" }
        end

        if type.any?
          notifications = notifications.select { |n| type.include?(n.subject_type) }
        end
        if exclude_type.any?
          notifications = notifications.reject { |n| exclude_type.include?(n.subject_type) }
        end
        notifications
      end

      def filter_by_reason(notifications)
        if reason.any?
          notifications = notifications.select { |n| reason.include?(n.reason&.downcase&.tr(" ", "_")) }
        end
        if exclude_reason.any?
          notifications = notifications.reject { |n| exclude_reason.include?(n.reason&.downcase&.tr(" ", "_")) }
        end
        notifications
      end

      def filter_by_state(notifications)
        if state.any?
          notifications = notifications.select { |n| state.include?(n.subject_state&.downcase) }
        end
        if exclude_state.any?
          notifications = notifications.reject { |n| exclude_state.include?(n.subject_state&.downcase) }
        end
        notifications
      end

      def filter_by_unread(notifications)
        # Handle is:read as opposite of unread
        if parsed_query[:is].any? { |v| v.downcase == "read" }
          return notifications.select { |n| n.unread == false }
        end
        return notifications if unread.nil?
        notifications.select { |n| n.unread == unread }
      end

      def filter_by_starred(notifications)
        return notifications if starred.nil?
        notifications.select { |n| n.starred == starred }
      end

      def filter_by_archived(notifications)
        return notifications if archived.nil?
        notifications.select { |n| n.archived == archived }
      end

      def filter_by_inbox(notifications)
        return notifications if inbox.nil?
        if inbox
          notifications.select { |n| !n.archived && !n.muted }
        else
          notifications.select { |n| n.archived || n.muted }
        end
      end

      def filter_by_bot(notifications)
        # Handle is:human as opposite of bot
        if parsed_query[:is].any? { |v| v.downcase == "human" }
          return notifications.reject { |n| bot_notification?(n) }
        end
        return notifications if bot.nil?
        if bot
          notifications.select { |n| bot_notification?(n) }
        else
          notifications.reject { |n| bot_notification?(n) }
        end
      end

      def filter_by_muted(notifications)
        return notifications if muted.nil?
        notifications.select { |n| n.muted == muted }
      end

      def boolean_filter(name)
        values = parsed_query[name]
        return nil if values.empty?
        values.first&.downcase == "true"
      end

      def classify_type(type_str)
        case type_str.downcase
        when "pr", "pullrequest", "pull_request"
          "PullRequest"
        when "issue"
          "Issue"
        when "release"
          "Release"
        when "commit"
          "Commit"
        when "discussion"
          "Discussion"
        when "checksuite", "check_suite"
          "CheckSuite"
        else
          type_str
        end
      end

      def bot_notification?(notification)
        # Check subject_author first (matches Octobox's bot_author scope)
        if notification.subject_author
          author = notification.subject_author.downcase
          return true if author.include?("[bot]") || author.end_with?("-bot")
        end
        false
      end
    end
  end
end
