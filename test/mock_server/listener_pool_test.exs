defmodule ListenerPoolTest do

  use ExUnit.Case, async: false
  alias MockServer.ListenerPool, as: T
  alias TestHelper, as: H

  setup_all do
    Application.stop(:mock_server)
    on_exit(fn ->
      Application.start(:mock_server)
    end)
    :ok
  end

  test "starting and stopping the listener pool" do
    # Test creating and stopping the pool
    assert {:ok, pool} = T.start_link(H.ports())
    assert is_pid(pool)
    assert :ok = T.stop()

    # Do it again
    assert {:ok, pool} = T.start_link(H.ports())
    assert is_pid(pool)
    assert :ok = T.stop()
  end

  test "using the listener pool" do
    # Start the pool
    {:ok, _pool} = T.start_link(H.ports())

    # Check the count of listeners in the pool
    listener_count = H.port_count()
    assert ^listener_count = T.count()

    # Try and get a listener and port number
    assert {:ok, {port, listener}} = T.bind()
    assert port in H.ports()
    assert H.is_socket(listener)

    # Check the listener count again
    assert (listener_count - 1) == T.count()

    # Try and release a port number
    assert :ok == T.free(port)

    # Check the listener count one last time
    assert ^listener_count = T.count()

    # Stop the pool
    :ok = T.stop()
  end

  test "overusing the listener pool" do
    # Start the pool
    {:ok, _pool} = T.start_link(H.ports())

    # Synthesize the bind/free process of a listener with some 'work' done while
    # the listener is bound.  Our 'work' will take between 5 and 20ms, which
    # should cause pressure on the pool without excessively delaying our tests.
    faux_worker = fn ->
      assert {:ok, {port, listener}} = T.bind()
      assert port in H.ports()
      assert H.is_socket(listener)
      :crypto.rand_uniform(5, 20) |> :timer.sleep()
      assert :ok == T.free(port)
    end

    # Spawn twice as many 'workers' as available port numbers
    server_count = H.port_count() * 2
    monitors = for _i <- 1..server_count, do: spawn_monitor(faux_worker)

    # Make sure that we've drained the listener pool.
    :timer.sleep(5)
    assert 0 == T.count()

    # Wait for the 'workers' to finish up.
    finished_workers = for _monitor <- monitors do
      receive do
        {:DOWN, _ref, :process, pid, _} when is_pid(pid) -> pid
      after 50 * server_count ->
        flunk "should have completed all mock clients by now"
      end
    end

    # Double check that all of our monitored pids stopped
    started_workers = Enum.map(monitors, fn {pid, _ref} -> pid end)
    started_workers |> Enum.each(fn pid ->
      refute Process.alive?(pid)
    end)
    assert Enum.sort(started_workers) == Enum.sort(finished_workers)

    # Make sure the pool is full again.
    assert H.port_count() == T.count()

    # Stop the pool
    :ok = T.stop()
  end

end
