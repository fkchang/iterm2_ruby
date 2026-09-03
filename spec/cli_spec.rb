# frozen_string_literal: true

require "spec_helper"

RSpec.describe "iterm2ctl CLI" do
  let(:bin) { File.expand_path("../bin/iterm2ctl", __dir__) }

  describe "version" do
    it "outputs the version" do
      output = `ruby #{bin} version 2>&1`
      expect(output).to include(ITerm2::VERSION)
    end
  end

  describe "help" do
    it "outputs usage information" do
      output = `ruby #{bin} help 2>&1`
      expect(output).to include("Usage:")
      expect(output).to include("Commands:")
    end
  end

  describe "unknown command" do
    it "exits with error" do
      system("ruby #{bin} nonexistent 2>/dev/null")
      expect($?.exitstatus).to eq(1)
    end
  end

  describe "set-window-frame" do
    it "exits with a usage error when args are missing" do
      output = `ruby #{bin} set-window-frame some-window 0 0 900 2>&1`
      expect(output).to include("Usage:")
      expect($?.exitstatus).to eq(1)
    end
  end

  describe "get-window-frame" do
    it "exits with a usage error when the window ID is missing" do
      output = `ruby #{bin} get-window-frame 2>&1`
      expect(output).to include("Usage:")
      expect($?.exitstatus).to eq(1)
    end
  end
end
