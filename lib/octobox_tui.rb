# frozen_string_literal: true

require "fileutils"
require "time"

require_relative "octobox_tui/version"
require_relative "octobox_tui/config"
require_relative "octobox_tui/db/schema"
require_relative "octobox_tui/models/notification"
require_relative "octobox_tui/models/app_state"
require_relative "octobox_tui/services/logger"
require_relative "octobox_tui/services/octobox_client"
require_relative "octobox_tui/services/cache"
require_relative "octobox_tui/services/browser"
require_relative "octobox_tui/app"

module OctoboxTui
  class Error < StandardError; end
end
