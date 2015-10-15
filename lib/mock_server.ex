defmodule MockServer do

  @moduledoc """
  A server which will emit data to a client based on the contents of a mock
  file. The server is started using `start/2`, which will spawn a server process
  and return the port the process is connected to. The client can then connect
  to this port and interact with the server just like it would with a real
  server, though the data is pre-determined.
  """

  alias MockServer.MockData
  alias MockServer.MockDataFeed

  # --- Types ---

  @type socket :: :inet.socket
  @type mock_source :: atom | String.t | [MockData.t] | MockDataFeed.t
  @type ip_address :: :inet.ip_address
  @type port_number :: :inet.port_number

  # --- API ---

  @doc """
  Start a mock server. The server will deliver (and expect) the data contained
  in the `mock` file (see `MockServer.MockData` for mock file details). If the
  data received does not match the expected data, then the `MockServer` will
  crash.

  `timeout` can be set to limit the amount of time which the server will wait
  for   a connection and for data to be sent to it. By default it is set to
  `:infinity`.
  """
  @spec start(mock_source, ip_address, timeout) :: {:ok, port_number}
  def start(mock, address, timeout \\ :infinity) do
    # Get port number and listener from pool
    {:ok, {port_number, listen_socket}} = MockServer.ListenerPool.bind(address)
    # Convert the mock source to a mock data feed.
    {:ok, feed} = start_data_feed(mock)
    # Spawn a MockServer to get a connection on the port
    {:ok, _server} = Supervisor.start_child(MockServer.ServerSupervisor,
                                            [feed, listen_socket, timeout])
    # Return the port number to the caller
    {:ok, port_number}
  end

  @spec start_data_feed(mock_source) :: {:ok, MockDataFeed.t}
  defp start_data_feed(mock) when is_pid(mock), do: {:ok, mock}
  defp start_data_feed(mock) do
    {:ok, feed} = MockDataFeed.start()
    case MockDataFeed.load(feed, mock) do
      :ok -> {:ok, feed}
      error -> error
    end
  end

  # --- Supervisor callbacks ---

  @doc false
  @spec start_link(MockDataFeed.t, :inet.socket, timeout) :: {:ok, pid}
  def start_link(feed, listen_socket, timeout) do
    server = spawn_link(__MODULE__, :init, [feed, listen_socket, timeout])
    {:ok, server}
  end

  @doc false
  @spec init(MockDataFeed.t, :inet.socket, timeout) :: :ok
  def init(feed, listen_socket, timeout) do
    # Link the server with the feed
    Process.link(feed)
    # Accept a connection to the listen socket
    {:ok, socket} = :gen_tcp.accept(listen_socket, timeout)
    # Release the listener port
    MockServer.ListenerPool.free(listen_socket)
    # Enter the send/recv loop
    loop(feed, socket, timeout)
    :ok
  end

  # --- Main loop ---

  @spec loop(MockDataFeed.t, :inet.socket, timeout) :: :ok
  defp loop(feed, socket, timeout) do
    # Pull mock data from the feed and take the appropriate action with it.
    case MockDataFeed.pull(feed) do
      {:server, data} ->
        server_send(socket, data)
        loop(feed, socket, timeout)
      {:client, data} ->
        server_recv(socket, data, timeout)
        loop(feed, socket, timeout)
      :close ->
        :ok = :inet.close(socket)
    end
  end

  @spec server_send(:inet.socket, binary) :: :ok
  defp server_send(socket, data) do
    :ok = :gen_tcp.send(socket, data)
  end

  @spec server_recv(:inet.socket, binary, timeout) :: :ok
  defp server_recv(socket, data, timeout) do
    {:ok, ^data} = :gen_tcp.recv(socket, byte_size(data), timeout)
    :ok
  end

end
