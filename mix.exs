defmodule MockServer.Mixfile do
  use Mix.Project

  def project do
    [
      app: :mock_server,
      version: "0.2.0",
      elixir: "~> 1.1",
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
