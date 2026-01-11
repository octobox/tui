# frozen_string_literal: true

module OctoboxTui
  module Services
    module Browser
      def self.open(url)
        return unless url

        case RUBY_PLATFORM
        when /darwin/
          system("open", url)
        when /linux/
          system("xdg-open", url)
        when /mswin|mingw/
          system("start", url)
        end
      end
    end
  end
end
