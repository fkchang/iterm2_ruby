# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe ITerm2::Browser do
  describe ".pane_properties" do
    it "marks the pane as a browser and carries the URL" do
      expect(described_class.pane_properties("http://localhost:4579/ambient")).to eq(
        "Custom Command" => "Browser",
        "Initial URL" => "http://localhost:4579/ambient"
      )
    end

    it "keeps the shared profile properties frozen" do
      expect(described_class::PROFILE_PROPERTIES).to be_frozen
    end
  end

  describe ".plugin_installed?" do
    before do
      allow(described_class).to receive(:darwin?).and_return(true)
      stub_const("ITerm2::Browser::PLUGIN_PATHS", [])
    end

    it "is true from a usual install path without asking Spotlight" do
      Dir.mktmpdir do |dir|
        stub_const("ITerm2::Browser::PLUGIN_PATHS", [dir])
        expect(described_class).not_to receive(:capture)
        expect(described_class.plugin_installed?).to be(true)
      end
    end

    it "is true when Spotlight finds the plugin bundle" do
      allow(described_class).to receive(:capture).and_return("/Applications/iTermBrowserPlugin.app\n")
      expect(described_class.plugin_installed?).to be(true)
    end

    it "is false when nothing is found" do
      allow(described_class).to receive(:capture).and_return("")
      expect(described_class.plugin_installed?).to be(false)
    end

    it "is false when mdfind is missing" do
      allow(described_class).to receive(:capture).and_raise(Errno::ENOENT)
      expect(described_class.plugin_installed?).to be(false)
    end

    it "is false when Spotlight does not answer in time" do
      allow(described_class).to receive(:capture).and_raise(Timeout::Error)
      expect(described_class.plugin_installed?).to be(false)
    end

    it "is false off macOS without running anything" do
      allow(described_class).to receive(:darwin?).and_return(false)
      expect(described_class).not_to receive(:capture)
      expect(described_class.plugin_installed?).to be(false)
    end
  end

  describe ".profiles_enabled?" do
    before { allow(described_class).to receive(:darwin?).and_return(true) }

    it "reads an unset preference as enabled" do
      allow(described_class).to receive(:capture).and_return("")
      expect(described_class.profiles_enabled?).to be(true)
    end

    it "reads 0 as disabled" do
      allow(described_class).to receive(:capture).and_return("0\n")
      expect(described_class.profiles_enabled?).to be(false)
    end

    it "reads 1 as enabled" do
      allow(described_class).to receive(:capture).and_return("1\n")
      expect(described_class.profiles_enabled?).to be(true)
    end

    it "treats a failed probe as enabled" do
      allow(described_class).to receive(:capture).and_raise(Errno::ENOENT)
      expect(described_class.profiles_enabled?).to be(true)
    end

    it "treats a timed-out probe as enabled" do
      allow(described_class).to receive(:capture).and_raise(Timeout::Error)
      expect(described_class.profiles_enabled?).to be(true)
    end

    it "is false off macOS without running anything" do
      allow(described_class).to receive(:darwin?).and_return(false)
      expect(described_class).not_to receive(:capture)
      expect(described_class.profiles_enabled?).to be(false)
    end
  end

  # capture is private; these run real child processes, because the point is what happens to them.
  describe ".capture" do
    it "returns the command's stdout" do
      expect(described_class.send(:capture, "echo", "hello", timeout: 2)).to eq("hello\n")
    end

    it "raises Errno::ENOENT for a missing command" do
      expect { described_class.send(:capture, "iterm2-ruby-no-such-command", timeout: 2) }.to raise_error(Errno::ENOENT)
    end

    it "terminates the child when the timeout fires" do
      marker = "7.31"
      expect { described_class.send(:capture, "sleep", marker, timeout: 0.2) }.to raise_error(Timeout::Error)
      # "[s]leep" keeps pgrep's own shell, whose command line holds the pattern, from matching itself
      expect(`pgrep -f "[s]leep #{marker}"`.strip).to be_empty
    end
  end

  describe ".available?" do
    it "needs both the plugin and the setting" do
      allow(described_class).to receive(:plugin_installed?).and_return(true)
      allow(described_class).to receive(:profiles_enabled?).and_return(false)
      expect(described_class.available?).to be(false)

      allow(described_class).to receive(:profiles_enabled?).and_return(true)
      expect(described_class.available?).to be(true)
    end
  end
end

RSpec.describe ITerm2, ".current_session_id" do
  it "returns the GUID after the colon" do
    expect(described_class.current_session_id("ITERM_SESSION_ID" => "w3t1p0:7CE78611-4037")).to eq("7CE78611-4037")
  end

  it "returns nil when unset" do
    expect(described_class.current_session_id({})).to be_nil
  end

  it "returns nil for a value with no colon" do
    expect(described_class.current_session_id("ITERM_SESSION_ID" => "garbage")).to be_nil
  end

  it "returns nil for an empty GUID" do
    expect(described_class.current_session_id("ITERM_SESSION_ID" => "w0t0p0:")).to be_nil
  end
end
