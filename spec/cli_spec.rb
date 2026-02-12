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
end
