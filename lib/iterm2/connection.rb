# frozen_string_literal: true

require "socket"
require "securerandom"
require "base64"
require "open3"
require "thread"

module ITerm2
  class Connection
    SOCKET_PATH = File.expand_path("~/Library/Application Support/iTerm2/private/socket")
    TCP_PORT = 1912

    attr_reader :connected

    def initialize(app_name: "iterm2_ruby")
      @app_name = app_name
      @id_counter = 0
      @connected = false
      @dispatch_active = false
      @mutex = Mutex.new
      @write_mutex = Mutex.new
      @pending_responses = {}
      @notification_callback = nil
      @reader_thread = nil
      connect!
    end

    # Send request, get response. Works in both sync and dispatch mode.
    def rpc(request)
      if @dispatch_active
        rpc_dispatched(request)
      else
        rpc_sync(request)
      end
    end

    def next_id
      @mutex.synchronize { @id_counter += 1 }
    end

    # Start background reader thread for notification dispatch
    def start_dispatch_loop!
      return if @dispatch_active

      @dispatch_active = true
      @reader_thread = Thread.new { dispatch_loop }
      @reader_thread.abort_on_exception = true
    end

    # Stop background reader thread cooperatively
    def stop_dispatch_loop!
      return unless @dispatch_active

      @dispatch_active = false
      # Close socket to unblock recv_binary — dispatch_loop rescues IOError and exits
      @socket&.close rescue nil
      @reader_thread&.join(2)
      @reader_thread = nil

      # Wake any blocked RPCs
      @mutex.synchronize do
        @pending_responses.each_value { |q| q.push(nil) }
        @pending_responses.clear
      end
    end

    def dispatch_active?
      @dispatch_active
    end

    # Register callback for incoming notifications
    def on_notification(&block)
      @notification_callback = block
    end

    def close
      if @dispatch_active
        stop_dispatch_loop!
      else
        send_close if @socket && !@socket.closed?
        @socket&.close rescue nil
      end
      @connected = false
    end

    # Make send_binary accessible for client to send subscription requests
    # while dispatch loop handles recv
    def send_request(request)
      encoded = Proto::ClientOriginatedMessage.encode(request)
      @write_mutex.synchronize { send_binary(encoded) }
    end

    private

    # Synchronous RPC — original behavior, used when no dispatch loop
    def rpc_sync(request)
      encoded = Proto::ClientOriginatedMessage.encode(request)
      @write_mutex.synchronize { send_binary(encoded) }
      data = recv_binary
      Proto::ServerOriginatedMessage.decode(data)
    end

    # Dispatch-mode RPC — register queue, send, wait for reader thread to deliver
    def rpc_dispatched(request)
      queue = Queue.new
      request_id = request.id

      @mutex.synchronize { @pending_responses[request_id] = queue }

      encoded = Proto::ClientOriginatedMessage.encode(request)
      @write_mutex.synchronize { send_binary(encoded) }

      response = queue.pop
      raise ConnectionError, "Connection closed during RPC" if response.nil?

      response
    ensure
      @mutex.synchronize { @pending_responses.delete(request_id) }
    end

    # Background loop: read frames, dispatch to RPC queues or notification callback
    def dispatch_loop
      while @dispatch_active
        data = recv_binary
        msg = Proto::ServerOriginatedMessage.decode(data)

        if msg.submessage == :notification
          @notification_callback&.call(msg.notification)
        else
          # RPC response — deliver to waiting queue
          queue = @mutex.synchronize { @pending_responses[msg.id] }
          queue&.push(msg)
        end
      end
    rescue IOError, EOFError, ConnectionError
      # Socket closed — stop dispatching
      @dispatch_active = false
    end

    def connect!
      cookie, key = authenticate
      @socket = open_socket
      websocket_upgrade(cookie, key)
      @connected = true
    end

    def authenticate
      script = "tell application \"iTerm2\" to request cookie and key for app named \"#{@app_name}\""
      stdout, status = Open3.capture2("osascript", "-e", script)
      raise AuthError, "AppleScript auth failed: #{stdout}" unless status.success?

      parts = stdout.strip.split(" ", 2)
      raise AuthError, "Unexpected auth response: #{stdout}" unless parts.size == 2

      parts
    end

    def open_socket
      if File.socket?(SOCKET_PATH)
        UNIXSocket.new(SOCKET_PATH)
      else
        TCPSocket.new("127.0.0.1", TCP_PORT)
      end
    rescue Errno::ECONNREFUSED, Errno::ENOENT => e
      raise ConnectionError, "Cannot connect to iTerm2 API: #{e.message}. Is iTerm2 running with API enabled?"
    end

    def websocket_upgrade(cookie, key)
      ws_key = Base64.strict_encode64(SecureRandom.random_bytes(16))

      headers = [
        "GET / HTTP/1.1",
        "Host: localhost",
        "Upgrade: websocket",
        "Connection: Upgrade",
        "Sec-WebSocket-Key: #{ws_key}",
        "Sec-WebSocket-Version: 13",
        "Sec-WebSocket-Protocol: api.iterm2.com",
        "Origin: ws://localhost/",
        "x-iterm2-cookie: #{cookie}",
        "x-iterm2-key: #{key}",
        "x-iterm2-library-version: ruby #{ITerm2::VERSION}",
        "x-iterm2-advisory-name: #{@app_name}",
        "x-iterm2-disable-auth-ui: true"
      ]

      @socket.write(headers.join("\r\n") + "\r\n\r\n")

      response = read_http_response
      unless response.start_with?("HTTP/1.1 101")
        raise ConnectionError, "WebSocket upgrade failed: #{response.lines.first}"
      end
    end

    def read_http_response
      response = +""
      loop do
        line = @socket.gets
        raise ConnectionError, "Connection closed during handshake" if line.nil?

        response << line
        break if line == "\r\n"
      end
      response
    end

    # WebSocket frame encoding (RFC 6455) - binary, client-masked
    def send_binary(data)
      frame = +""
      frame << [0x82].pack("C") # FIN + opcode 2 (binary)

      if data.bytesize < 126
        frame << [data.bytesize | 0x80].pack("C")
      elsif data.bytesize < 65_536
        frame << [126 | 0x80].pack("C")
        frame << [data.bytesize].pack("n")
      else
        frame << [127 | 0x80].pack("C")
        frame << [data.bytesize].pack("Q>")
      end

      mask = SecureRandom.random_bytes(4)
      frame << mask

      masked = data.bytes.each_with_index.map { |b, i| b ^ mask.getbyte(i % 4) }
      frame << masked.pack("C*")

      @socket.write(frame)
    end

    # Read a single WebSocket frame, return payload
    def recv_binary
      first = @socket.read(2)
      raise ConnectionError, "Connection closed" if first.nil? || first.bytesize < 2

      second = first.getbyte(1)
      masked = (second & 0x80) != 0
      length = second & 0x7F

      if length == 126
        length = @socket.read(2).unpack1("n")
      elsif length == 127
        length = @socket.read(8).unpack1("Q>")
      end

      mask_key = masked ? @socket.read(4) : nil

      payload = @socket.read(length)
      raise ConnectionError, "Incomplete frame" if payload.nil? || payload.bytesize < length

      if mask_key
        payload = payload.bytes.each_with_index.map { |b, i| b ^ mask_key.getbyte(i % 4) }.pack("C*")
      end

      payload
    end

    def send_close
      frame = [0x88, 0x80].pack("CC")
      frame << SecureRandom.random_bytes(4)
      @socket.write(frame)
    rescue IOError, Errno::EPIPE
      # Connection already dead
    end
  end
end
