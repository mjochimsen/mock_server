defmodule MockServerTest do

  @localhost {127, 0, 0, 1}
  @timeout 1000

  use ExUnit.Case
  alias MockServer, as: T

  test "using a mock server with a mock file" do
    assert {:ok, port} = T.start(:trivial_pop3, @localhost, @timeout)
    assert {:ok, socket} = :gen_tcp.connect(@localhost, port,
                                            [active: false, mode: :binary],
                                            @timeout)
    assert {:ok, greeting} = :gen_tcp.recv(socket, 0, @timeout)
    assert greeting == "+OK POP3 server ready\r\n"
    assert :ok = :gen_tcp.send(socket, "QUIT\r\n")
    assert {:ok, goodbye} = :gen_tcp.recv(socket, 0, @timeout)
    assert goodbye == "+OK POP3 server signing off\r\n"
    assert :ok = :inet.close(socket)
  end

end
