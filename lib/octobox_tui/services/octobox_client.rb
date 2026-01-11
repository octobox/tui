# frozen_string_literal: true

require "faraday"
require "json"

module OctoboxTui
  module Services
    class OctoboxClient
      attr_reader :base_url

      def initialize(base_url:, api_token:)
        @base_url = base_url
        @api_token = api_token
        log.info "OctoboxClient initialized for #{base_url}"
      end

      def fetch_notifications(page: 1, per_page: 100, starred: nil, archived: nil, query: nil)
        log.info "Fetching notifications (page: #{page}, per_page: #{per_page})"
        params = { page: page, per_page: per_page }
        params[:starred] = starred unless starred.nil?
        params[:archive] = archived unless archived.nil?
        params[:q] = query if query && !query.empty?

        response = get("/api/notifications.json", params)
        data = JSON.parse(response.body)
        log.info "Fetched #{data['notifications']&.size || 0} notifications"
        log.debug "Pagination: #{data['pagination'].inspect}"
        if data['notifications']&.any?
          log.debug "First notification: #{data['notifications'].first.inspect}"
        end
        data
      end

      def fetch_all_notifications(starred: nil, archived: nil, query: nil)
        all_notifications = []
        page = 1

        loop do
          data = fetch_notifications(page: page, per_page: 100, starred: starred, archived: archived, query: query)
          notifications = data["notifications"] || []
          break if notifications.empty?

          all_notifications.concat(notifications)

          pagination = data["pagination"] || {}
          break if page >= (pagination["total_pages"] || 1)

          page += 1
        end

        all_notifications
      end

      def sync
        log.info "Triggering sync with GitHub"
        post("/api/notifications/sync.json")
      end

      def syncing?
        response = connection.get("/api/notifications/syncing.json")
        response.status == 423
      end

      def unread_count
        response = get("/api/notifications/unread_count.json")
        data = JSON.parse(response.body)
        data["count"] || 0
      end

      def star(notification_id)
        log.info "Toggling star for notification #{notification_id}"
        post("/api/notifications/#{notification_id}/star.json")
      end

      def archive(notification_ids)
        ids = Array(notification_ids)
        log.info "Archiving #{ids.size} notification(s)"
        post("/api/notifications/archive_selected.json", id: ids)
      end

      def unarchive(notification_ids)
        ids = Array(notification_ids)
        log.info "Unarchiving #{ids.size} notification(s)"
        post("/api/notifications/archive_selected.json", id: ids, value: false)
      end

      def mute(notification_ids)
        ids = Array(notification_ids)
        log.info "Muting #{ids.size} notification(s)"
        post("/api/notifications/mute_selected.json", id: ids)
      end

      def mark_read(notification_ids)
        ids = Array(notification_ids)
        log.info "Marking #{ids.size} notification(s) as read"
        get("/api/notifications/mark_read_selected.json", id: ids)
      end

      def delete(notification_ids)
        ids = Array(notification_ids)
        log.info "Deleting #{ids.size} notification(s)"
        request(:delete, "/api/notifications/delete_selected.json", id: ids)
      end

      def user_profile
        response = get("/api/users/profile.json")
        JSON.parse(response.body)
      end

      def log
        Services.logger
      end

      def connection
        @connection ||= Faraday.new(url: @base_url) do |f|
          f.request :url_encoded
          f.adapter Faraday.default_adapter
          f.headers["Authorization"] = "Bearer #{@api_token}"
          f.headers["X-Octobox-API"] = "1"
          f.headers["Accept"] = "application/json"
          f.headers["Content-Type"] = "application/json"
        end
      end

      def get(path, params = {})
        response = connection.get(path, params)
        handle_response(response)
        response
      end

      def post(path, params = {})
        response = connection.post(path) do |req|
          req.params = params
        end
        handle_response(response)
        response
      end

      def request(method, path, params = {})
        response = connection.send(method, path) do |req|
          req.params = params
        end
        handle_response(response)
        response
      end

      def handle_response(response)
        case response.status
        when 200..299
          # OK
        when 401
          raise OctoboxTui::Error, "Unauthorized: check your API token"
        when 404
          raise OctoboxTui::Error, "Not found: #{response.env.url}"
        when 503
          raise OctoboxTui::Error, "Service unavailable (sync in progress?)"
        else
          raise OctoboxTui::Error, "API error: #{response.status} - #{response.body}"
        end
      end
    end
  end
end
