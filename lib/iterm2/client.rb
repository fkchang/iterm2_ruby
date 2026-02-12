# frozen_string_literal: true

require "json"

module ITerm2
  class Client
    def initialize(app_name: "iterm2_ruby")
      @connection = Connection.new(app_name: app_name)
      @subscribers = {}
      @subscriber_mutex = Mutex.new
    end

    def close
      unsubscribe_all
      @connection.close
    end

    # --- Topology ---

    def list_sessions
      request(:list_sessions_request, Proto::ListSessionsRequest.new).list_sessions_response
    end

    # Returns a flat array of {window_id:, tab_id:, session_id:, title:} hashes
    def topology
      resp = list_sessions
      sessions = []

      resp.windows.each do |window|
        window.tabs.each do |tab|
          extract_sessions(tab.root, sessions, window_id: window.window_id, tab_id: tab.tab_id)
        end
      end

      sessions
    end

    # --- Session Interaction ---

    def send_text(session_id, text, suppress_broadcast: false)
      response = request(:send_text_request, Proto::SendTextRequest.new(
        session: session_id,
        text: text,
        suppress_broadcast: suppress_broadcast
      ))
      response.send_text_response.status == :OK
    end

    def read_screen(session_id, trailing_lines: nil)
      line_range = if trailing_lines
        Proto::LineRange.new(trailing_lines: trailing_lines)
      else
        Proto::LineRange.new(screen_contents_only: true)
      end

      response = request(:get_buffer_request, Proto::GetBufferRequest.new(
        session: session_id,
        line_range: line_range
      ))
      buf = response.get_buffer_response
      raise RPCError, "GetBuffer failed: #{buf.status}" unless buf.status == :OK

      {
        lines: buf.contents.map(&:text),
        cursor: buf.cursor ? { x: buf.cursor.x, y: buf.cursor.y } : nil
      }
    end

    # --- Activate (raise) ---

    def activate_session(session_id, select_tab: true, order_window_front: true)
      response = request(:activate_request, Proto::ActivateRequest.new(
        session_id: session_id,
        select_tab: select_tab,
        select_session: true,
        order_window_front: order_window_front,
        activate_app: Proto::ActivateRequest::App.new(raise_all_windows: false, ignoring_other_apps: true)
      ))
      response.activate_response.status == :OK
    end

    def activate_tab(tab_id, order_window_front: true)
      response = request(:activate_request, Proto::ActivateRequest.new(
        tab_id: tab_id,
        order_window_front: order_window_front,
        activate_app: Proto::ActivateRequest::App.new(raise_all_windows: false, ignoring_other_apps: true)
      ))
      response.activate_response.status == :OK
    end

    def activate_window(window_id)
      response = request(:activate_request, Proto::ActivateRequest.new(
        window_id: window_id,
        order_window_front: true,
        activate_app: Proto::ActivateRequest::App.new(raise_all_windows: false, ignoring_other_apps: true)
      ))
      response.activate_response.status == :OK
    end

    # Raise first session whose title matches pattern
    def raise_by_title(pattern)
      regex = Regexp.new(pattern, Regexp::IGNORECASE)
      match = topology.find { |s| s[:title]&.match?(regex) }
      raise NotFoundError, "No session matching #{pattern.inspect}" unless match

      activate_session(match[:session_id])
    end

    # --- CreateTab ---

    def create_tab(window_id: nil, profile_name: nil)
      req = Proto::CreateTabRequest.new
      req.window_id = window_id if window_id
      req.profile_name = profile_name if profile_name

      resp = request(:create_tab_request, req).create_tab_response
      raise RPCError, "CreateTab failed: #{resp.status}" unless resp.status == :OK

      { window_id: resp.window_id, tab_id: resp.tab_id, session_id: resp.session_id }
    end

    # --- SplitPane ---

    def split_pane(session_id, vertical: true, profile_name: nil, profile_customizations: {})
      props = profile_customizations.map do |key, value|
        Proto::ProfileProperty.new(key: key, json_value: JSON.dump(value))
      end

      split_req = Proto::SplitPaneRequest.new(
        split_direction: vertical ? :VERTICAL : :HORIZONTAL,
        before: false
      )
      split_req.session = session_id if session_id
      split_req.profile_name = profile_name if profile_name
      split_req.custom_profile_properties.replace(props) unless props.empty?

      resp = request(:split_pane_request, split_req).split_pane_response
      raise RPCError, "SplitPane failed: #{resp.status}" unless resp.status == :OK

      resp.session_id.first
    end

    # --- Close ---

    def close_session(session_id, force: false)
      response = request(:close_request, Proto::CloseRequest.new(
        sessions: Proto::CloseRequest::CloseSessions.new(session_ids: [session_id]),
        force: force
      ))
      response.close_response.statuses.first == :OK
    end

    def close_tab(tab_id, force: false)
      response = request(:close_request, Proto::CloseRequest.new(
        tabs: Proto::CloseRequest::CloseTabs.new(tab_ids: [tab_id]),
        force: force
      ))
      response.close_response.statuses.first == :OK
    end

    # --- SetProfileProperty ---

    def set_profile_property(session_id, key, value)
      assignment = Proto::SetProfilePropertyRequest::Assignment.new(
        key: key,
        json_value: JSON.dump(value)
      )

      response = request(:set_profile_property_request, Proto::SetProfilePropertyRequest.new(
        session: session_id,
        assignments: [assignment]
      ))
      response.set_profile_property_response.status == :OK
    end

    # --- Variables ---

    # Get one or more variables from a session, tab, window, or app scope
    # Use "*" to get all variables as a hash
    def get_variables(*names, session_id: nil, tab_id: nil, window_id: nil, app: nil)
      req = Proto::VariableRequest.new(get: names)
      set_variable_scope!(req, session_id: session_id, tab_id: tab_id, window_id: window_id, app: app)

      resp = request(:variable_request, req).variable_response
      raise RPCError, "GetVariables failed: #{resp.status}" unless resp.status == :OK

      if names == ["*"]
        JSON.parse(resp.values.first || "{}")
      elsif names.size == 1
        val = resp.values.first
        val == "null" ? nil : JSON.parse(val)
      else
        names.zip(resp.values).to_h { |name, val| [name, val == "null" ? nil : JSON.parse(val)] }
      end
    end

    # Set user-defined variables (must begin with "user.")
    def set_variables(vars, session_id: nil, tab_id: nil, window_id: nil, app: nil)
      sets = vars.map { |k, v| Proto::VariableRequest::Set.new(name: k, value: JSON.dump(v)) }
      req = Proto::VariableRequest.new(set: sets)
      set_variable_scope!(req, session_id: session_id, tab_id: tab_id, window_id: window_id, app: app)

      request(:variable_request, req).variable_response.status == :OK
    end

    # Convenience: get a single variable
    def get_variable(name, **scope)
      get_variables(name, **scope)
    end

    # Convenience: get session's tty, pid, cwd, name in one call
    def session_info(session_id)
      vars = get_variables("tty", "pid", "path", "name", "jobName", session_id: session_id)
      {
        tty: vars["tty"],
        pid: vars["pid"],
        cwd: vars["path"],
        name: vars["name"],
        job: vars["jobName"]
      }
    end

    # Enriched topology with variables (cwd, pid, tty, job)
    def topology_enriched
      sessions = topology
      sessions.each do |s|
        info = session_info(s[:session_id])
        s.merge!(info)
      end
      sessions
    end

    # Raise first session whose cwd matches pattern
    def raise_by_cwd(pattern)
      regex = Regexp.new(pattern, Regexp::IGNORECASE)
      match = topology_enriched.find { |s| s[:cwd]&.match?(regex) }
      raise NotFoundError, "No session with cwd matching #{pattern.inspect}" unless match

      activate_session(match[:session_id])
    end

    # JXA-compatible topology: returns hash matching get-iterm-topology.js output format.
    # Maps iTerm session GUIDs to Claude session IDs via session-iterm-mapping.json.
    # Used by claude_code_history's SessionAggregator as a drop-in replacement.
    def topology_for_aggregator(mapping_file: nil)
      mapping_file ||= File.expand_path("~/.claude/session-iterm-mapping.json")
      tty_to_claude = build_tty_mapping(mapping_file)

      resp = list_sessions
      tab_index = 0
      windows = resp.windows.map.with_index(1) do |window, widx|
        tabs = window.tabs.map do |tab|
          sessions_in_tab = extract_sessions_flat(tab.root)
          # Use first session in tab (primary session)
          primary = sessions_in_tab.first
          next nil unless primary

          tab_index += 1
          info = session_info(primary[:session_id])
          claude_id = tty_to_claude[info[:tty]]

          # Parse title for project_name, session_number, status
          title = info[:name] || primary[:title] || ""
          project_name, session_number, status = parse_tab_title(title)

          {
            "tab_index" => tab_index,
            "title" => title,
            "project_name" => project_name,
            "session_number" => session_number,
            "status" => status,
            "tty" => info[:tty],
            "cwd" => info[:cwd],
            "session_id" => claude_id,
            "foreground_process" => info[:job],
            "iterm_session_id" => primary[:session_id],
            "iterm_tab_id" => tab.tab_id,
            "pid" => info[:pid]
          }
        end.compact

        {
          "window_index" => widx,
          "window_id" => window.window_id,
          "name" => "Window #{widx}",
          "tabs" => tabs
        }
      end

      { "windows" => windows }
    end

    # --- GetProfileProperty ---

    def get_profile_property(session_id, *keys)
      req = Proto::GetProfilePropertyRequest.new(session: session_id)
      req.keys.replace(keys) unless keys.empty?

      resp = request(:get_profile_property_request, req).get_profile_property_response
      raise RPCError, "GetProfileProperty failed: #{resp.status}" unless resp.status == :OK

      resp.properties.to_h { |p| [p.key, JSON.parse(p.json_value)] }
    end

    # --- ListProfiles ---

    def list_profiles(properties: nil, guids: nil)
      req = Proto::ListProfilesRequest.new
      req.properties.replace(properties) if properties
      req.guids.replace(guids) if guids

      resp = request(:list_profiles_request, req).list_profiles_response
      resp.profiles.map do |profile|
        profile.properties.to_h { |p| [p.key, JSON.parse(p.json_value)] }
      end
    end

    # --- Inject ---

    def inject(session_id, data)
      resp = request(:inject_request, Proto::InjectRequest.new(
        session_id: [session_id],
        data: data.encode("BINARY")
      )).inject_response
      resp.status.first == :OK
    end

    # --- Focus ---

    def focus
      parse_focus_response(request(:focus_request, Proto::FocusRequest.new).focus_response)
    end

    # --- GetPrompt ---

    def get_prompt(session_id)
      resp = request(:get_prompt_request, Proto::GetPromptRequest.new(session: session_id)).get_prompt_response

      case resp.status
      when :OK
        {
          state: resp.prompt_state.to_s.downcase.to_sym,
          command: resp.command.empty? ? nil : resp.command,
          working_directory: resp.working_directory.empty? ? nil : resp.working_directory,
          exit_status: resp.exit_status
        }
      when :PROMPT_UNAVAILABLE
        { state: :unavailable, command: nil, working_directory: nil, exit_status: nil }
      else
        raise RPCError, "GetPrompt failed: #{resp.status}"
      end
    end

    # --- GetProperty ---

    def get_property(name, session_id: nil, window_id: nil)
      req = Proto::GetPropertyRequest.new(name: name)
      req.session_id = session_id if session_id
      req.window_id = window_id if window_id

      resp = request(:get_property_request, req).get_property_response
      raise RPCError, "GetProperty failed: #{resp.status}" unless resp.status == :OK

      JSON.parse(resp.json_value)
    end

    # --- Notifications ---

    def subscribe(notification_type, session_id: nil, &callback)
      ensure_dispatch_loop!

      req = Proto::NotificationRequest.new(
        subscribe: true,
        notification_type: notification_type
      )
      req.session = session_id if session_id

      resp = request(:notification_request, req).notification_response
      unless resp.status == :OK || resp.status == :ALREADY_SUBSCRIBED
        raise SubscriptionError, "Subscribe failed: #{resp.status}"
      end

      key = [session_id, notification_type]
      token = [key, callback]
      @subscriber_mutex.synchronize do
        (@subscribers[key] ||= []) << callback
      end

      token
    end

    def unsubscribe(token)
      key, callback = token
      session_id, notification_type = key

      @subscriber_mutex.synchronize do
        list = @subscribers[key]
        list&.delete(callback)
        @subscribers.delete(key) if list&.empty?
      end

      req = Proto::NotificationRequest.new(
        subscribe: false,
        notification_type: notification_type
      )
      req.session = session_id if session_id

      request(:notification_request, req)
    rescue IOError, ConnectionError
      # Connection may already be closed during shutdown
    end

    def on_focus_change(&block)
      subscribe(:NOTIFY_ON_FOCUS_CHANGE) do |n|
        block.call(parse_focus_notification(n))
      end
    end

    def on_new_session(&block)
      subscribe(:NOTIFY_ON_NEW_SESSION) do |n|
        block.call({ type: :new_session, session_id: n.new_session_notification.session_id })
      end
    end

    def on_session_terminated(&block)
      subscribe(:NOTIFY_ON_TERMINATE_SESSION) do |n|
        block.call({ type: :session_terminated, session_id: n.terminate_session_notification.session_id })
      end
    end

    def on_prompt_change(session_id, &block)
      subscribe(:NOTIFY_ON_PROMPT, session_id: session_id) do |n|
        block.call(parse_prompt_notification(n))
      end
    end

    def on_screen_update(session_id, &block)
      subscribe(:NOTIFY_ON_SCREEN_UPDATE, session_id: session_id) do |n|
        block.call({ type: :screen_update, session: n.screen_update_notification.session })
      end
    end

    def on_layout_change(&block)
      subscribe(:NOTIFY_ON_LAYOUT_CHANGE) do |n|
        block.call({ type: :layout_change })
      end
    end

    private

    def next_id
      @connection.next_id
    end

    def rpc!(envelope)
      response = @connection.rpc(envelope)
      if response.submessage == :error
        raise RPCError, "Server error: #{response.error}"
      end
      response
    end

    def request(field, message)
      envelope = Proto::ClientOriginatedMessage.new(id: next_id, field => message)
      rpc!(envelope)
    end

    def set_variable_scope!(req, session_id: nil, tab_id: nil, window_id: nil, app: nil)
      if session_id
        req.session_id = session_id
      elsif tab_id
        req.tab_id = tab_id
      elsif window_id
        req.window_id = window_id
      elsif app
        req.app = true
      else
        raise ArgumentError, "Must specify session_id:, tab_id:, window_id:, or app: true"
      end
    end

    def extract_sessions(node, sessions, window_id:, tab_id:)
      return unless node

      node.links.each do |link|
        case link.child
        when :session
          s = link.session
          sessions << {
            window_id: window_id,
            tab_id: tab_id,
            session_id: s.unique_identifier,
            title: s.title
          }
        when :node
          extract_sessions(link.node, sessions, window_id: window_id, tab_id: tab_id)
        end
      end
    end

    # Flat extraction without window/tab context (for topology_for_aggregator)
    def extract_sessions_flat(node, sessions = [])
      return sessions unless node

      node.links.each do |link|
        case link.child
        when :session
          s = link.session
          sessions << { session_id: s.unique_identifier, title: s.title }
        when :node
          extract_sessions_flat(link.node, sessions)
        end
      end
      sessions
    end

    # Build tty → Claude session ID mapping from session-iterm-mapping.json
    def build_tty_mapping(mapping_file)
      return {} unless File.exist?(mapping_file)

      mapping = JSON.parse(File.read(mapping_file))
      tty_map = {}
      mapping.each do |claude_id, info|
        tty = info["tty"]
        tty_map[tty] = claude_id if tty && tty != "not a tty"
      end
      tty_map
    rescue JSON::ParserError
      {}
    end

    def ensure_dispatch_loop!
      return if @connection.dispatch_active?

      @connection.on_notification { |notification| dispatch_notification(notification) }
      @connection.start_dispatch_loop!
    end

    def dispatch_notification(notification)
      type = notification_type_for(notification)
      session_id = notification_session_for(notification)

      # Try session-specific subscribers first, then global
      callbacks = @subscriber_mutex.synchronize do
        specific = @subscribers[[session_id, type]] || []
        global = @subscribers[[nil, type]] || []
        specific + global
      end

      callbacks.each do |cb|
        cb.call(notification)
      rescue => e
        $stderr.puts "Notification callback error: #{e.message}"
      end
    end

    NOTIFICATION_FIELDS = {
      focus_changed_notification:     :NOTIFY_ON_FOCUS_CHANGE,
      new_session_notification:       :NOTIFY_ON_NEW_SESSION,
      terminate_session_notification: :NOTIFY_ON_TERMINATE_SESSION,
      prompt_notification:            :NOTIFY_ON_PROMPT,
      screen_update_notification:     :NOTIFY_ON_SCREEN_UPDATE,
      layout_changed_notification:    :NOTIFY_ON_LAYOUT_CHANGE,
      keystroke_notification:         :NOTIFY_ON_KEYSTROKE
    }.freeze

    def notification_type_for(notification)
      NOTIFICATION_FIELDS.each do |field, type|
        return type if notification.send("has_#{field}?")
      end
      nil
    end

    def notification_session_for(notification)
      if notification.has_prompt_notification?
        notification.prompt_notification.session
      elsif notification.has_screen_update_notification?
        notification.screen_update_notification.session
      elsif notification.has_new_session_notification?
        notification.new_session_notification.session_id
      elsif notification.has_terminate_session_notification?
        notification.terminate_session_notification.session_id
      end
    end

    def parse_focus_notification(notification)
      n = notification.focus_changed_notification
      result = { type: :focus }
      result[:app_active] = n.application_active if n.has_application_active?

      if n.has_window?
        w = n.window
        result[:window] = w.window_id
        result[:window_status] = w.window_status.to_s.downcase.to_sym
      end

      result[:selected_tab] = n.selected_tab unless n.selected_tab.empty?
      result[:session] = n.session unless n.session.empty?
      result
    end

    def parse_prompt_notification(notification)
      n = notification.prompt_notification
      result = { type: :prompt, session: n.session }

      if n.has_prompt?
        result[:state] = :prompt
        result[:unique_prompt_id] = n.unique_prompt_id unless n.unique_prompt_id.empty?
      elsif n.has_command_start?
        result[:state] = :command_start
        result[:command] = n.command_start.command unless n.command_start.command.empty?
      elsif n.has_command_end?
        result[:state] = :command_end
        result[:exit_status] = n.command_end.status
      end

      result
    end

    def unsubscribe_all
      tokens = @subscriber_mutex.synchronize do
        @subscribers.flat_map do |key, callbacks|
          callbacks.map { |cb| [key, cb] }
        end
      end

      tokens.each { |token| unsubscribe(token) }
    end

    def parse_focus_response(resp)
      result = { active_session: nil, active_tab: nil, active_window: nil, app_active: false }

      resp.notifications.each do |n|
        result[:app_active] = n.application_active if n.has_application_active?

        if n.has_window?
          w = n.window
          result[:active_window] = w.window_id if w.window_status == :TERMINAL_WINDOW_BECAME_KEY
        end

        result[:active_tab] = n.selected_tab unless n.selected_tab.empty?
        result[:active_session] = n.session unless n.session.empty?
      end

      result
    end

    # Parse title like "cultiv-os #1 [WAITING]" into [project_name, session_number, status]
    def parse_tab_title(title)
      # Match: "project_name #N [STATUS]" or "project_name #N" or just title
      if title =~ /\A(.+?)\s+#(\d+)\s*(?:\[(\w+)\])?\s*\z/
        [$1, $2.to_i, ($3 || "working").downcase]
      else
        [title, nil, nil]
      end
    end
  end
end
