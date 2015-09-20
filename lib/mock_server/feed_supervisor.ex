defmodule MockServer.FeedSupervisor do

  @moduledoc """
  `MockServer.FeedSupervisor` is a supervisor for our `MockDataFeed` processes.
  The mock data feeds will not be restarted if they should crash. This
  supervisor just keeps them in the OTP tree.
  """

  use Supervisor

  @doc """
  Start the FeedSupervisor.
  """
  def start_link() do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc false
  def init([]) do
    children = [
      worker(MockDataFeed, [], restart: :temporary)
    ]
    supervise(children, strategy: :simple_one_for_one)
  end

end
