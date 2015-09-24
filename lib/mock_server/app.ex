defmodule MockServer.App do

  use Application

  @doc """
  Start the `MockServer` application supervisor. This just starts the processes
  we need to work, in particular the `MockServer.ListenerPool` and
  `MockServer.ServerPool` processes.

  This will normally be started by including the `:mock_server` application
  as a dependency for your application in `mix.exs`. It can be started
  independently, however, by calling `Application.start(:mock_server)`

  The ports used by the `MockServer` can be set in the `:mock_server`
  configuration under the `:ports` key. The key value can be a single port
  number, a range of port numbers, or a list of port numbers.
  """
  def start(_type, []) do
    import Supervisor.Spec

    mock_server_ports = Application.get_env(:mock_server, :ports, :no_ports)
    children = [
      worker(MockServer.ListenerPool, [mock_server_ports]),
      supervisor(MockServer.ServerSupervisor, [])
    ]
    opts = [strategy: :one_for_one, name: MockServer.Supervisor]
    Supervisor.start_link(children, opts)
  end

end
