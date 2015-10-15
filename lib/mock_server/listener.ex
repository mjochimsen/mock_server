defmodule MockServer.Listener do

  @moduledoc """
  A `Listener` process holds the state for a socket in the `ListenerPool`,
  including whether or not the socket has been bound to a `MockServer`.
  """

  @type ip_address :: :inet.ip_address
  @type port_number :: :inet.port_number
  @type socket :: :inet.socket
  @type bind_state :: :bound | :free
  @type listener :: pid
  @type on_start :: {:ok, listener} | {:error, term}
  @type on_bind_address :: :ok | {:error, :wrong_address | :bound}
  @type on_free_socket :: :ok | {:error, :wrong_socket | :freed}

  @doc """
  Start a `Listenter` process linked to the calling process. The `Listener`
  process will contain a listener socket at the given `port` on `address`, and
  will be free for binding to a `MockServer`.
  """
  @spec start_link(ip_address, port_number) :: on_start
  def start_link(address, port) do
    listen_opts = [
      {:ip, address},
      :binary,
      {:active, false},
      {:reuseaddr, true},
    ]
    {:ok, socket} = :gen_tcp.listen(port, listen_opts)
    Agent.start_link(fn -> {socket, address, :free} end)
  end

  @doc """
  Stop the `Listener` process. The listener socket will be closed in the
  process.
  """
  @spec stop(listener) :: :ok
  def stop(listener) do
    socket = Agent.get_and_update(listener, fn
      ({socket, addr, _state}) -> {socket, {nil, addr, :bound}}
    end)
    Agent.stop(listener)
    :inet.close(socket)
    :ok
  end

  @doc """
  Test whether the `Listener` process is bound to a `MockServer`.
  """
  @spec bound?(listener) :: boolean
  def bound?(listener) do
    Agent.get(listener, fn
      ({_socket, _addr, state}) -> state == :bound
    end)
  end

  @doc """
  Test whether the socket of the `listener` process is free to be bound to a
  `MockServer`.
  """
  @spec free?(listener) :: boolean
  def free?(listener) do
    Agent.get(listener, fn
      ({_socket, _addr, state}) -> state == :free
    end)
  end

  @doc """
  Get the IP address of the `listener` process.
  """
  @spec address(listener) :: ip_address
  def address(listener) do
    Agent.get(listener, fn ({_socket, addr, _state}) -> addr end)
  end

  @doc """
  Get the port of the `listener` process.
  """
  @spec port(listener) :: port_number
  def port(listener) do
    Agent.get(listener, fn
      ({socket, _addr, _state}) -> {:ok, port} = :inet.port(socket); port
    end)
  end

  @doc """
  Get the socket of the `listener` process.
  """
  @spec socket(listener) :: socket
  def socket(listener) do
    Agent.get(listener, fn ({socket, _addr, _state}) -> socket end)
  end

  @doc """
  Attempt to bind the `listener` process for use by a `MockServer`. Binding will
  only be successful if the `listener` is listening at `address` and is free.
  Returns `:ok` on success. If the process is already bound returns
  `{:error, :bound}`. If the `address` does not match the listener, then
  `{:error, :wrong_address}` is returned.
  """
  @spec bind_address(listener, ip_address) :: on_bind_address
  def bind_address(listener, address) do
    Agent.get_and_update(listener, fn ({socket, addr, state}) ->
      if (addr == address) do
        if (state == :free) do
          {:ok, {socket, address, :bound}}
        else
          {{:error, :bound}, {socket, addr, state}}
        end
      else
        {{:error, :wrong_address}, {socket, addr, state}}
      end
    end)
  end

  @doc """
  Free the bound `listener` process. The process will only be freed if it was
  bound. Returns `:ok` on success, or `{:error, :freed}` if the process has
  already been freed.
  """
  @spec free_socket(listener, socket) :: on_free_socket
  def free_socket(listener, socket) do
    Agent.get_and_update(listener, fn ({sock, addr, state}) ->
      if (sock == socket) do
        if (state == :bound) do
          {:ok, {socket, addr, :free}}
        else
          {{:error, :freed}, {sock, addr, state}}
        end
      else
        {{:error, :wrong_socket}, {sock, addr, state}}
      end
    end)
  end

end
