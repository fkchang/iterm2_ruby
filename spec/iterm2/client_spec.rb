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
end
