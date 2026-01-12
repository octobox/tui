# frozen_string_literal: true

require "ratatui_ruby"

module OctoboxTui
  class App
    TABS = ["Inbox", "Starred", "Archived"].freeze
    TAB_KEYS = [:inbox, :starred, :archived].freeze

    def initialize
      @config = Config.new
      validate_config!
      @cache = Services::Cache.new(@config.db_path)
      @client = Services::OctoboxClient.new(
        base_url: @config.base_url,
        api_token: @config.api_token
      )
      @pinned_searches = []
      @state = Models::AppState.initial(
        notifications: @cache.load_notifications(filter: :inbox),
        counts: @cache.counts,
        sidebar_data: @cache.sidebar_data,
        pinned_searches: @pinned_searches
      )
      @table_state = nil
      @sidebar_state = nil
      @selected_tab = 0
      @last_update_check = nil
      log.info "App initialized, loaded #{@state.notifications.size} notifications from cache"
    end

    def validate_config!
      return if @config.valid?

      token = @config.prompt_for_token
      return if token

      raise OctoboxTui::Error, "No API token provided. Cannot continue."
    end

    def log
      Services.logger
    end

    def run
      RatatuiRuby.run do |tui|
        @tui = tui
        init_styles
        @table_state = RatatuiRuby::TableState.new(nil)
        @table_state.select(0)
        @sidebar_state = RatatuiRuby::TableState.new(nil)
        @sidebar_state.select(0)

        sync_if_stale

        loop do
          render
          break if handle_input == :quit
        end
      end
    end

    def init_styles
      @style_header = @tui.style(fg: :white, modifiers: [:bold])
      @style_tab_highlight = @tui.style(fg: :cyan, modifiers: [:bold])
      @style_row_highlight = @tui.style(bg: :blue, fg: :white, modifiers: [:bold])
      @style_muted = @tui.style(fg: :dark_gray)
      @style_search = @tui.style(fg: :yellow)
      @style_starred = @tui.style(fg: :yellow)
      @style_open = @tui.style(fg: :green)
      @style_closed = @tui.style(fg: :red)
      @style_merged = @tui.style(fg: :magenta)
      @style_reason = @tui.style(fg: :yellow)
      @style_unread = @tui.style(fg: :cyan, modifiers: [:bold])
    end

    def render
      @tui.draw do |frame|
        main_area, status_area = @tui.layout_split(
          frame.area,
          direction: :vertical,
          constraints: [
            @tui.constraint_fill(1),
            @tui.constraint_length(1)
          ]
        )

        # Split main area into sidebar and content
        sidebar_area, content_area = @tui.layout_split(
          main_area,
          direction: :horizontal,
          constraints: [
            @tui.constraint_length(28),
            @tui.constraint_fill(1)
          ]
        )
        render_sidebar(frame, sidebar_area)

        if @state.search_mode
          search_area, table_area = @tui.layout_split(
            content_area,
            direction: :vertical,
            constraints: [
              @tui.constraint_length(1),
              @tui.constraint_fill(1)
            ]
          )
          render_search_bar(frame, search_area)
          render_table(frame, table_area)
        else
          render_table(frame, content_area)
        end

        render_status_bar(frame, status_area)
        render_help_popup(frame, frame.area) if @state.show_help
      end
    end

    def render_tabs(frame, area)
      counts = @state.counts
      tab_titles = TAB_KEYS.each_with_index.map do |key, idx|
        count = counts[key] || 0
        "#{TABS[idx]} (#{count})"
      end

      status_suffix = if @state.syncing
        " syncing..."
      elsif @state.loading
        " loading..."
      else
        ""
      end

      tabs = @tui.tabs(
        titles: tab_titles,
        selected_index: @selected_tab,
        block: @tui.block(title: " octobox_tui#{status_suffix} ", borders: [:all]),
        highlight_style: @style_tab_highlight,
        divider: " | "
      )
      frame.render_widget(tabs, area)
    end

    def render_sidebar(frame, area)
      rows = []
      counts = @state.counts

      # Add all sidebar items
      @state.sidebar_items.each do |item|
        cells = case item[:type]
        when :header
          [
            @tui.table_cell(content: item[:label], style: @style_header),
            ""
          ]
        when :separator
          ["", ""]
        when :tab
          count = counts[item[:value]] || 0
          is_current = @state.filter == item[:value] && @state.sidebar_filter.nil?
          style = is_current ? @style_tab_highlight : nil
          prefix = is_current ? "> " : "  "
          # Don't show count for archived tab
          count_str = item[:value] == :archived ? "" : count.to_s
          [
            style ? @tui.table_cell(content: "#{prefix}#{item[:label]}", style: style) : "#{prefix}#{item[:label]}",
            @tui.table_cell(content: count_str, style: @style_muted)
          ]
        else
          indent = item[:indent] ? "    " : "  "
          label = item[:label] || case item[:type]
          when :owner then item[:value]
          when :repo then item[:value].split("/").last || item[:value]
          when :subject_type then item[:value]
          when :reason then item[:value].to_s.tr("_", " ")
          when :state then item[:value].to_s.capitalize
          when :unread then item[:value] ? "Unread" : "Read"
          when :bot then item[:value] ? "Bots" : "Humans"
          when :pinned then item[:label]
          else item[:value].to_s
          end

          is_selected = @state.sidebar_filter &&
            @state.sidebar_filter[:type] == item[:type] &&
            @state.sidebar_filter[:value] == item[:value]

          # Color indicator for states
          state_indicator = case item[:type]
          when :state
            case item[:value]
            when "open" then "\u25cf "
            when "merged" then "\u25cf "
            when "closed" then "\u25cf "
            else ""
            end
          else
            ""
          end

          state_style = case item[:type]
          when :state
            case item[:value]
            when "open" then @style_open
            when "merged" then @style_merged
            when "closed" then @style_closed
            end
          end

          style = is_selected ? @style_tab_highlight : state_style
          prefix = is_selected ? "> " : indent

          display_label = truncate(label.to_s, item[:indent] ? 14 : 16)
          cell_content = "#{prefix}#{state_indicator}#{display_label}"

          [
            style ? @tui.table_cell(content: cell_content, style: style) : cell_content,
            @tui.table_cell(content: item[:count].to_s, style: @style_muted)
          ]
        end
        rows << @tui.table_row(cells: cells)
      end

      widths = [
        @tui.constraint_fill(1),
        @tui.constraint_length(4)
      ]

      border_style = @state.sidebar_focus ? @style_tab_highlight : nil
      status_suffix = if @state.syncing
        " syncing..."
      elsif @state.loading
        " loading..."
      else
        ""
      end

      table = @tui.table(
        rows: rows,
        widths: widths,
        row_highlight_style: @state.sidebar_focus ? @style_row_highlight : nil,
        highlight_symbol: @state.sidebar_focus ? ">> " : "   ",
        column_spacing: 1,
        block: @tui.block(title: " octobox#{status_suffix} ", borders: [:all], border_style: border_style)
      )

      frame.render_stateful_widget(table, area, @sidebar_state)
    end

    def render_search_bar(frame, area)
      frame.render_widget(
        @tui.paragraph(
          text: @tui.text_line(spans: [
            @tui.text_span(content: " / ", style: @style_search),
            @tui.text_span(content: @state.search_query, style: @style_search),
            @tui.text_span(content: "_", style: @tui.style(modifiers: [:slow_blink]))
          ])
        ),
        area
      )
    end

    def render_table(frame, area)
      notifications = @state.filtered_notifications

      if notifications.empty?
        render_empty_state(frame, area)
        return
      end

      # Show author column on wide terminals (> 120 cols)
      show_author = area.width > 120
      rows = notifications.map { |n| build_table_row(n, show_author: show_author) }

      widths = if show_author
        [
          @tui.constraint_length(4),
          @tui.constraint_length(1),
          @tui.constraint_length(30),
          @tui.constraint_fill(1),
          @tui.constraint_length(20),
          @tui.constraint_length(4),
          @tui.constraint_length(6)
        ]
      else
        [
          @tui.constraint_length(4),
          @tui.constraint_length(1),
          @tui.constraint_length(30),
          @tui.constraint_fill(1),
          @tui.constraint_length(4),
          @tui.constraint_length(6)
        ]
      end

      table = @tui.table(
        rows: rows,
        widths: widths,
        row_highlight_style: @style_row_highlight,
        highlight_symbol: ">> ",
        column_spacing: 1,
        block: @tui.block(borders: [:all])
      )

      table_area, scrollbar_area = @tui.layout_split(
        area,
        direction: :horizontal,
        constraints: [
          @tui.constraint_fill(1),
          @tui.constraint_length(1)
        ]
      )

      frame.render_stateful_widget(table, table_area, @table_state)

      if notifications.size > (area.height - 2)
        scrollbar = @tui.scrollbar(
          content_length: notifications.size,
          position: @table_state.offset || 0,
          orientation: :vertical_right,
          thumb_symbol: "\u2588",
          track_symbol: "\u2591"
        )
        frame.render_widget(scrollbar, scrollbar_area)
      end
    end

    def build_table_row(notification, show_author: false)
      type_style = case notification.state_style
      when :open then @style_open
      when :closed then @style_closed
      when :merged then @style_merged
      else @style_muted
      end

      title_style = notification.unread ? @style_unread : nil

      cells = [
        @tui.table_cell(content: notification.type_label, style: type_style),
        @tui.table_cell(content: notification.reason_icon, style: @style_reason),
        notification.display_ref,
        title_style ? @tui.table_cell(content: truncate(notification.subject_title || "", 80), style: title_style) : truncate(notification.subject_title || "", 80)
      ]

      if show_author
        author = truncate(notification.subject_author || "-", 18)
        cells << @tui.table_cell(content: author, style: @style_muted)
      end

      cells << @tui.table_cell(content: notification.age, style: @style_muted)
      cells << @tui.table_cell(content: notification.display_status, style: @style_starred)

      @tui.table_row(cells: cells)
    end

    def render_empty_state(frame, area)
      message = if @state.search_query.empty?
        case @state.filter
        when :inbox then "Inbox empty - you're all caught up!"
        when :starred then "No starred notifications"
        when :archived then "No archived notifications"
        end
      else
        "No matches for '#{@state.search_query}'"
      end
      frame.render_widget(
        @tui.paragraph(
          text: message,
          alignment: :center,
          block: @tui.block(borders: [:all])
        ),
        area
      )
    end

    def render_status_bar(frame, area)
      help_text = if @state.search_mode
        "Esc:clear  j/k:move  o:open  s:star  e:archive  m:mute"
      elsif @state.sidebar_focus
        "j/k:move  Enter:select  l/Right:list  Esc:clear filter  q:quit"
      else
        "j/k:move  h:sidebar  /:search  o:open  s:star  e:archive  C-a:archive all  m:mute  r:refresh  R:sync  ?:help  q:quit"
      end
      frame.render_widget(
        @tui.paragraph(text: " #{help_text}", style: @style_muted),
        area
      )
    end

    def render_help_popup(frame, area)
      popup_width = 55
      popup_height = 18
      x = (area.width - popup_width) / 2
      y = (area.height - popup_height) / 2

      popup_area = @tui.rect(x: area.x + x, y: area.y + y, width: popup_width, height: popup_height)

      frame.render_widget(@tui.clear, popup_area)

      help_lines = [
        "",
        "  Navigation",
        "    j / Down     Move down",
        "    k / Up       Move up",
        "    g            Go to first",
        "    G            Go to last",
        "    Tab          Next tab",
        "    Shift+Tab    Previous tab",
        "",
        "  Actions",
        "    o / Enter    Open in browser",
        "    s            Star/unstar",
        "    e            Archive/unarchive",
        "    m            Mute",
        "    /            Search",
        "    r            Refresh from Octobox",
        "",
        "  Press ? or Esc to close"
      ]

      frame.render_widget(
        @tui.paragraph(
          text: help_lines.join("\n"),
          block: @tui.block(title: " Help ", borders: [:all])
        ),
        popup_area
      )
    end

    def handle_input
      event = @tui.poll_event
      log.info "Key: #{event[:code]}" if event.is_a?(Hash) && event[:type] == :key
      case event
      in { type: :key, code: "q" } | { type: :key, code: "c", modifiers: ["ctrl"] }
        return :quit unless @state.search_mode
        exit_search_mode

      in { type: :key, code: "?" }
        @state = @state.with(show_help: !@state.show_help)

      in { type: :key, code: "escape" } | { type: :key, code: "esc" }
        if @state.show_help
          @state = @state.with(show_help: false)
        elsif @state.search_mode
          exit_search_mode
        elsif @state.sidebar_filter
          # Clear filter and reload from cache
          @state = @state.with(sidebar_filter: nil, selected_index: 0)
          reload_notifications
          @table_state.select(0)
        elsif @state.sidebar_focus
          @state = @state.with(sidebar_focus: false)
        end

      in { type: :key, code: "/" }
        enter_search_mode

      in { type: :key, code: "j" } | { type: :key, code: "down" }
        if @state.sidebar_focus
          move_sidebar_selection(1)
        else
          move_selection(1)
        end

      in { type: :key, code: "k" } | { type: :key, code: "up" }
        if @state.sidebar_focus
          move_sidebar_selection(-1)
        else
          move_selection(-1)
        end

      in { type: :key, code: "g" }
        if @state.sidebar_focus
          @sidebar_state.select_first
          @state = @state.with(sidebar_index: 0)
        else
          @table_state.select_first
          @state = @state.with(selected_index: 0)
        end

      in { type: :key, code: "G" } | { type: :key, code: "g", modifiers: ["shift"] }
        if @state.sidebar_focus
          max = [@state.selectable_sidebar_items.size - 1, 0].max
          @sidebar_state.select(max)
          @state = @state.with(sidebar_index: max)
        else
          max = [@state.filtered_notifications.size - 1, 0].max
          @table_state.select(max)
          @state = @state.with(selected_index: max)
        end

      in { type: :key, code: "tab" }
        unless @state.search_mode
          if @state.sidebar_data.any?
            toggle_sidebar_focus
          else
            switch_tab(1)
          end
        end

      in { type: :key, code: "backtab" }
        switch_tab(-1) unless @state.search_mode

      in { type: :key, code: "h" } | { type: :key, code: "left" }
        if !@state.search_mode && @state.sidebar_data.any? && !@state.sidebar_focus
          @state = @state.with(sidebar_focus: true)
        end

      in { type: :key, code: "l" } | { type: :key, code: "right" }
        if @state.sidebar_focus
          @state = @state.with(sidebar_focus: false)
        end

      in { type: :key, code: "o" } | { type: :key, code: "enter" }
        if @state.sidebar_focus
          select_sidebar_filter
        else
          open_selected
        end

      in { type: :key, code: "e" }
        toggle_archive_selected

      in { type: :key, code: "s" }
        toggle_star_selected

      in { type: :key, code: "m" }
        mute_selected

      in { type: :key, code: "a", modifiers: ["ctrl"] }
        archive_all

      in { type: :key, code: "u", modifiers: ["ctrl"] }
        unarchive_all

      in { type: :key, code: "r" }
        fetch_from_octobox unless @state.search_mode

      in { type: :key, code: "R" } | { type: :key, code: "r", modifiers: ["shift"] }
        sync_with_github unless @state.search_mode

      in { type: :key, code: "backspace" }
        handle_backspace if @state.search_mode

      in { type: :key, code: code } if @state.search_mode && code.length == 1
        handle_search_input(code)

      in { type: :none }
        check_for_updates

      else
        # no-op
      end

      nil
    end

    def move_selection(delta)
      notifications = @state.filtered_notifications
      return if notifications.empty?

      current = @table_state.selected || 0
      new_index = (current + delta).clamp(0, notifications.size - 1)
      @table_state.select(new_index)
      @state = @state.with(selected_index: new_index)
    end

    def move_sidebar_selection(delta)
      items = @state.sidebar_items
      return if items.empty?

      current = @sidebar_state.selected || 0
      new_index = current

      # Skip headers and separators when moving
      loop do
        new_index = (new_index + delta).clamp(0, items.size - 1)
        break unless [:header, :separator].include?(items[new_index][:type])
        break if new_index == 0 || new_index == items.size - 1
      end

      # If we landed on a header/separator, try to move past it
      if [:header, :separator].include?(items[new_index][:type])
        new_index = (new_index + delta).clamp(0, items.size - 1)
      end

      @sidebar_state.select(new_index)
      @state = @state.with(sidebar_index: new_index)
    end

    def toggle_sidebar_focus
      @state = @state.with(sidebar_focus: !@state.sidebar_focus)
    end

    def select_sidebar_filter
      items = @state.sidebar_items
      return if items.empty?

      selected_idx = @sidebar_state.selected || 0
      item = items[selected_idx]
      return if item.nil? || item[:type] == :header || item[:type] == :separator

      # Handle tab selection (Inbox/Starred/Archived)
      if item[:type] == :tab
        filter = item[:value]
        @selected_tab = TAB_KEYS.index(filter) || 0
        notifications = @cache.load_notifications(filter: filter)
        @state = @state.with(
          filter: filter,
          notifications: notifications,
          sidebar_filter: nil,
          sidebar_focus: false,
          selected_index: 0,
          search_query: ""
        )
        @table_state.select(0)
        return
      end

      # Handle pinned search selection - filter cached notifications client-side
      if item[:type] == :pinned
        log.info "Applying pinned search: #{item[:label]} (#{item[:value]})"
        # Load all inbox notifications from cache and apply the search filter
        all_notifications = @cache.load_notifications(filter: :inbox)
        search = Models::SearchQuery.new(item[:value])
        filtered = search.filter_notifications(all_notifications)
        log.info "Pinned search matched #{filtered.size} of #{all_notifications.size} notifications"

        @state = @state.with(
          notifications: filtered,
          sidebar_filter: { type: :pinned, value: item[:value], label: item[:label] },
          sidebar_focus: false,
          selected_index: 0
        )
        @table_state.select(0)
        return
      end

      # Toggle filter - if same filter, clear it
      if @state.sidebar_filter &&
         @state.sidebar_filter[:type] == item[:type] &&
         @state.sidebar_filter[:value] == item[:value]
        @state = @state.with(sidebar_filter: nil, sidebar_focus: false, selected_index: 0)
      else
        new_filter = { type: item[:type], value: item[:value] }
        log.info "Setting sidebar filter: #{new_filter.inspect}"
        @state = @state.with(
          sidebar_filter: new_filter,
          sidebar_focus: false,
          selected_index: 0
        )
      end
      @table_state.select(0)
    end

    def switch_tab(delta)
      @selected_tab = (@selected_tab + delta) % TABS.size
      filter = TAB_KEYS[@selected_tab]
      notifications = @cache.load_notifications(filter: filter)
      counts = @cache.counts
      @state = @state.with(filter: filter, notifications: notifications, counts: counts, selected_index: 0, search_query: "")
      @table_state.select(0)
    end

    def enter_search_mode
      @state = @state.with(search_mode: true, search_query: "") unless @state.search_mode
    end

    def exit_search_mode
      @state = @state.with(search_mode: false, search_query: "", selected_index: 0)
      @table_state.select(0)
    end

    def handle_search_input(char)
      @state = @state.with(search_query: @state.search_query + char, selected_index: 0)
      @table_state.select(0)
    end

    def handle_backspace
      return if @state.search_query.empty?
      @state = @state.with(search_query: @state.search_query[0..-2], selected_index: 0)
      @table_state.select(0)
    end

    def check_for_updates
      return if @state.loading || @state.syncing
      return if @last_update_check && (Time.now - @last_update_check) < 1

      @last_update_check = Time.now
      new_counts = @cache.counts
      if new_counts != @state.counts
        reload_notifications
        log.debug "UI updated with new notifications"
      end
    end

    def open_selected
      notification = @state.filtered_notifications[@state.selected_index]
      return unless notification

      log.info "Opening: #{notification.subject_title}"
      log.info "  URL: #{notification.web_url}"

      if notification.web_url
        Services::Browser.open(notification.web_url)

        # Update UI immediately
        @cache.update_notification(notification.id, unread: false)
        reload_notifications

        # API call in background
        Thread.new do
          @client.mark_read(notification.id)
        rescue => e
          log.error "Mark read failed: #{e.message}"
        end
      else
        log.warn "  No URL to open"
      end
    end

    def toggle_archive_selected
      notification = @state.filtered_notifications[@state.selected_index]
      return unless notification

      new_archived = !notification.archived

      # Update cache
      @cache.update_notification(notification.id, archived: new_archived)

      # Update UI - for pinned searches, remove item from list if archiving
      if @state.sidebar_filter && @state.sidebar_filter[:type] == :pinned
        if new_archived
          updated = @state.notifications.reject { |n| n.id == notification.id }
          @state = @state.with(notifications: updated).clamp_selection
          @table_state.select(@state.selected_index)
        end
      else
        reload_notifications
      end

      # API call in background
      Thread.new do
        if new_archived
          @client.archive(notification.id)
        else
          @client.unarchive(notification.id)
        end
      rescue => e
        log.error "Archive toggle failed: #{e.message}"
        # Revert on failure
        @cache.update_notification(notification.id, archived: !new_archived)
        reload_notifications
      end
    end

    def archive_all
      notifications = @state.filtered_notifications
      return if notifications.empty?

      log.info "Archiving all #{notifications.size} visible notifications"

      # Update cache
      ids = notifications.map(&:id)
      ids.each { |id| @cache.update_notification(id, archived: true) }

      # Update UI - for pinned searches, clear the list since all are archived
      if @state.sidebar_filter && @state.sidebar_filter[:type] == :pinned
        @state = @state.with(notifications: [], selected_index: 0)
        @table_state.select(0)
      else
        reload_notifications
      end

      # API call in background
      Thread.new do
        @client.archive(ids)
      rescue => e
        log.error "Archive all failed: #{e.message}"
      end
    end

    def unarchive_all
      notifications = @state.filtered_notifications
      return if notifications.empty?

      log.info "Unarchiving all #{notifications.size} visible notifications"

      # Update UI immediately
      ids = notifications.map(&:id)
      ids.each { |id| @cache.update_notification(id, archived: false) }
      reload_notifications

      # API call in background
      Thread.new do
        @client.unarchive(ids)
      rescue => e
        log.error "Unarchive all failed: #{e.message}"
      end
    end

    def toggle_star_selected
      notification = @state.filtered_notifications[@state.selected_index]
      return unless notification

      new_starred = !notification.starred

      # Update UI immediately
      @cache.update_notification(notification.id, starred: new_starred)
      reload_notifications

      # API call in background
      Thread.new do
        @client.star(notification.id)
      rescue => e
        log.error "Star toggle failed: #{e.message}"
        # Revert on failure
        @cache.update_notification(notification.id, starred: !new_starred)
        reload_notifications
      end
    end

    def mute_selected
      notification = @state.filtered_notifications[@state.selected_index]
      return unless notification

      # Update cache
      @cache.update_notification(notification.id, muted: true, archived: true)

      # Update UI - for pinned searches, remove item from list
      if @state.sidebar_filter && @state.sidebar_filter[:type] == :pinned
        updated = @state.notifications.reject { |n| n.id == notification.id }
        @state = @state.with(notifications: updated).clamp_selection
        @table_state.select(@state.selected_index)
      else
        reload_notifications
      end

      # API call in background
      Thread.new do
        @client.mute(notification.id)
      rescue => e
        log.error "Mute failed: #{e.message}"
        # Revert on failure
        @cache.update_notification(notification.id, muted: false, archived: false)
        reload_notifications
      end
    end

    def reload_notifications
      # Don't reload from cache if we're viewing pinned search results
      # (pinned search results come from API, not cache)
      if @state.sidebar_filter && @state.sidebar_filter[:type] == :pinned
        counts = @cache.counts
        sidebar_data = @cache.sidebar_data
        @state = @state.with(counts: counts, sidebar_data: sidebar_data, pinned_searches: @pinned_searches)
        return
      end

      notifications = @cache.load_notifications(filter: @state.filter)
      counts = @cache.counts
      sidebar_data = @cache.sidebar_data
      @state = @state.with(
        notifications: notifications,
        counts: counts,
        sidebar_data: sidebar_data,
        pinned_searches: @pinned_searches
      ).clamp_selection
      @table_state.select(@state.selected_index)
    end

    def sync_if_stale
      if @cache.stale?
        log.info "Cache is stale, fetching from Octobox"
        fetch_from_octobox
      else
        log.info "Cache is fresh, skipping fetch"
      end
    end

    def fetch_from_octobox
      log.info "Fetching from Octobox..."
      Thread.new do
        do_fetch
      rescue => e
        log.error "Fetch error: #{e.message}"
        log.error e.backtrace.first(5).join("\n")
      end
    end

    def sync_with_github
      log.info "Full sync with GitHub triggered"
      Thread.new do
        do_github_sync
        do_fetch
      rescue => e
        log.error "Sync error: #{e.message}"
        log.error e.backtrace.first(5).join("\n")
      end
    end

    def do_github_sync
      @state = @state.with(syncing: true)
      begin
        @client.sync
      rescue OctoboxTui::Error => e
        log.warn "Sync trigger failed (may already be syncing): #{e.message}"
      end

      # Wait for sync to complete
      attempts = 0
      while @client.syncing? && attempts < 30
        log.info "Waiting for GitHub sync (attempt #{attempts + 1})"
        sleep 1
        attempts += 1
      end
      log.info "GitHub sync done after #{attempts} attempts"
      @state = @state.with(syncing: false)
    end

    def do_fetch
      @state = @state.with(loading: true)

      # Fetch pinned searches
      log.info "Fetching pinned searches..."
      @pinned_searches = @client.pinned_searches
      log.info "Got #{@pinned_searches.size} pinned searches"

      # Fetch all notifications
      log.info "Fetching notifications from Octobox..."
      all_notifications = @client.fetch_all_notifications
      log.info "Got #{all_notifications.size} notifications from Octobox"

      models = all_notifications.map { |data| Models::Notification.from_api(data) }
      @cache.clear_and_save_notifications(models)

      # Build sidebar data from cache
      sidebar_data = @cache.sidebar_data
      log.info "Built sidebar: #{sidebar_data["owner_counts"]&.size} owners, #{sidebar_data["types"]&.size} types"

      @state = @state.with(sidebar_data: sidebar_data, pinned_searches: @pinned_searches)
      reload_notifications
      log.info "Fetch complete, #{@state.notifications.size} notifications in current view"
    rescue => e
      log.error "Fetch failed: #{e.message}"
      log.error e.backtrace.first(5).join("\n")
      @state = @state.with(error: e.message)
    ensure
      @state = @state.with(loading: false)
    end

    def truncate(str, max)
      return "" if str.nil?
      str.length > max ? "#{str[0, max - 3]}..." : str
    end
  end
end
