defmodule ListenerPoolTest do

  @localhost4 {127, 0, 0, 1}
  @localhost6 {0, 0, 0, 0, 0, 0, 0, 1}
  @localhosts [@localhost4, @localhost6]

  use ExUnit.Case, async: false
  alias MockServer.ListenerPool, as: T
  import TestHelper

  setup_all do
    Application.stop(:mock_server)
    on_exit(fn ->
      Application.start(:mock_server)
    end)
    :ok
  end

  test "starting and stopping the listener pool" do
    # Test creating and stopping the pool
    assert {:ok, pool} = T.start_link(@localhosts, ports())
    assert is_pid(pool)
    assert :ok = T.stop()

    # Do it again
    assert {:ok, pool} = T.start_link(@localhosts, ports())
    assert is_pid(pool)
    assert :ok = T.stop()
  end

  test "using the listener pool" do
    # Start the pool
    {:ok, _pool} = T.start_link(@localhosts, ports())

    # Check the count of listeners in the pool
    listener_count = port_count() * Enum.count(@localhosts)
    assert ^listener_count = T.count()

    # Try and get a listener and port number
    assert {:ok, {port, listener}} = T.bind(@localhost4)
    assert port in ports()
    assert is_socket(listener)

    # Check the listener count again
    assert (listener_count - 1) == T.count()

    # Try and release the listener
    assert :ok == T.free(listener)

    # Check the listener count
    assert ^listener_count = T.count()

    # Try and get a IPv6 listener and port number
    assert {:ok, {port, listener}} = T.bind(@localhost6)
    assert port in ports()
    assert is_socket(listener)

    # Check the listener count again
    assert (listener_count - 1) == T.count()

    # Try and release the listener
    assert :ok == T.free(listener)

    # Check the listener count one last time
    assert ^listener_count = T.count()

    # Stop the pool
    :ok = T.stop()
  end

  test "overusing the listener pool" do
    # Start the pool
    {:ok, _pool} = T.start_link(@localhosts, ports())

    # Spawn twice as many 'workers' per address as available port numbers
    # server_count = port_count() * 1
    monitors =
      for _i <- 1..2 do
        for _j <- 1..port_count() do
          for addr <- @localhosts do
            spawn_monitor(__MODULE__, :faux_worker, [self, addr])
          end
        end
      end
      |> List.flatten
    server_count = Enum.count(monitors)

    # Wait for all the 'workers' to start
    for {pid, _ref} <- monitors do
      receive do
        {:start, ^pid} -> pid
      after 10 * server_count ->
        flunk "should have started all mock clients by now"
      end
    end

    # Make sure that we've drained the listener pool.
    assert 0 == T.count()

    # Wait for the 'workers' to finish up
    for {pid, ref} <- monitors do
      receive do
        {:DOWN, ^ref, :process, ^pid, _} -> pid
      after 20 * server_count ->
        flunk "should have completed all mock clients by now"
      end
    end

    # Double check that all of our monitored pids stopped
    Enum.each(monitors, fn {pid, _ref} ->
      refute Process.alive?(pid)
    end)

    # Make sure the pool is full again.
    assert Enum.count(@localhosts) * port_count() == T.count()

    # Stop the pool
    :ok = T.stop()
  end

  # Synthesize the bind/free process of a listener socket with some 'work' done
  # while the socket is bound.  Our 'work' will take between 5 and 20ms, which
  # should cause pressure on the pool without excessively delaying our tests.
  def faux_worker(test, addr) do
    send(test, {:start, self})
    assert {:ok, {port, socket}} = T.bind(addr)
    assert port in ports()
    assert is_socket(socket)
    :crypto.rand_uniform(5, 20) |> :timer.sleep()
    assert :ok == T.free(socket)
  end

end
