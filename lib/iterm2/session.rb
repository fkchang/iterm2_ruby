# frozen_string_literal: true

module ITerm2
  class Session
    attr_reader :client, :id, :window_id, :tab_id, :title

    def initialize(client:, id:, window_id: nil, tab_id: nil, title: nil)
      @client = client
      @id = id
      @window_id = window_id
      @tab_id = tab_id
      @title = title
    end

    def activate(select_tab: true, order_window_front: true)
      client.activate_session(id, select_tab: select_tab, order_window_front: order_window_front)
    end

    def send_text(text, suppress_broadcast: false)
      client.send_text(id, text, suppress_broadcast: suppress_broadcast)
    end

    def read_screen(trailing_lines: nil)
      client.read_screen(id, trailing_lines: trailing_lines)
    end

    def info
      client.session_info(id)
    end

    def get_variable(name)
      client.get_variable(name, session_id: id)
    end

    def to_h
      {
        window_id: window_id,
        tab_id: tab_id,
        session_id: id,
        title: title
      }
    end
  end
end
