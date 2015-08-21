ExUnit.start()

defmodule TestHelper do

  def ports do
    %Range{} = Application.get_env(:mock_server, :ports)
  end

  def port_count do
    first..last = ports()
    last - first + 1
  end

  def is_socket(socket) do
    case :inet.sockname(socket) do
      {:ok, {_address, port}} when is_integer(port) and port >= 0 -> true
    end
  end

end
