# frozen_string_literal: true

module ITerm2
  class Window
    attr_reader :client, :id

    def initialize(client:, id:)
      @client = client
      @id = id
    end

    def activate
      client.activate_window(id)
    end

    def tabs
      tab_ids = client.topology.select { |s| s[:window_id] == id }.map { |s| s[:tab_id] }.uniq
      tab_ids.map { |tab_id| Tab.new(client: client, id: tab_id, window_id: id) }
    end

    def create_tab(profile_name: nil)
      result = client.create_tab(window_id: id, profile_name: profile_name)
      Session.new(client: client, id: result[:session_id], window_id: result[:window_id], tab_id: result[:tab_id])
    end

    def to_h
      {
        window_id: id,
        tabs: tabs.map(&:to_h)
      }
    end
  end
end
