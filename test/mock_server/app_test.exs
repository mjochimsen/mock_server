defmodule AppTest do

  use ExUnit.Case, async: false

  setup_all do
    :ok = Application.ensure_started(:mock_server)
    # Make sure the application is running when we're done
    on_exit(fn -> Application.ensure_started(:mock_server) end)
    :ok
  end

  test "starting and stopping the mock server application" do
    # Stop and restart the application
    assert :ok = Application.stop(:mock_server)
    assert :ok = Application.start(:mock_server)

    # Again
    assert :ok = Application.stop(:mock_server)
    assert :ok = Application.start(:mock_server)
  end
end
