defmodule MockDataFeedTest do

  use ExUnit.Case
  alias MockServer.MockDataFeed, as: T

  test "starting a mock data feeder" do
    assert {:ok, feed} = T.start_link()
    assert is_pid(feed)
    assert Process.alive?(feed)
    assert T.dump(feed) == []
  end

  test "loading mock data into a feed" do
    {:ok, feed} = T.start_link()
    assert T.load(feed, pop3_messages) == :ok
    assert T.dump(feed) == pop3_messages
    assert Process.alive?(feed)
  end

  test "loading mock data into a feed from a string" do
    {:ok, feed} = T.start_link()
    assert T.load(feed, """
                  S:+OK POP3 server ready
                  C:QUIT
                  S:+OK POP3 server signing off
                  """) == :ok
    assert T.dump(feed) == pop3_messages
    assert Process.alive?(feed)
  end

  test "loading mock data into a feed from a file" do
    {:ok, feed} = T.start_link()
    assert T.load(feed, :trivial_pop3) == :ok
    assert T.dump(feed) == pop3_messages
    assert Process.alive?(feed)
  end

  test "performing multiple loads into a feed" do
    {:ok, feed} = T.start_link()
    assert T.load(feed, :trivial_pop3) == :ok
    assert T.load(feed, :trivial_pop3) == :ok
    junk_mock = {:server, "-ERR junk server data\r\n"}
    assert T.load(feed, [junk_mock]) == :ok
    assert T.dump(feed) == pop3_messages ++ pop3_messages ++ [junk_mock]
    assert Process.alive?(feed)
  end

  test "that we can't load invalid mock data" do
    {:ok, feed} = T.start_link()
    bad_mock = {:junk, "-ERR junk server data\r\n"}
    assert T.load(feed, [bad_mock]) == {:error, :bad_mock, bad_mock}
    bad_mock = "Who is this coming from?"
    assert T.load(feed, [bad_mock]) == {:error, :bad_mock, bad_mock}
    assert T.dump(feed) == []
    assert Process.alive?(feed)
  end

  test "pulling mock data from a mock data feeder" do
    # Load a feed with mock data from a file.
    {:ok, feed} = T.start_link()
    :ok = T.load(feed, :trivial_pop3)
    assert T.dump(feed) == pop3_messages
    mocks = pop3_messages

    # Pull the greeting from the feed.
    [greeting | mocks] = mocks
    assert T.pull(feed) == greeting
    assert T.dump(feed) == mocks

    # Pull the QUIT from the feed
    [quit | mocks] = mocks
    assert T.pull(feed) == quit
    assert T.dump(feed) == mocks

    # Pull the QUIT response from the feed
    [response | mocks] = mocks
    assert T.pull(feed) == response
    assert T.dump(feed) == mocks

    # Check that the feed is empty and pulls a :close
    assert [] = ^mocks = T.dump(feed)
    assert T.pull(feed) == :close
    assert T.pull(feed) == :close
    assert Process.alive?(feed)
  end

  defp pop3_messages do
    [
      server: "+OK POP3 server ready\r\n",
      client: "QUIT\r\n",
      server: "+OK POP3 server signing off\r\n",
    ]
  end
end
