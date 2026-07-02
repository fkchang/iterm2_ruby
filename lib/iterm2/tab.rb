# frozen_string_literal: true

module ITerm2
  class Tab
    attr_reader :client, :id, :window_id

    def initialize(client:, id:, window_id:)
      @client = client
      @id = id
      @window_id = window_id
    end

    def activate(order_window_front: true)
      client.activate_tab(id, order_window_front: order_window_front)
    end

    def sessions
      client.topology
            .select { |s| s[:tab_id] == id && s[:window_id] == window_id }
            .map { |s| Session.new(client: client, id: s[:session_id], window_id: s[:window_id], tab_id: s[:tab_id], title: s[:title]) }
    end

    def primary_session
      sessions.first
    end

    def close(force: false)
      client.close_tab(id, force: force)
    end

    def to_h
      {
        window_id: window_id,
        tab_id: id,
        sessions: sessions.map(&:to_h)
      }
    end
  end
end
