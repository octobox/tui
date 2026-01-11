# frozen_string_literal: true

require "test_helper"
require "tempfile"

class TestConfig < Minitest::Test
  def setup
    @temp_dir = Dir.mktmpdir
    @original_env = ENV.to_h
    ENV["OCTOBOX_TUI_DATA_DIR"] = @temp_dir
    ENV.delete("OCTOBOX_API_TOKEN")
    ENV.delete("OCTOBOX_URL")
  end

  def teardown
    FileUtils.rm_rf(@temp_dir)
    ENV.replace(@original_env)
  end

  def test_default_base_url
    config = OctoboxTui::Config.new
    assert_equal "https://octobox.io", config.base_url
  end

  def test_custom_base_url_from_env
    ENV["OCTOBOX_URL"] = "https://my-octobox.example.com"
    config = OctoboxTui::Config.new
    assert_equal "https://my-octobox.example.com", config.base_url
  end

  def test_strips_trailing_slash_from_url
    ENV["OCTOBOX_URL"] = "https://my-octobox.example.com/"
    config = OctoboxTui::Config.new
    assert_equal "https://my-octobox.example.com", config.base_url
  end

  def test_api_token_from_env
    ENV["OCTOBOX_API_TOKEN"] = "test-token-123"
    config = OctoboxTui::Config.new
    assert_equal "test-token-123", config.api_token
  end

  def test_api_token_from_file
    File.write(File.join(@temp_dir, "token"), "file-token-456\n")
    config = OctoboxTui::Config.new
    assert_equal "file-token-456", config.api_token
  end

  def test_env_token_takes_precedence_over_file
    ENV["OCTOBOX_API_TOKEN"] = "env-token"
    File.write(File.join(@temp_dir, "token"), "file-token")
    config = OctoboxTui::Config.new
    assert_equal "env-token", config.api_token
  end

  def test_valid_returns_false_without_token
    config = OctoboxTui::Config.new
    refute config.valid?
  end

  def test_valid_returns_true_with_token
    ENV["OCTOBOX_API_TOKEN"] = "test-token"
    config = OctoboxTui::Config.new
    assert config.valid?
  end

  def test_creates_data_directory
    new_dir = File.join(@temp_dir, "new_subdir")
    ENV["OCTOBOX_TUI_DATA_DIR"] = new_dir
    OctoboxTui::Config.new
    assert Dir.exist?(new_dir)
  end

  def test_db_path
    config = OctoboxTui::Config.new
    assert_equal File.join(@temp_dir, "cache.db"), config.db_path
  end
end
