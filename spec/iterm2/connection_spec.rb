# frozen_string_literal: true

require "spec_helper"

RSpec.describe ITerm2::Connection, :live do
  it "connects to iTerm2" do
    conn = ITerm2::Connection.new
    expect(conn.connected).to be true
    conn.close
  end

  it "increments next_id" do
    conn = ITerm2::Connection.new
    id1 = conn.next_id
    id2 = conn.next_id
    expect(id2).to eq(id1 + 1)
    conn.close
  end

  it "closes cleanly" do
    conn = ITerm2::Connection.new
    conn.close
    expect(conn.connected).to be false
  end
end
