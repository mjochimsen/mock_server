defmodule AppTest do
  use ExUnit.Case

  test "starting and stopping the mock server application" do
    assert :ok = Application.ensure_started(:mock_server)
    assert :ok = Application.stop(:mock_server)
    assert :ok = Application.start(:mock_server)
    assert :ok = Application.stop(:mock_server)
  end
end
