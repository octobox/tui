# frozen_string_literal: true

require "logger"

module OctoboxTui
  module Services
    class << self
      def logger
        @logger ||= begin
          log_path = File.join(Dir.home, ".octobox_tui", "debug.log")
          FileUtils.mkdir_p(File.dirname(log_path))
          logger = Logger.new(log_path, 5, 1_024_000)
          logger.level = ENV["OCTOBOX_TUI_DEBUG"] ? Logger::DEBUG : Logger::INFO
          logger.formatter = proc { |sev, time, _, msg| "[#{time.strftime('%H:%M:%S')}] #{sev}: #{msg}\n" }
          logger
        end
      end
    end
  end
end
