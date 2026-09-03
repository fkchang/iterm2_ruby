# frozen_string_literal: true

require "spec_helper"

RSpec.describe ITerm2::Client, :live do
  let(:client) { ITerm2::Client.new }

  after { client.close }

  describe "#list_sessions" do
    it "returns a ListSessionsResponse" do
      resp = client.list_sessions
      expect(resp).to respond_to(:windows)
      expect(resp.windows).not_to be_empty
    end
  end

  describe "#topology" do
    it "returns a flat array of session hashes" do
      sessions = client.topology
      expect(sessions).to be_an(Array)
      expect(sessions).not_to be_empty
      expect(sessions.first).to include(:session_id, :window_id, :tab_id, :title)
    end
  end

  describe "#focus" do
    it "returns focus state with expected keys" do
      result = client.focus
      expect(result).to include(:active_session, :active_tab, :active_window, :app_active)
    end
  end

  describe "#get_prompt" do
    it "returns prompt state for a session" do
      session_id = client.topology.first[:session_id]
      result = client.get_prompt(session_id)
      expect(result).to include(:state)
      expect([:editing, :running, :finished, :unavailable]).to include(result[:state])
    end
  end

  describe "#session_info" do
    it "returns tty, pid, cwd, name, job" do
      session_id = client.topology.first[:session_id]
      info = client.session_info(session_id)
      expect(info).to include(:tty, :pid, :cwd, :name, :job)
    end
  end

  describe "#list_profiles" do
    it "returns an array of profile hashes" do
      profiles = client.list_profiles(properties: ["Name", "Guid"])
      expect(profiles).to be_an(Array)
      expect(profiles).not_to be_empty
    end
  end

  describe "#window_frame / #set_window_frame" do
    it "moves and resizes a window, and reads back the new frame" do
      window_id = client.topology.first[:window_id]
      original = client.window_frame(window_id)

      target = { x: original[:x], y: original[:y], width: 900, height: 600 }
      expect(client.set_window_frame(window_id, **target)).to be true

      updated = client.window_frame(window_id)
      expect(updated[:width]).to eq(900)
      expect(updated[:height]).to eq(600)
    ensure
      client.set_window_frame(window_id, **original) if window_id && original
    end
  end

  describe "#set_session_grid_size" do
    it "resizes a session's character grid" do
      session_id = client.topology.first[:session_id]
      original = client.get_property("grid_size", session_id: session_id)

      expect(client.set_session_grid_size(session_id, columns: 100, rows: 30)).to be true

      updated = client.get_property("grid_size", session_id: session_id)
      expect(updated["width"]).to eq(100)
      expect(updated["height"]).to eq(30)
    ensure
      if session_id && original
        client.set_session_grid_size(session_id, columns: original["width"], rows: original["height"])
      end
    end
  end
end
