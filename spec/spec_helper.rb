# frozen_string_literal: true

require "iterm2"

RSpec.configure do |config|
  config.filter_run_excluding :live unless ENV["ITERM2_LIVE_TESTS"]

  # Try to connect once to determine if iTerm2 is available
  config.before(:suite) do
    if ENV["ITERM2_LIVE_TESTS"]
      begin
        conn = ITerm2::Connection.new
        conn.close
      rescue ITerm2::ConnectionError, ITerm2::AuthError => e
        warn "iTerm2 not available (#{e.message}), skipping live tests"
        ENV.delete("ITERM2_LIVE_TESTS")
      end
    end
  end
end
