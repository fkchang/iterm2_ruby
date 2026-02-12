# frozen_string_literal: true

require_relative "iterm2/version"
require_relative "iterm2/proto/api_pb"
require_relative "iterm2/connection"
require_relative "iterm2/client"

module ITerm2
  # Alias the protoc-generated Iterm2 module for internal use
  Proto = ::Iterm2

  class Error < StandardError; end
  class ConnectionError < Error; end
  class AuthError < Error; end
  class RPCError < Error; end
  class NotFoundError < RPCError; end
  class SubscriptionError < Error; end

  # Convenience: open connection, yield client, close
  def self.connect(app_name: "iterm2_ruby")
    client = Client.new(app_name: app_name)
    return client unless block_given?

    yield client
  ensure
    client&.close if block_given?
  end

  # One-shot: list all sessions
  def self.list_sessions
    connect { |c| c.list_sessions }
  end

  # One-shot: flat topology
  def self.topology
    connect { |c| c.topology }
  end

  # One-shot: send text to a session
  def self.send_text(session_id, text)
    connect { |c| c.send_text(session_id, text) }
  end

  # One-shot: read screen contents
  def self.read_screen(session_id, trailing_lines: nil)
    connect { |c| c.read_screen(session_id, trailing_lines: trailing_lines) }
  end

  # One-shot: raise by title pattern
  def self.raise_by_title(pattern)
    connect { |c| c.raise_by_title(pattern) }
  end

  # One-shot: activate a session
  def self.activate_session(session_id)
    connect { |c| c.activate_session(session_id) }
  end

  # One-shot: enriched topology (with cwd, pid, tty)
  def self.topology_enriched
    connect { |c| c.topology_enriched }
  end

  # One-shot: raise by cwd pattern
  def self.raise_by_cwd(pattern)
    connect { |c| c.raise_by_cwd(pattern) }
  end

  # One-shot: session info (tty, pid, cwd, name, job)
  def self.session_info(session_id)
    connect { |c| c.session_info(session_id) }
  end

  # One-shot: get variable
  def self.get_variable(name, **scope)
    connect { |c| c.get_variable(name, **scope) }
  end

  # One-shot: current focus state
  def self.focus
    connect { |c| c.focus }
  end

  # One-shot: prompt state for a session
  def self.get_prompt(session_id)
    connect { |c| c.get_prompt(session_id) }
  end

  # One-shot: get profile properties for a session
  def self.get_profile_property(session_id, *keys)
    connect { |c| c.get_profile_property(session_id, *keys) }
  end

  # One-shot: list all profiles
  def self.list_profiles(properties: nil, guids: nil)
    connect { |c| c.list_profiles(properties: properties, guids: guids) }
  end

  # One-shot: inject data into a session
  def self.inject(session_id, data)
    connect { |c| c.inject(session_id, data) }
  end
end
