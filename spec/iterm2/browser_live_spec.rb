# frozen_string_literal: true

require "spec_helper"

RSpec.describe "ITerm2::Client#split_browser_pane", :live do
  it "splits a browser pane beside the calling session, then closes it" do
    here = ITerm2.current_session_id
    skip "not running inside iTerm2" unless here
    skip "iTerm2 browser plugin not available" unless ITerm2::Browser.available?

    client = ITerm2::Client.new
    new_id = nil
    begin
      new_id = client.split_browser_pane(here, "about:blank")

      expect(new_id).to be_a(String)
      expect(client.topology.map { |s| s[:session_id] }).to include(new_id)
      # A plain split would also pass the checks above; this one proves the pane is a browser.
      expect(client.get_profile_property(new_id, "Custom Command", "Initial URL")).to eq(
        "Custom Command" => "Browser",
        "Initial URL" => "about:blank"
      )
    ensure
      client.close_session(new_id, force: true) if new_id
      client.close
    end
  end
end
