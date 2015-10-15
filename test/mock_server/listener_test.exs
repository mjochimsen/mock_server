defmodule ListenerTest do

  @localhost4 {127, 0, 0, 1}
  @localhost6 {0, 0, 0, 0, 0, 0, 0, 1}

  use ExUnit.Case, async: false
  alias MockServer.Listener, as: T

  setup_all do
    Application.stop(:mock_server)
    on_exit(fn ->
      Application.start(:mock_server)
    end)
    :ok
  end

  test "starting and stopping a listener" do
    # Start and stop a listener on localhost
    assert {:ok, listener} = T.start_link(@localhost4, port)
    assert is_pid(listener)
    assert Process.alive?(listener)
    assert :ok = T.stop(listener)
    refute Process.alive?(listener)

    # Again using IPv6
    assert {:ok, listener} = T.start_link(@localhost6, port)
    assert is_pid(listener)
    assert Process.alive?(listener)
    assert :ok = T.stop(listener)
    refute Process.alive?(listener)
  end

  test "getting the address, port, and socket of a listener" do
    # Start listeners for localhost on IPv4 and IPv6
    assert {:ok, listener4} = T.start_link(@localhost4, port)
    assert {:ok, listener6} = T.start_link(@localhost6, port)

    # Get the address of a listener
    assert @localhost4 == T.address(listener4)
    assert @localhost6 == T.address(listener6)

    # Get the port of a listener
    assert port == T.port(listener4)
    assert port == T.port(listener6)

    # Get the socket of a listener
    socket = T.socket(listener4)
    assert TestHelper.is_socket(socket)
    socket = T.socket(listener6)
    assert TestHelper.is_socket(socket)

    # Stop the listeners
    assert :ok == T.stop(listener4)
    assert :ok == T.stop(listener6)
  end

  test "binding and freeing a listener" do
    # Start listeners for localhost on IPv4 and IPv6
    assert {:ok, listener4} = T.start_link(@localhost4, port)
    assert {:ok, listener6} = T.start_link(@localhost6, port)

    # Check that the listeners are free
    assert T.free?(listener4)
    assert T.free?(listener6)

    # Bind the listeners
    assert :ok = T.bind_address(listener4, @localhost4)
    assert :ok = T.bind_address(listener6, @localhost6)

    # Check that the listeners are bound
    assert T.bound?(listener4)
    assert T.bound?(listener6)

    # Get the sockets
    socket4 = T.socket(listener4)
    socket6 = T.socket(listener6)

    # Check that we cannot re-bind the listeners
    assert {:error, :bound} = T.bind_address(listener4, @localhost4)
    assert {:error, :bound} = T.bind_address(listener6, @localhost6)

    # Check that we cannot free the listeners with the wrong socket
    assert {:error, :wrong_socket} = T.free_socket(listener4, socket6)
    assert {:error, :wrong_socket} = T.free_socket(listener6, socket4)

    # Free the listeners
    assert :ok = T.free_socket(listener4, socket4)
    assert :ok = T.free_socket(listener6, socket6)

    # Check that the listeners are freed
    assert T.free?(listener4)
    assert T.free?(listener6)

    # Check that we cannot re-free the listeners
    assert {:error, :freed} = T.free_socket(listener4, socket4)
    assert {:error, :freed} = T.free_socket(listener6, socket6)

    # Check that we cannot bind the listeners with the wrong address
    assert {:error, :wrong_address} = T.bind_address(listener4, @localhost6)
    assert {:error, :wrong_address} = T.bind_address(listener6, @localhost4)

    # Stop the listeners
    assert :ok == T.stop(listener4)
    assert :ok == T.stop(listener6)
  end

  defp port() do
    port.._ = TestHelper.ports()
    port
  end

end
