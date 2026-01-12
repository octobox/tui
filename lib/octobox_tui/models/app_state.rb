# frozen_string_literal: true

module OctoboxTui
  module Models
    FILTERS = [:inbox, :starred, :archived].freeze

    AppState = Data.define(
      :notifications,
      :filter,
      :selected_index,
      :search_mode,
      :search_query,
      :loading,
      :syncing,
      :error,
      :show_help,
      :counts,
      :sidebar_data,
      :sidebar_filter,
      :sidebar_focus,
      :sidebar_index,
      :pinned_searches
    ) do

      def self.initial(notifications: [], counts: {}, sidebar_data: {}, pinned_searches: [])
        new(
          notifications: notifications,
          filter: :inbox,
          selected_index: 0,
          search_mode: false,
          search_query: "",
          loading: false,
          syncing: false,
          error: nil,
          show_help: false,
          counts: counts,
          sidebar_data: sidebar_data,
          sidebar_filter: nil,
          sidebar_focus: false,
          sidebar_index: 0,
          pinned_searches: pinned_searches
        )
      end

      def bot_notification?(n)
        # Check subject_author (matches Octobox's bot_author scope)
        if n.subject_author
          author = n.subject_author.downcase
          return true if author.include?("[bot]") || author.end_with?("-bot")
        end
        false
      end

      def filtered_notifications
        result = notifications

        if sidebar_filter
          result = case sidebar_filter[:type]
          when :owner
            result.select { |n| n.repo_owner == sidebar_filter[:value] }
          when :repo
            result.select { |n| n.repo_name == sidebar_filter[:value] }
          when :reason
            result.select { |n| n.reason == sidebar_filter[:value] }
          when :subject_type
            result.select { |n| n.subject_type == sidebar_filter[:value] }
          when :state
            result.select { |n| n.subject_state == sidebar_filter[:value] }
          when :unread
            result.select { |n| n.unread == sidebar_filter[:value] }
          when :bot
            if sidebar_filter[:value]
              result.select { |n| bot_notification?(n) }
            else
              result.reject { |n| bot_notification?(n) }
            end
          else
            result
          end
        end

        return result if search_query.empty?

        SearchQuery.new(search_query).filter_notifications(result)
      end

      def selected_notification
        filtered_notifications[selected_index]
      end

      def clamp_selection
        max = [filtered_notifications.size - 1, 0].max
        with(selected_index: [[selected_index, 0].max, max].min)
      end

      def sidebar_items
        items = []

        # Main tabs first
        items << { type: :tab, value: :inbox, label: "Inbox" }
        items << { type: :tab, value: :starred, label: "Starred" }
        items << { type: :tab, value: :archived, label: "Archived" }
        items << { type: :separator }

        # Pinned searches
        unless pinned_searches.empty?
          pinned_searches.each do |ps|
            items << { type: :pinned, value: ps["query"], label: ps["name"], count: ps["count"] || 0 }
          end
          items << { type: :separator }
        end

        return items if sidebar_data.empty?

        # Humans/Bots
        humans = sidebar_data["humans"] || 0
        bots = sidebar_data["bots"] || 0
        items << { type: :bot, value: false, label: "Humans", count: humans } if humans > 0
        items << { type: :bot, value: true, label: "Bots", count: bots } if bots > 0

        # Read/Unread
        unread = sidebar_data["unread"] || 0
        read = sidebar_data["read"] || 0
        items << { type: :unread, value: true, label: "Unread", count: unread } if unread > 0
        items << { type: :unread, value: false, label: "Read", count: read } if read > 0

        # States (Open, Merged, Closed)
        states = sidebar_data["states"] || {}
        unless states.empty?
          items << { type: :header, label: "Status" }
          %w[open merged closed].each do |state|
            count = states[state]
            items << { type: :state, value: state, count: count } if count && count > 0
          end
        end

        # Types
        types = sidebar_data["types"] || {}
        unless types.empty?
          items << { type: :header, label: "Type" }
          types.each { |name, count| items << { type: :subject_type, value: name, count: count } }
        end

        # Reasons
        reasons = sidebar_data["reasons"] || {}
        unless reasons.empty?
          items << { type: :header, label: "Reason" }
          reasons.each { |name, count| items << { type: :reason, value: name, count: count } }
        end

        # Owners with nested repos
        owner_counts = sidebar_data["owner_counts"] || {}
        repos_by_owner = sidebar_data["repos_by_owner"] || {}
        repo_counts = sidebar_data["repo_counts"] || {}
        unless owner_counts.empty?
          items << { type: :header, label: "Owners" }
          owner_counts.each do |owner, count|
            items << { type: :owner, value: owner, count: count }
            # Add repos under this owner
            repos = repos_by_owner[owner] || []
            repos.sort.each do |repo_short|
              full_name = "#{owner}/#{repo_short}"
              repo_count = repo_counts[full_name] || 0
              items << { type: :repo, value: full_name, label: repo_short, count: repo_count, indent: true }
            end
          end
        end

        items
      end

      def selectable_sidebar_items
        sidebar_items.reject { |item| [:header, :separator].include?(item[:type]) }
      end
    end
  end
end
