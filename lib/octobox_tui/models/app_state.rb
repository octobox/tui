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
      :sidebar_index
    ) do

      def self.initial(notifications: [], counts: {}, sidebar_data: {})
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
          sidebar_index: 0
        )
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
          else
            result
          end
        end

        return result if search_query.empty?

        query = search_query.downcase
        result.select { |n| n.search_text.downcase.include?(query) }
      end

      def selected_notification
        filtered_notifications[selected_index]
      end

      def clamp_selection
        max = [filtered_notifications.size - 1, 0].max
        with(selected_index: [[selected_index, 0].max, max].min)
      end

      def sidebar_items
        return [] if sidebar_data.empty?

        items = []

        # Read/Unread
        unread = sidebar_data["unread"] || 0
        read = sidebar_data["read"] || 0
        if unread > 0 || read > 0
          items << { type: :unread, value: true, label: "Unread", count: unread } if unread > 0
          items << { type: :unread, value: false, label: "Read", count: read } if read > 0
        end

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
        sidebar_items.reject { |item| item[:type] == :header }
      end
    end
  end
end
