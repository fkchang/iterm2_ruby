# frozen_string_literal: true

require "rbconfig"
require "timeout"

module ITerm2
  # iTerm2 draws a pane as a web view instead of a shell when its profile's
  # "Custom Command" is the literal string "Browser" -- exactly how iTerm2's own
  # built-in "Web Browser" profile is defined. Overriding that property (plus
  # "Initial URL") on a split produces a browser pane from ANY base profile, so
  # no "Web Browser" profile needs to be installed.
  #
  # iTerm2's own browser feature still needs two things this override cannot
  # bypass: the separately downloaded Browser Plugin, and the "Enable
  # browser-style profiles" Advanced setting (on by default). The probes below
  # check both without opening an API connection.
  module Browser
    PROFILE_PROPERTIES = { "Custom Command" => "Browser" }.freeze

    # The plugin's own CFBundleIdentifier (iterm2.com/browser-plugin.html).
    PLUGIN_BUNDLE_ID = "com.googlecode.iterm2.iTermBrowserPlugin"

    # Persisted key of Settings > Advanced > "Enable browser-style profiles".
    # Unset on a machine that never touched it; iTerm2 treats that as enabled.
    PROFILES_PREF_KEY = "browserProfiles"

    # Where the plugin is normally unzipped. Checked first: a directory test is
    # instant and deterministic, where a cold Spotlight (mdfind) lookup can take
    # seconds and would read as "not installed" if it hit the timeout.
    PLUGIN_PATHS = [
      "/Applications/iTermBrowserPlugin.app",
      File.join(Dir.home, "Applications", "iTermBrowserPlugin.app")
    ].freeze

    PROBE_TIMEOUT = 5
    SPOTLIGHT_TIMEOUT = 15

    # The profile properties that turn a split into a browser pane showing `url`.
    def self.pane_properties(url)
      PROFILE_PROPERTIES.merge("Initial URL" => url)
    end

    # True when the Browser Plugin is installed: in a usual location, or found
    # by bundle identifier wherever it was unzipped. False on any doubt: not
    # macOS, mdfind missing or erroring, timeout.
    def self.plugin_installed?
      return false unless darwin?
      return true if PLUGIN_PATHS.any? { |path| File.directory?(path) }

      found = capture("mdfind", "kMDItemCFBundleIdentifier == '#{PLUGIN_BUNDLE_ID}'", timeout: SPOTLIGHT_TIMEOUT)
      !found.strip.empty?
    rescue StandardError
      false
    end

    # True unless the user explicitly turned off browser-style profiles. An
    # unset preference reads as enabled. Not macOS: false. Any probe failure:
    # true (the setting ships enabled, so doubt should not block).
    def self.profiles_enabled?
      return false unless darwin?

      capture("defaults", "read", "com.googlecode.iterm2", PROFILES_PREF_KEY, timeout: PROBE_TIMEOUT).strip != "0"
    rescue StandardError
      true
    end

    # Whether a browser pane can be expected to work on this machine.
    def self.available?
      plugin_installed? && profiles_enabled?
    end

    def self.darwin?
      RbConfig::CONFIG["host_os"].match?(/darwin/)
    end

    # Runs `command` without a shell and returns its stdout. On timeout the
    # child is terminated, not left running, and Timeout::Error is raised.
    def self.capture(*command, timeout:)
      IO.popen(command, err: File::NULL) do |io|
        Timeout.timeout(timeout) { io.read }
      rescue Timeout::Error
        terminate(io.pid)
        raise
      end
    end

    def self.terminate(pid)
      Process.kill("TERM", pid)
    rescue Errno::ESRCH
      nil # already gone
    end

    private_class_method :darwin?, :capture, :terminate
  end
end
