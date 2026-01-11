# frozen_string_literal: true

require "io/console"

module OctoboxTui
  class Config
    DEFAULT_BASE_URL = "https://octobox.io"

    attr_reader :base_url, :data_dir, :db_path
    attr_accessor :api_token

    def initialize
      @data_dir = ENV.fetch("OCTOBOX_TUI_DATA_DIR") { File.join(Dir.home, ".octobox_tui") }
      @db_path = File.join(@data_dir, "cache.db")
      @base_url = ENV.fetch("OCTOBOX_URL") { DEFAULT_BASE_URL }.chomp("/")
      ensure_data_dir
      @api_token = load_api_token
    end

    def load_api_token
      token = ENV["OCTOBOX_API_TOKEN"]
      return token if token && !token.empty?

      token_file = File.join(@data_dir, "token")
      if File.exist?(token_file)
        File.read(token_file).strip
      else
        nil
      end
    end

    def ensure_data_dir
      FileUtils.mkdir_p(@data_dir) unless Dir.exist?(@data_dir)
    end

    def valid?
      api_token && !api_token.empty?
    end

    def token_file_path
      File.join(@data_dir, "token")
    end

    def save_token(token)
      File.write(token_file_path, token)
      File.chmod(0600, token_file_path)
      @api_token = token
    end

    def prompt_for_token
      puts "octobox_tui - A terminal UI for Octobox notifications"
      puts ""
      puts "No API token found. You need to configure your Octobox API token."
      puts ""
      puts "Get your token from: #{@base_url}/settings"
      puts ""
      print "Paste your API token: "
      $stdout.flush

      token = $stdin.gets&.strip
      return nil if token.nil? || token.empty?

      save_token(token)
      puts ""
      puts "Token saved to #{token_file_path}"
      puts ""
      token
    end
  end
end
