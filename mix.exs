defmodule MockServer.Mixfile do
  use Mix.Project

  def project do
    [
      app: :mock_server,
      version: "0.0.1",
      elixir: "~> 1.0",
      build_embedded: Mix.env == :prod,
      start_permanent: Mix.env == :prod,
      deps: deps
    ]
  end

  # Configuration for the application.
  def application do
    [
      applications: [:logger],
      mod: {MockServer.App, []}
    ]
  end

  # Application dependencies. See `mix help deps` for examples and options
  defp deps do
    []
  end

end

defmodule Mix.Tasks.Dialyzer do

  use Mix.Task

  @shortdoc "Run the dialyzer"
  @recursive true

  @moduledoc """
  Run the dialyzer over the generated POP3 application code.
  """

  @spec run(OptionParser.argv) :: :ok
  def run(_) do
    Mix.Task.run("compile")
    ebin_path = Path.join([Mix.Project.app_path, "ebin"])
    Mix.shell.cmd "dialyzer #{ebin_path}"
  end

end
