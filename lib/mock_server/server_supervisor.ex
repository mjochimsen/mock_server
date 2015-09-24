defmodule MockServer.ServerSupervisor do

  @moduledoc """
  `MockServer.ServerSupervisor` is a supervisor for our `MockServer` processes.
  The mock servers will not be restarted if they should crash. This supervisor
  just keeps them in the OTP tree.
  """

  use Supervisor

  @doc """
  Start the ServerSupervisor.
  """
  def start_link() do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc false
  def init([]) do
    children = [
      worker(MockServer, [], restart: :temporary)
    ]
    supervise(children, strategy: :simple_one_for_one)
  end

end
