defmodule MockServer.ListenerPool do

  @moduledoc """
  `MockServer.ListenerPool` is a pool of listener sockets on TCP ports. We
  include methods to bind and release these ports so they can be used by
  network servers.
  """

  # --- Types ---

  @type ip_address :: :inet.ip_address
  @type port_number :: :inet.port_number
  @type bind_interval :: non_neg_integer
  @type socket :: :inet.socket
  @typep pool_state :: [socket_state]
  @typep socket_state :: %{socket: :inet.socket,
                           addr: ip_address, port: port_number,
                           state: (:free | :bound)}

  # --- API ---

  @doc """
  Start the pool process using a list of `addresses` and `port_numbers`. The
  `port_numbers` list may alternately be a `Range` or a single port number. The
  pool will consist of listener sockets on each port number for each address. If
  no addresses are specified, then the localhost IPv4 and IPv6 addresses are
  used.
  """
  @spec start_link([ip_address], [port_number] | port_number | Range.t) ::
    GenServer.on_start
  def start_link(addresses, port_numbers) when is_list(addresses) and
                                               is_list(port_numbers) do
    GenServer.start_link(__MODULE__, {addresses, port_numbers},
                         name: __MODULE__)
  end
  def start_link(addresses, %Range{} = port_numbers) do
    port_numbers = for port_number <- port_numbers, do: port_number
    start_link(addresses, port_numbers)
  end
  def start_link(addresses, port_number) when is_integer(port_number) do
    start_link(addresses, [port_number])
  end

  @doc """
  Stop the listener pools.
  """
  @spec stop() :: :ok
  def stop() do
    :gen_server.stop(__MODULE__)
  end

  @doc """
  Bind a listener socket on the given `address`. The listener socket will remain
  unavailable until it is freed with a call to `free()`. If all sockets are in
  use, this method will block until one becomes available. This can potentially
  cause a permanent block, so be sure that the listener sockets gets freed.

  While waiting for a listener to become available, this method will wait in
  blocks of `sleep` milliseconds (default 10ms).
  """
  @spec bind(ip_address, bind_interval) :: {:ok, {port_number, socket}}
  def bind(address, sleep \\ 10) do
    case GenServer.call(__MODULE__, {:bind, address}) do
      :empty -> :timer.sleep(sleep); bind(address, sleep)
      {:ok, {port, socket}} -> {:ok, {port, socket}}
    end
  end

  @doc """
  Release the socket listening on the given `address` and `port`. The listener
  socket is made available for binding again on return.
  """
  @spec free(socket) :: :ok
  def free(socket) do
    :ok = GenServer.call(__MODULE__, {:free, socket})
  end

  @doc false
  # Get a count of available listeners. This is used for testing.
  @spec count() :: non_neg_integer
  def count() do
    GenServer.call(__MODULE__, :count)
  end

  # --- GenServer callbacks ---

  use GenServer
  alias MockServer.Listener

  @doc false
  @spec init({[ip_address], [port_number]}) :: {:ok, pool_state}
  def init({addresses, port_numbers}) do
    pool = for addr <- addresses do
      for port <- port_numbers do
        {:ok, listener} = Listener.start_link(addr, port)
        listener
      end
    end
    {:ok, List.flatten(pool)}
  end

  @doc false
  @spec handle_call({:bind, ip_address}, term, pool_state) ::
    {:reply, {:ok, {port, socket}} | :empty, pool_state}
  def handle_call({:bind, address}, _from, pool) do
    case Enum.find(pool, &_attempt_bind(&1, address)) do
      listener when is_pid(listener) ->
        port = Listener.port(listener)
        socket = Listener.socket(listener)
        {:reply, {:ok, {port, socket}}, pool}
      _ ->
        {:reply, :empty, pool}
    end
  end

  @doc false
  @spec handle_call({:free, socket}, term, pool_state) ::
    {:reply, :ok | {:error, :not_in_pool}, pool_state}
  def handle_call({:free, socket}, _from, pool) do
    if Enum.any?(pool, &_attempt_free(&1, socket)) do
      {:reply, :ok, pool}
    else
      {:reply, {:error, :not_in_pool}, pool}
    end
  end

  @doc false
  @spec handle_call(:count, term, pool_state) ::
    {:reply, non_neg_integer, pool_state}
  def handle_call(:count, _from, pool) do
    count = Enum.count(pool, fn (listener) -> Listener.free?(listener) end)
    {:reply, count, pool}
  end

  @doc false
  @spec terminate(term, pool_state) :: :ok
  def terminate(_reason, pool) do
    Enum.each(pool, fn (listener) ->
      :ok = Listener.stop(listener)
    end)
    :ok
  end

  # --- Helpers ---

  defp _attempt_bind(listener, addr) do
    case Listener.bind_address(listener, addr) do
      :ok -> listener
      {:error, _} -> nil
    end
  end

  defp _attempt_free(listener, socket) do
    case Listener.free_socket(listener, socket) do
      :ok -> true
      {:error, _} -> false
    end
  end

end
