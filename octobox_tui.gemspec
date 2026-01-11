# frozen_string_literal: true

require_relative "lib/octobox_tui/version"

Gem::Specification.new do |spec|
  spec.name = "octobox_tui"
  spec.version = OctoboxTui::VERSION
  spec.authors = ["Andrew Nesbitt"]
  spec.email = ["andrewnez@gmail.com"]

  spec.summary = "A terminal UI for managing Octobox notifications"
  spec.description = "A TUI for Octobox.io. Navigate with keyboard, search to filter, quick actions to archive/star/mute notifications."
  spec.homepage = "https://github.com/andrew/octobox_tui"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore test/ .github/])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "ratatui_ruby", "~> 0.10"
  spec.add_dependency "faraday", "~> 2.0"
  spec.add_dependency "sequel", "~> 5.0"
  spec.add_dependency "sqlite3", "~> 2.0"
end
