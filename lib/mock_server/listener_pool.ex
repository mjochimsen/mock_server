defmodule MockServer.ListenerPool do

  @moduledoc """
  `MockServer.ListenerPool` is a pool of listener sockets on TCP ports. We
  include methods to bind and release these ports so they can be used by
  network servers.
  """

  # --- Types ---

  @type port_number :: :inet.port_number
  @type bind_interval :: non_neg_integer
  @type socket :: :inet.socket
  @typep pool_state :: [socket_state]
  @typep socket_state :: %{socket: :inet.socket, port: port_number, state: (:free | :bound)}

  # --- API ---

  @doc """
  Start the pool process using a list of `port numbers`. The list may
  alternately be a `Range` or a single port number.
  """
  @spec start_link([port_number] | port_number | Range.t) :: GenServer.on_start
  def start_link(port_numbers) when is_list(port_numbers) do
    GenServer.start_link(__MODULE__, port_numbers, name: __MODULE__)
  end
  def start_link(%Range{} = port_numbers) do
    port_numbers = for port_number <- port_numbers, do: port_number
    start_link(port_numbers)
  end
  def start_link(port_number) when is_integer(port_number) do
    start_link([port_number])
  end

  @doc """
  Stop the pool.
  """
  @spec stop() :: :ok
  def stop() do
    :gen_server.stop(__MODULE__)
  end

  @doc """
  Bind a listener socket. The listener socket will remain unavailable until it
  is freed with a call to `free()`. If all sockets are in use, this method will
  block until one becomes available. This can potentially cause a permanent
  block, so be sure that the listener socket gets freed.

  While waiting for a listener to become available, this method will wait in
  blocks of `sleep` milliseconds (default 10ms).
  """
  @spec bind(bind_interval) :: {:ok, {port_number, socket}}
  def bind(sleep \\ 10) do
    case GenServer.call(__MODULE__, :bind) do
      :empty -> :timer.sleep(sleep); bind(sleep)
      {:ok, {port, socket}} -> {:ok, {port, socket}}
    end
  end

  @doc """
  Release the socket listening on the given `port`. The listener socket is
  made available for binding again on return.
  """
  @spec free(port_number) :: :ok
  def free(port) do
    :ok = GenServer.call(__MODULE__, {:free, port})
  end

  @doc false
  # Get a count of the number of available listeners. This is used for testing.
  @spec count() :: non_neg_integer
  def count() do
    GenServer.call(__MODULE__, :count)
  end

  # --- GenServer callbacks ---

  use GenServer

  @localhost {127, 0, 0, 1}

  @doc false
  @spec init([port_number]) :: {:ok, pool_state}
  def init(port_numbers) do
    listen_opts = [:binary | [active: false, ip: @localhost, reuseaddr: true]]
    pool = for port <- port_numbers do
      {:ok, listen_socket} = :gen_tcp.listen(port, listen_opts)
      %{
        socket: listen_socket,
        port: port,
        state: :free
      }
    end
    {:ok, pool}
  end

  @doc false
  @spec handle_call(:bind, term, pool_state) :: {:reply, {:ok, {port, socket}}, pool_state} | {:reply, :empty, pool_state}
  def handle_call(:bind, _from, pool) do
    case Enum.find_index(pool, fn %{state: state} -> state == :free end) do
      i when is_integer(i) ->
        %{port: port, socket: socket} = Enum.at(pool, i)
        pool = List.update_at(pool, i, fn listener ->
          %{listener | state: :bound}
        end)
        {:reply, {:ok, {port, socket}}, pool}
      _ -> {:reply, :empty, pool}
    end
  end

  @doc false
  @spec handle_call({:free, port_number}, term, pool_state) :: {:reply, :ok, pool_state} | {:reply, {:error, :no_port}, pool_state}
  def handle_call({:free, free_port}, _from, pool) do
    case Enum.find_index(pool, fn %{port: port} -> port == free_port end) do
      i when is_integer(i) ->
        pool = List.update_at(pool, i, fn listener ->
          %{listener | state: :free}
        end)
        {:reply, :ok, pool}
      _ -> {:reply, {:error, :no_port}, pool}
    end
  end

  @doc false
  @spec handle_call(:count, term, pool_state) :: {:reply, non_neg_integer, pool_state}
  def handle_call(:count, _from, pool) do
    count = Enum.count(pool, fn %{state: state} -> state == :free end)
    {:reply, count, pool}
  end

  @doc false
  @spec terminate(term, pool_state) :: :ok
  def terminate(_reason, pool) do
    Enum.each(pool, fn %{socket: listen_socket} ->
      :inet.close(listen_socket)
    end)
    :ok
  end

end
